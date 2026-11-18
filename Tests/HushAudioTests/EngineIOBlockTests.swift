import CoreAudio
import Synchronization
import Testing
@testable import HushAudio

/// Drives the engine's realtime block directly with test buffers (no HAL).
@Suite struct EngineIOBlockTests {
    static let frames = 64

    /// One interleaved stereo buffer of a constant 0.5 in, the same shape out; returns the output.
    func cycle(_ block: AudioDeviceIOBlock) -> [Float] {
        let input = TestBufferList([(channels: 2, samples: [Float](repeating: 0.5, count: Self.frames * 2))])
        let output = TestBufferList([(channels: 2, samples: [Float](repeating: 9, count: Self.frames * 2))])
        var time = AudioTimeStamp()
        block(&time, UnsafePointer(input.list.unsafeMutablePointer), &time, output.list.unsafeMutablePointer, &time)
        return output.samples(0)
    }

    func left(_ samples: [Float]) -> [Float] { stride(from: 0, to: samples.count, by: 2).map { samples[$0] } }

    @Test func meterOnlyEngineStartsSilentWithNothingToFadeOut() {
        let state = EngineSharedState(gain: 1, mode: .meterOnly)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        #expect(cycle(block).allSatisfy { $0 == 0 }, "meter-only output is silence from the first buffer")
        #expect(Float(bitPattern: state.peakBits.load(ordering: .relaxed)) == 0.5, "but it meters the source")
    }

    @Test func controlEngineStartsAtItsGain() {
        let state = EngineSharedState(gain: 0.5, mode: .control)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        #expect(left(cycle(block)).allSatisfy { isApproximatelyEqual($0, 0.25) })
    }

    @Test func switchingToReplayFadesInFromSilenceOverOneBuffer() {
        // meter-only -> control: if the source's mute lands late, the overlap is a crossfade.
        let state = EngineSharedState(gain: 1, mode: .meterOnly)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        _ = cycle(block)
        state.targetGainBits.store(Float(0.5).bitPattern, ordering: .relaxed)
        state.appliedGainBits.store(Float(0).bitPattern, ordering: .relaxed)
        state.replaying.store(true, ordering: .releasing)

        let first = left(cycle(block))
        #expect(first[0] < 0.01, "starts at (about) zero gain")
        #expect(zip(first, first.dropFirst()).allSatisfy { $0 <= $1 }, "rises monotonically")
        #expect(isApproximatelyEqual(first.last!, 0.25, tolerance: 0.01))
        #expect(left(cycle(block)).allSatisfy { isApproximatelyEqual($0, 0.25) }, "then holds the target")
    }

    @Test func stoppingReplayFadesOutOverOneBufferThenGoesSilent() {
        // control -> meter-only: no hard cut to digital silence while the source unmutes.
        let state = EngineSharedState(gain: 0.5, mode: .control)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        _ = cycle(block)
        state.replaying.store(false, ordering: .releasing)

        let fade = left(cycle(block))
        #expect(isApproximatelyEqual(fade[0], 0.25, tolerance: 0.01), "starts where the replay was")
        #expect(zip(fade, fade.dropFirst()).allSatisfy { $0 >= $1 }, "falls monotonically")
        #expect(fade.last! < 0.01)
        _ = state.peakBits.exchange(0, ordering: .relaxed)
        #expect(cycle(block).allSatisfy { $0 == 0 }, "then silence")
        #expect(Float(bitPattern: state.peakBits.load(ordering: .relaxed)) == 0.5, "metering the source")
    }

    @Test func theReplayRampNeverStartsAtAnExactZero() {
        // An exact 0.0 next to Core Audio's takeover drop made the zero run one frame longer.
        let state = EngineSharedState(gain: 1, mode: .meterOnly)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        _ = cycle(block)
        AppAudioEngine.beginReplay(state: state, gain: 0.25)
        let first = cycle(block)
        #expect(first.allSatisfy { $0 != 0 }, "every replayed sample of a non-zero input is non-zero")
    }

    @Test func ioBlockSetsHasRun() {
        let state = EngineSharedState(gain: 1, mode: .meterOnly)
        let before = state.hasRun.load(ordering: .relaxed)
        _ = cycle(AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0))
        let after = state.hasRun.load(ordering: .relaxed)
        #expect(!before)
        #expect(after)
    }

    @Test func takeOverSwitchesOnlyAfterTheIOProcRan() throws {
        let state = EngineSharedState(gain: 1, mode: .meterOnly)
        var clock = 0.0
        var sleeps = 0
        var switchedAfterRun: Bool?
        let ran = try AppAudioEngine.takeOver(
            state: state,
            sleep: {
                clock += $0; sleeps += 1; if sleeps == 3 { state.hasRun.store(true, ordering: .relaxed) }
            },
            now: { clock },
            switchToControl: { switchedAfterRun = state.hasRun.load(ordering: .relaxed) })
        #expect(ran)
        #expect(sleeps == 3, "stops waiting as soon as the IOProc has run")
        #expect(switchedAfterRun == true)
        let replaying = state.replaying.load(ordering: .relaxed)
        #expect(!replaying, "the fresh engine is meter-only until the switch")
    }

    @Test func takeOverFallsBackToSwitchingAfterTheLimit() throws {
        let state = EngineSharedState(gain: 1, mode: .meterOnly)
        var clock = 0.0
        var switched = false
        let ran = try AppAudioEngine.takeOver(
            state: state, limit: 0.2, sleep: { clock += $0 }, now: { clock }, switchToControl: { switched = true })
        #expect(!ran)
        #expect(switched, "switches anyway")
        #expect(clock >= 0.2 && clock < 0.21, "waits about the limit, no longer")
    }

    @Test func rebuiltControlEngineRestartsMeterOnlyUntilTheIOProcRuns() throws {
        // The state a rebuilt control engine starts in: no replay, nothing applied, not yet run.
        let state = EngineSharedState(gain: 0.5, mode: .meterOnly)
        var clock = 0.0
        var sleeps = 0
        var replayingAtSwitch: Bool?
        let ran = try AppAudioEngine.takeOver(
            state: state,
            sleep: {
                clock += $0; sleeps += 1; if sleeps == 2 { state.hasRun.store(true, ordering: .relaxed) }
            },
            now: { clock },
            switchToControl: { replayingAtSwitch = state.replaying.load(ordering: .relaxed) })
        #expect(ran)
        #expect(replayingAtSwitch == false, "the source is still unmuted when the switch starts")
    }

    @Test func overlappedTakeoversWaitOnceInTotal() throws {
        // Engines started together share one wait: once the first is up, the rest are already running.
        let states = (0..<4).map { _ in EngineSharedState(gain: 1, mode: .meterOnly) }
        var clock = 0.0
        var sleeps = 0
        let sleep: (TimeInterval) -> Void = {
            clock += $0; sleeps += 1; if sleeps == 5 { for s in states { s.hasRun.store(true, ordering: .relaxed) } }
        }
        for state in states {
            _ = try AppAudioEngine.takeOver(state: state, sleep: sleep, now: { clock }, switchToControl: {})
        }
        #expect(sleeps == 5, "only the first engine waits")
    }
}

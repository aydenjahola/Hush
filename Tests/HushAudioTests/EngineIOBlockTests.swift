import CoreAudio
import HushCore
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

    // MARK: Takeover diagnostics (#50)

    /// One cycle with the given input on both channels.
    func cycle(_ block: AudioDeviceIOBlock, left samples: [Float]) {
        let input = TestBufferList([(channels: 2, samples: samples.flatMap { [$0, $0] })])
        let output = TestBufferList([(channels: 2, samples: [Float](repeating: 9, count: samples.count * 2))])
        var time = AudioTimeStamp()
        block(&time, UnsafePointer(input.list.unsafeMutablePointer), &time, output.list.unsafeMutablePointer, &time)
    }

    @Test func theTakeoverWatchMeasuresTheTapsZeroRunAcrossReplayedBuffers() {
        let state = EngineSharedState(gain: 1, mode: .meterOnly)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        let silent = [Float](repeating: 0, count: Self.frames)
        let sound = [Float](repeating: 0.5, count: Self.frames)
        cycle(block, left: sound)
        cycle(block, left: sound)
        AppAudioEngine.beginReplay(state: state, gain: 0.5)

        cycle(block, left: [Float](repeating: 0.5, count: Self.frames - 10) + [Float](repeating: 0, count: 10))
        cycle(block, left: silent)  // the HAL's dropped buffer
        cycle(block, left: [Float](repeating: 0, count: 20) + [Float](repeating: 0.5, count: Self.frames - 20))

        #expect(state.watchFirstCycle.load(ordering: .relaxed) == 3, "the first replayed buffer was cycle 3")
        #expect(state.watchLongestZeroRun.load(ordering: .relaxed) == UInt32(10 + Self.frames + 20))
        #expect(state.watchSilentBuffers.load(ordering: .relaxed) == 1)
        #expect(state.watchCyclesLeft.load(ordering: .relaxed) == EngineSharedState.takeoverWatchCycles - 3)
    }

    @Test func theTakeoverWatchStopsAfterItsCycles() {
        let state = EngineSharedState(gain: 1, mode: .meterOnly)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        AppAudioEngine.beginReplay(state: state, gain: 0.5)
        for _ in 0..<EngineSharedState.takeoverWatchCycles { _ = cycle(block) }
        #expect(state.watchCyclesLeft.load(ordering: .relaxed) == 0)
        cycle(block, left: [Float](repeating: 0, count: Self.frames))
        #expect(state.watchSilentBuffers.load(ordering: .relaxed) == 0, "a later silent buffer isn't counted")
        #expect(state.watchLongestZeroRun.load(ordering: .relaxed) == 0)
    }

    @Test func theTakeoverWatchIgnoresMeterOnlyCycles() {
        let state = EngineSharedState(gain: 1, mode: .meterOnly)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        cycle(block, left: [Float](repeating: 0, count: Self.frames))
        #expect(state.watchSilentBuffers.load(ordering: .relaxed) == 0)
        #expect(state.watchCyclesLeft.load(ordering: .relaxed) == 0, "not armed until beginReplay")
    }

    @Test func silentTapInputIsCountedUntilTheFirstSound() {
        let state = EngineSharedState(gain: 1, mode: .meterOnly)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        let silent = [Float](repeating: 0, count: Self.frames)
        cycle(block, left: silent)
        cycle(block, left: silent)
        var heard = state.heardTapInput.load(ordering: .relaxed)
        #expect(!heard)
        #expect(state.silentCyclesBeforeSound.load(ordering: .relaxed) == 2)

        _ = cycle(block)
        cycle(block, left: silent)
        heard = state.heardTapInput.load(ordering: .relaxed)
        #expect(heard)
        #expect(
            state.silentCyclesBeforeSound.load(ordering: .relaxed) == 2, "silence after the first sound isn't counted")
    }

    @Test func aReplayedCycleAlsoCountsAsHearingTheTap() {
        let state = EngineSharedState(gain: 0.5, mode: .control)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        _ = cycle(block)
        let heard = state.heardTapInput.load(ordering: .relaxed)
        #expect(heard)
    }

    @Test func theDiagnosticsLeaveTheReplayUnchanged() {
        // The watch only reads the input: a watched ramp renders exactly as before.
        let state = EngineSharedState(gain: 1, mode: .meterOnly)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        _ = cycle(block)
        AppAudioEngine.beginReplay(state: state, gain: 0.5)
        let first = left(cycle(block))
        #expect(first.allSatisfy { $0 != 0 })
        #expect(isApproximatelyEqual(first.last!, 0.25, tolerance: 0.01))
        #expect(left(cycle(block)).allSatisfy { isApproximatelyEqual($0, 0.25) })
    }

    // MARK: Fast mode toggles (#12)

    @Test func switchingAwayAndBackBeforeTheIOProcRunsKeepsTheReplayAtItsGain() {
        // control -> meter-only -> control within one buffer: the IOProc never saw the meter-only
        // switch, so the replay continues at its gain. Restarting the ramp from g/1000 was an 11 ms dip.
        let state = EngineSharedState(gain: 0.5, mode: .control)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        _ = cycle(block)
        state.replaying.store(false, ordering: .releasing)  // switchMode(.meterOnly)
        AppAudioEngine.beginReplay(state: state, gain: 0.5)  // switchMode(.control)

        #expect(left(cycle(block)).allSatisfy { isApproximatelyEqual($0, 0.25) }, "no dip")
        #expect(left(cycle(block)).allSatisfy { isApproximatelyEqual($0, 0.25) })
    }

    @Test func switchingAwayAndBackToANewGainRampsFromTheRealGain() {
        let state = EngineSharedState(gain: 0.5, mode: .control)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        _ = cycle(block)
        state.replaying.store(false, ordering: .releasing)
        AppAudioEngine.beginReplay(state: state, gain: 1)

        let ramp = left(cycle(block))
        #expect(isApproximatelyEqual(ramp[0], 0.25, tolerance: 0.01), "starts where the replay was")
        #expect(zip(ramp, ramp.dropFirst()).allSatisfy { $0 <= $1 }, "rises monotonically")
        #expect(isApproximatelyEqual(ramp.last!, 0.5, tolerance: 0.01))
    }

    @Test func switchingToControlAndBackBeforeTheIOProcRunsStaysMeterOnly() {
        // meter-only -> control -> meter-only within one buffer: the replay never started, so
        // there is nothing to fade out and the output stays exact silence.
        let state = EngineSharedState(gain: 0.5, mode: .meterOnly)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        _ = cycle(block)
        AppAudioEngine.beginReplay(state: state, gain: 0.5)
        state.replaying.store(false, ordering: .releasing)
        _ = state.peakBits.exchange(0, ordering: .relaxed)

        #expect(cycle(block).allSatisfy { $0 == 0 })
        #expect(peak(state) == 0.5, "still metering the source")
        #expect(Float(bitPattern: state.appliedGainBits.load(ordering: .relaxed)) == 0)
    }

    @Test func aSwitchBackAfterTheFadeOutRampsUpFromAlmostZero() {
        // control -> meter-only, picked up by the IOProc (it fades out), then -> control: the
        // source was unmuted in between, so the replay starts over, from g/1000 and not an exact 0.
        let state = EngineSharedState(gain: 0.5, mode: .control)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        _ = cycle(block)
        state.replaying.store(false, ordering: .releasing)
        _ = cycle(block)  // the fade-out
        AppAudioEngine.beginReplay(state: state, gain: 0.5)

        let rise = left(cycle(block))
        #expect(rise[0] > 0 && rise[0] < 0.01, "starts at g/1000")
        #expect(zip(rise, rise.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(isApproximatelyEqual(rise.last!, 0.25, tolerance: 0.01))
    }

    @Test func beginReplayLeavesTheAppliedGainToTheIOProc() {
        // A fade-out cycle that read `replaying == false` stores applied = 0 at its end. If
        // beginReplay also wrote the applied gain, whichever store landed last would win. It
        // doesn't, so the order no longer matters: the next replayed cycle ramps from g/1000.
        let state = EngineSharedState(gain: 0.5, mode: .control)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        _ = cycle(block)
        state.replaying.store(false, ordering: .releasing)
        let appliedBefore = state.appliedGainBits.load(ordering: .relaxed)
        AppAudioEngine.beginReplay(state: state, gain: 0.5)  // lands while the fade-out cycle runs
        #expect(state.appliedGainBits.load(ordering: .relaxed) == appliedBefore, "untouched")
        // The fade-out cycle's own stores, landing after beginReplay's:
        state.appliedGainBits.store(Float(0).bitPattern, ordering: .relaxed)
        state.replayedLastCycle.store(false, ordering: .relaxed)

        let rise = left(cycle(block))
        #expect(rise.allSatisfy { $0 > 0 }, "no exact zero")
        #expect(rise[0] < 0.01)
        #expect(isApproximatelyEqual(rise.last!, 0.25, tolerance: 0.01))
    }

    // MARK: Muted fast path (#5)

    func fastPathCycles(_ state: EngineSharedState) -> UInt32 { state.mutedFastPathCycles.load(ordering: .relaxed) }
    func peak(_ state: EngineSharedState) -> Float { Float(bitPattern: state.peakBits.load(ordering: .relaxed)) }

    @Test func aSettledGainOfZeroWritesExactZerosOnTheFastPath() {
        let state = EngineSharedState(gain: 0, mode: .control)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        let out = cycle(block)
        #expect(out.allSatisfy { $0 == 0 && $0.sign == .plus }, "every sample is an exact +0, the stale 9s overwritten")
        #expect(fastPathCycles(state) == 1)
        #expect(Float(bitPattern: state.appliedGainBits.load(ordering: .relaxed)) == 0, "stays settled at 0")
    }

    @Test func theFastPathSkipsTheSampleLoop() {
        // The full render multiplies each input sample by 0, which turns a NaN into NaN. The fast
        // path never reads the input, so a NaN in shows that the sample loop didn't run.
        let state = EngineSharedState(gain: 0, mode: .control)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        let input = TestBufferList([(channels: 2, samples: [Float](repeating: .nan, count: Self.frames * 2))])
        let output = TestBufferList([(channels: 2, samples: [Float](repeating: 9, count: Self.frames * 2))])
        var time = AudioTimeStamp()
        block(&time, UnsafePointer(input.list.unsafeMutablePointer), &time, output.list.unsafeMutablePointer, &time)
        #expect(output.samples(0).allSatisfy { $0 == 0 })
    }

    @Test func aRampToZeroTakesTheFastPathOnlyOnceItHasSettled() {
        let state = EngineSharedState(gain: 0.5, mode: .control)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        _ = cycle(block)
        state.targetGainBits.store(Float(0).bitPattern, ordering: .relaxed)  // mute

        let fade = left(cycle(block))
        #expect(fastPathCycles(state) == 0, "the ramp down renders in full")
        #expect(isApproximatelyEqual(fade[0], 0.25, tolerance: 0.01), "starts where the replay was")
        #expect(zip(fade, fade.dropFirst()).allSatisfy { $0 >= $1 }, "falls monotonically")
        #expect(fade.last! < 0.01)

        #expect(cycle(block).allSatisfy { $0 == 0 })
        #expect(fastPathCycles(state) == 1, "the next buffer, settled at 0, takes the fast path")
    }

    @Test func unmutingRampsUpFromZero() {
        let state = EngineSharedState(gain: 0, mode: .control)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        _ = cycle(block)
        _ = cycle(block)
        state.targetGainBits.store(Float(0.5).bitPattern, ordering: .relaxed)  // unmute

        let rise = left(cycle(block))
        #expect(fastPathCycles(state) == 2, "the ramp up renders in full")
        #expect(rise[0] == 0, "starts from the settled 0")
        #expect(zip(rise, rise.dropFirst()).allSatisfy { $0 <= $1 }, "rises monotonically")
        #expect(isApproximatelyEqual(rise.last!, 0.25, tolerance: 0.01))
        #expect(left(cycle(block)).allSatisfy { isApproximatelyEqual($0, 0.25) }, "then holds the target")
    }

    @Test func unmutingToABoostRampsUpThroughTheLimiter() {
        // The limiter keeps no state, so resuming from the fast path straight into a boost is the
        // same as resuming from a rendered 0: a clean ramp that the limiter caps below 1.
        let state = EngineSharedState(gain: 0, mode: .control)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        _ = cycle(block)
        state.targetGainBits.store(Float(2).bitPattern, ordering: .relaxed)

        let rise = left(cycle(block))
        #expect(rise[0] == 0)
        #expect(zip(rise, rise.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(rise.allSatisfy { $0 < 1 })
        #expect(left(cycle(block)).allSatisfy { isApproximatelyEqual($0, SoftLimiter.process(1)) })
    }

    @Test func theMutedMeterMatchesTheFullRender() {
        // Before the fast path, a muted control engine metered render(gain 0 -> 0): input × 0.
        let input = TestBufferList([(channels: 2, samples: [Float](repeating: 0.5, count: Self.frames * 2))])
        let output = TestBufferList([(channels: 2, samples: [Float](repeating: 9, count: Self.frames * 2))])
        let rendered = BufferRouting.render(input: input.list, output: output.list, startGain: 0, endGain: 0)

        let state = EngineSharedState(gain: 0, mode: .control)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        _ = cycle(block)
        #expect(fastPathCycles(state) == 1)
        #expect(peak(state) == rendered)
        #expect(peak(state) == 0, "a muted strip shows no level")
    }

    @Test func theMeterDuringTheRampDownStillReportsTheFade() {
        let state = EngineSharedState(gain: 0.5, mode: .control)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        _ = cycle(block)
        _ = state.peakBits.exchange(0, ordering: .relaxed)
        state.targetGainBits.store(Float(0).bitPattern, ordering: .relaxed)
        _ = cycle(block)
        #expect(isApproximatelyEqual(peak(state), 0.25, tolerance: 0.01), "the fade's first sample")
        _ = state.peakBits.exchange(0, ordering: .relaxed)
        _ = cycle(block)
        #expect(peak(state) == 0)
    }

    @Test func theFastPathAdvancesHasRunAndTheCycleCounter() {
        let state = EngineSharedState(gain: 0, mode: .control)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        for _ in 0..<3 { _ = cycle(block) }
        let hasRun = state.hasRun.load(ordering: .relaxed)
        #expect(hasRun)
        #expect(state.ioCycles.load(ordering: .relaxed) == 3)
        #expect(fastPathCycles(state) == 3)
    }

    @Test func takingOverAMutedAppGoesStraightToTheFastPath() {
        // meter-only -> control at gain 0: the IOProc's ramp starts at target/1000, which is 0, so there is nothing to ramp.
        let state = EngineSharedState(gain: 0, mode: .meterOnly)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        _ = cycle(block)
        #expect(fastPathCycles(state) == 0, "meter-only never takes the fast path")
        #expect(peak(state) == 0.5, "meter-only meters the source")
        AppAudioEngine.beginReplay(state: state, gain: 0)
        _ = state.peakBits.exchange(0, ordering: .relaxed)
        #expect(cycle(block).allSatisfy { $0 == 0 })
        #expect(fastPathCycles(state) == 1)
        #expect(peak(state) == 0)
    }

    @Test func stoppingAMutedReplayGoesBackToMeteringTheSource() {
        let state = EngineSharedState(gain: 0, mode: .control)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        _ = cycle(block)
        state.replaying.store(false, ordering: .releasing)
        #expect(cycle(block).allSatisfy { $0 == 0 })
        #expect(fastPathCycles(state) == 1, "meter-only uses its own silent path")
        #expect(peak(state) == 0.5)
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

    @Test func takeOverLeavesTheSourceUnmutedUntilTheIOProcRan() throws {
        // Static takeOver on a meter-only state: the switch (replay, then mute) only starts once
        // the IOProc has run, and not before.
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

    @Test func overlappedTakeoversWaitNoLongerThanTheSlowestFirstRun() throws {
        // Four engines started together, each running at a different simulated time. Taking them
        // over in order waits for the slowest once, not the sum of the delays.
        let delays = [0.010, 0.030, 0.020, 0.050]
        let states = delays.map { _ in EngineSharedState(gain: 1, mode: .meterOnly) }
        var clock = 0.0
        let sleep: (TimeInterval) -> Void = { step in
            clock += step
            for (state, delay) in zip(states, delays) where clock >= delay {
                state.hasRun.store(true, ordering: .relaxed)
            }
        }
        for state in states {
            let ran = try AppAudioEngine.takeOver(state: state, sleep: sleep, now: { clock }, switchToControl: {})
            #expect(ran)
        }
        #expect(clock >= 0.050 && clock < 0.060, "total wait \(clock)s is about the slowest delay, not the sum (0.11)")
    }

    @MainActor @Test func factoryStopsTheEngineAndRethrowsWhenTakeOverFails() {
        struct Boom: Error {}
        var stopped = false
        #expect(throws: Boom.self) {
            try AppAudioEngine.takeOverOrStop(takeOver: { throw Boom() }, stop: { stopped = true })
        }
        #expect(stopped)
    }
}

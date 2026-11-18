import CoreAudio
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

    @Test func theIOProcCountsOnlyBuffersItReplays() {
        let state = EngineSharedState(gain: 0.5, mode: .meterOnly)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        _ = cycle(block)
        #expect(state.replayBuffers.load(ordering: .relaxed) == 0, "metering isn't replaying")

        state.replaying.store(true, ordering: .releasing)
        _ = cycle(block)
        _ = cycle(block)
        #expect(state.replayBuffers.load(ordering: .relaxed) == 2)

        state.replaying.store(false, ordering: .releasing)
        _ = cycle(block)  // the fade-out buffer
        _ = cycle(block)
        #expect(state.replayBuffers.load(ordering: .relaxed) == 2, "fading out and silence don't count")
    }

    @Test func theReplayRampNeverStartsAtAnExactZero() {
        // An exact 0.0 next to the source's mute made a 513-frame zero run on real hardware.
        let state = EngineSharedState(gain: 1, mode: .meterOnly)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        let clock = FakeSwitchClock()
        _ = try? AppAudioEngine.replayThenMute(
            state: state, gain: 0.25, timeout: .milliseconds(50), interval: .microseconds(500),
            now: { clock.now }, pause: { clock.advance($0) }, mute: {})
        let first = cycle(block)
        #expect(first.allSatisfy { $0 != 0 }, "every replayed sample of a non-zero input is non-zero")
    }
}

/// A clock the switch sequencing reads; `pause` advances it (and can run IO cycles).
final class FakeSwitchClock: @unchecked Sendable {
    private(set) var now = ContinuousClock.now
    func advance(_ duration: Duration) { now = now.advanced(by: duration) }
}

/// meter-only -> control: the replay goes on first and the source is muted only once the IOProc
/// has rendered a replay buffer, so the mute and the first replayed buffer reach the output together.
@Suite struct ReplayThenMuteTests {
    @Test func muteWaitsForTheIOProcToRenderAReplayBuffer() throws {
        let state = EngineSharedState(gain: 1, mode: .meterOnly)
        let block = AppAudioEngine.makeIOBlock(state: state, tapBufferOffset: 0)
        let clock = FakeSwitchClock()
        var events: [String] = []
        var pauses = 0

        let acknowledged = try AppAudioEngine.replayThenMute(
            state: state, gain: 0.25, timeout: .milliseconds(50), interval: .microseconds(500),
            now: { clock.now },
            pause: { duration in
                clock.advance(duration)
                pauses += 1
                if pauses == 3 {  // the HAL's IO thread runs a cycle while the main thread waits
                    _ = EngineIOBlockTests().cycle(block)
                    events.append("cycle")
                }
            },
            mute: { events.append("mute") })

        #expect(acknowledged)
        #expect(events == ["cycle", "mute"], "muted only after a replay buffer was rendered")
        let replaying = state.replaying.load(ordering: .relaxed)
        let target = Float(bitPattern: state.targetGainBits.load(ordering: .relaxed))
        #expect(replaying)
        #expect(target == 0.25)
    }

    @Test func noAcknowledgementMutesAnywayAtTheTimeout() throws {
        let state = EngineSharedState(gain: 1, mode: .meterOnly)
        let clock = FakeSwitchClock()
        let start = clock.now
        var muted = false

        let acknowledged = try AppAudioEngine.replayThenMute(
            state: state, gain: 0.25, timeout: .milliseconds(50), interval: .microseconds(500),
            now: { clock.now }, pause: { clock.advance($0) }, mute: { muted = true })

        #expect(!acknowledged)
        #expect(muted, "the app must still be muted if the IOProc is stalled")
        #expect(clock.now - start >= .milliseconds(50))
        #expect(clock.now - start < .milliseconds(51), "bounded: the main thread isn't held longer")
    }

    @Test func aFailedMuteTurnsTheReplayOffAgain() {
        let state = EngineSharedState(gain: 1, mode: .meterOnly)
        let clock = FakeSwitchClock()
        #expect(throws: FakeHALError.self) {
            try AppAudioEngine.replayThenMute(
                state: state, gain: 0.25, timeout: .milliseconds(1), interval: .microseconds(500),
                now: { clock.now }, pause: { clock.advance($0) }, mute: { throw FakeHALError() })
        }
        let replaying = state.replaying.load(ordering: .relaxed)
        #expect(!replaying)
    }
}

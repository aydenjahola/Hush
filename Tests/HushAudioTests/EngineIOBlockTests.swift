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
}

import Testing
@testable import HushAudio

@Suite struct BufferRoutingTests {
    @Test func interleavedStereoToInterleavedStereo() {
        let input = TestBufferList([(2, [0.2, -0.2, 0.4, -0.4])])
        let output = TestBufferList([(2, [9, 9, 9, 9])])
        let peak = BufferRouting.render(input: input.list, output: output.list, startGain: 0.5, endGain: 0.5)
        let result = output.samples(0)
        #expect(zip(result, [0.1, -0.1, 0.2, -0.2]).allSatisfy { isApproximatelyEqual($0, $1) })
        #expect(isApproximatelyEqual(peak, 0.2))
    }

    @Test func interleavedStereoToNonInterleavedStereo() {
        let input = TestBufferList([(2, [0.1, 0.2, 0.3, 0.4])])
        let output = TestBufferList([(1, [9, 9]), (1, [9, 9])])
        _ = BufferRouting.render(input: input.list, output: output.list, startGain: 1, endGain: 1)
        #expect(output.samples(0) == [0.1, 0.3])
        #expect(output.samples(1) == [0.2, 0.4])
    }

    @Test func monoInputFeedsEveryOutputChannel() {
        let input = TestBufferList([(1, [0.5, 0.25])])
        let output = TestBufferList([(2, [9, 9, 9, 9])])
        _ = BufferRouting.render(input: input.list, output: output.list, startGain: 1, endGain: 1)
        #expect(output.samples(0) == [0.5, 0.5, 0.25, 0.25])
    }

    @Test func monoInputFeedsEveryNonInterleavedOutputChannel() {
        let input = TestBufferList([(1, [0.5, 0.25])])
        let output = TestBufferList([(1, [9, 9]), (1, [9, 9]), (1, [9, 9])])
        _ = BufferRouting.render(input: input.list, output: output.list, startGain: 1, endGain: 1)
        #expect(output.samples(0) == [0.5, 0.25])
        #expect(output.samples(1) == [0.5, 0.25])
        #expect(output.samples(2) == [0.5, 0.25])
    }

    @Test func stereoInputFillsOnlyFirstTwoOfSixInterleavedChannels() {
        let input = TestBufferList([(2, [0.1, 0.2, 0.3, 0.4])])
        let output = TestBufferList([(6, [Float](repeating: 9, count: 12))])
        let peak = BufferRouting.render(input: input.list, output: output.list, startGain: 1, endGain: 1)
        #expect(output.samples(0) == [0.1, 0.2, 0, 0, 0, 0, 0.3, 0.4, 0, 0, 0, 0])
        #expect(isApproximatelyEqual(peak, 0.4))
    }

    @Test func stereoInputFillsOnlyFirstTwoOfSixNonInterleavedChannels() {
        let input = TestBufferList([(2, [0.1, 0.2, 0.3, 0.4])])
        let output = TestBufferList((0..<6).map { _ in (1, [Float(9), 9]) })
        _ = BufferRouting.render(input: input.list, output: output.list, startGain: 1, endGain: 1)
        #expect(output.samples(0) == [0.1, 0.3])
        #expect(output.samples(1) == [0.2, 0.4])
        for channel in 2..<6 {
            #expect(output.samples(channel) == [0, 0])
        }
    }

    @Test func extraOutputFramesAreZeroed() {
        let input = TestBufferList([(1, [0.5])])
        let output = TestBufferList([(1, [9, 9, 9])])
        _ = BufferRouting.render(input: input.list, output: output.list, startGain: 1, endGain: 1)
        #expect(output.samples(0) == [0.5, 0, 0])
    }

    @Test func noInputMeansSilence() {
        let input = TestBufferList([])
        let output = TestBufferList([(2, [9, 9])])
        let peak = BufferRouting.render(input: input.list, output: output.list, startGain: 1, endGain: 1)
        #expect(output.samples(0) == [0, 0])
        #expect(peak == 0)
    }

    @Test func peakScansAllInputBuffers() {
        let input = TestBufferList([(1, [0.1, -0.3]), (1, [0.2, -0.6])])
        #expect(isApproximatelyEqual(BufferRouting.peak(of: input.list), 0.6))
    }

    @Test func silenceZeroesEveryBuffer() {
        let output = TestBufferList([(1, [1, 2]), (1, [3, 4])])
        BufferRouting.silence(output.list)
        #expect(output.samples(0) == [0, 0])
        #expect(output.samples(1) == [0, 0])
    }

    @Test func renderSkipsLeadingNonTapInputBuffers() {
        let input = TestBufferList([(1, [0.9, 0.9]), (2, [0.1, 0.2, 0.3, 0.4])])
        let output = TestBufferList([(2, [9, 9, 9, 9])])
        let peak = BufferRouting.render(input: input.list, output: output.list, startGain: 1, endGain: 1, firstInputBuffer: 1)
        #expect(output.samples(0) == [0.1, 0.2, 0.3, 0.4])
        #expect(isApproximatelyEqual(peak, 0.4))
    }

    @Test func peakSkipsLeadingNonTapInputBuffers() {
        let input = TestBufferList([(1, [0.9, -0.9]), (1, [0.1, -0.3])])
        #expect(isApproximatelyEqual(BufferRouting.peak(of: input.list, firstInputBuffer: 1), 0.3))
    }

    @Test func offsetPastAllBuffersMeansSilence() {
        let input = TestBufferList([(1, [0.9, 0.9])])
        let output = TestBufferList([(1, [9, 9])])
        let peak = BufferRouting.render(input: input.list, output: output.list, startGain: 1, endGain: 1, firstInputBuffer: 1)
        #expect(output.samples(0) == [0, 0])
        #expect(peak == 0)
    }
}

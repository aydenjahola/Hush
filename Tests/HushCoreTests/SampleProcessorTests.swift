import Testing
@testable import HushCore

@Suite struct SampleProcessorTests {
    @Test func constantGainScalesSamplesAndReportsPeak() {
        let input: [Float] = [0.2, -0.4, 0.6]
        var output = [Float](repeating: 9, count: 3)
        let peak = input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                SampleProcessor.apply(
                    startGain: 0.5, endGain: 0.5,
                    input: inPtr.baseAddress!, inputStride: 1,
                    output: outPtr.baseAddress!, outputStride: 1,
                    frameCount: 3)
            }
        }
        #expect(isApproximatelyEqual(output[0], 0.1))
        #expect(isApproximatelyEqual(output[1], -0.2))
        #expect(isApproximatelyEqual(output[2], 0.3))
        #expect(isApproximatelyEqual(peak, 0.3))
    }

    @Test func boostIsSoftLimited() {
        let input: [Float] = [0.8]
        var output: [Float] = [0]
        _ = input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                SampleProcessor.apply(
                    startGain: 2, endGain: 2,
                    input: inPtr.baseAddress!, inputStride: 1,
                    output: outPtr.baseAddress!, outputStride: 1,
                    frameCount: 1)
            }
        }
        #expect(output[0] < 1.0)
        #expect(output[0] > 0.9)
    }

    @Test func stridedProcessingLeavesOtherChannelsAlone() {
        let input: [Float] = [1, 9, 1, 9]
        var output: [Float] = [0, 7, 0, 7]
        _ = input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                SampleProcessor.apply(
                    startGain: 0.5, endGain: 0.5,
                    input: inPtr.baseAddress!, inputStride: 2,
                    output: outPtr.baseAddress!, outputStride: 2,
                    frameCount: 2)
            }
        }
        #expect(output == [0.5, 7, 0.5, 7])
    }

    @Test func gainRampsLinearlyAcrossBuffer() {
        let input: [Float] = [1, 1, 1, 1]
        var output = [Float](repeating: 0, count: 4)
        _ = input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                SampleProcessor.apply(
                    startGain: 0, endGain: 1,
                    input: inPtr.baseAddress!, inputStride: 1,
                    output: outPtr.baseAddress!, outputStride: 1,
                    frameCount: 4)
            }
        }
        #expect(isApproximatelyEqual(output[0], 0))
        #expect(isApproximatelyEqual(output[1], 0.25))
        #expect(isApproximatelyEqual(output[2], 0.5))
        #expect(isApproximatelyEqual(output[3], 0.75))
    }

    @Test func zeroFramesIsANoOp() {
        let input: [Float] = [1]
        var output: [Float] = [5]
        let peak = input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                SampleProcessor.apply(
                    startGain: 1, endGain: 1,
                    input: inPtr.baseAddress!, inputStride: 1,
                    output: outPtr.baseAddress!, outputStride: 1,
                    frameCount: 0)
            }
        }
        #expect(peak == 0)
        #expect(output == [5])
    }

    @Test func peakFindsLargestMagnitude() {
        let input: [Float] = [0.1, -0.7, 0.3, 0.9]
        let peak = input.withUnsafeBufferPointer {
            SampleProcessor.peak(input: $0.baseAddress!, stride: 1, frameCount: 3)
        }
        #expect(isApproximatelyEqual(peak, 0.7))
    }
}

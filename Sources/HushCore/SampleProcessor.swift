/// Realtime-safe sample loops. No allocation, no locks, no Objective-C.
package enum SampleProcessor {
    /// Multiplies `frameCount` samples by a gain that ramps linearly from
    /// `startGain` toward `endGain`, soft-limits when boosting, writes them to
    /// `output`, and returns the largest output magnitude.
    package static func apply(
        startGain: Float,
        endGain: Float,
        input: UnsafePointer<Float>,
        inputStride: Int,
        output: UnsafeMutablePointer<Float>,
        outputStride: Int,
        frameCount: Int
    ) -> Float {
        guard frameCount > 0 else { return 0 }
        let limit = startGain > 1 || endGain > 1
        let step = (endGain - startGain) / Float(frameCount)
        var gain = startGain
        var peak: Float = 0
        for frame in 0..<frameCount {
            var sample = input[frame * inputStride] * gain
            if limit { sample = SoftLimiter.process(sample) }
            output[frame * outputStride] = sample
            peak = max(peak, abs(sample))
            gain += step
        }
        return peak
    }

    /// Largest magnitude among `frameCount` samples spaced `stride` apart.
    package static func peak(input: UnsafePointer<Float>, stride: Int, frameCount: Int) -> Float {
        guard frameCount > 0 else { return 0 }
        var peak: Float = 0
        for frame in 0..<frameCount {
            peak = max(peak, abs(input[frame * stride]))
        }
        return peak
    }
}

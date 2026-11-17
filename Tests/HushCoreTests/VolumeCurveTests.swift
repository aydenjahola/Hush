import Testing
@testable import HushCore

@Suite struct VolumeCurveTests {
    @Test func knownPoints() {
        #expect(VolumeCurve.gain(percent: 0) == 0)
        #expect(isApproximatelyEqual(VolumeCurve.gain(percent: 50), 0.25))
        #expect(VolumeCurve.gain(percent: 100) == 1)
        #expect(isApproximatelyEqual(VolumeCurve.gain(percent: 150), 1.5))
        #expect(isApproximatelyEqual(VolumeCurve.gain(percent: 200), 2.0))
    }

    @Test func increasesMonotonically() {
        var previous = VolumeCurve.gain(percent: 0)
        for percent in 1...200 {
            let gain = VolumeCurve.gain(percent: percent)
            #expect(gain > previous, "gain(\(percent)) should exceed gain(\(percent - 1))")
            previous = gain
        }
    }

    @Test func negativePercentIsSilent() {
        #expect(VolumeCurve.gain(percent: -10) == 0)
    }
}

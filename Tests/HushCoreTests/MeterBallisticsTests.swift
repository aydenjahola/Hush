import Testing
@testable import HushCore

@Suite struct MeterBallisticsTests {
    @Test func risesInstantlyToNewPeak() {
        #expect(MeterBallistics.next(displayed: 0.1, peak: 0.8, elapsed: 0.033) == 0.8)
    }

    @Test func decaysTwentyDecibelsPerSecond() {
        #expect(isApproximatelyEqual(MeterBallistics.next(displayed: 1, peak: 0, elapsed: 1), 0.1))
        #expect(isApproximatelyEqual(MeterBallistics.next(displayed: 1, peak: 0, elapsed: 0.5), 0.316_227_8, tolerance: 1e-4))
    }

    @Test func holdsDecayedLevelWhenPeakIsLower() {
        let next = MeterBallistics.next(displayed: 1, peak: 0.05, elapsed: 1)
        #expect(isApproximatelyEqual(next, 0.1))
    }

    @Test func snapsTinyLevelsToZero() {
        #expect(MeterBallistics.next(displayed: 0.000_05, peak: 0, elapsed: 0.033) == 0)
    }

    @Test func fractionUsesSixtyDecibelScale() {
        #expect(MeterBallistics.fraction(forLevel: 0) == 0)
        #expect(MeterBallistics.fraction(forLevel: 1) == 1)
        #expect(MeterBallistics.fraction(forLevel: 2) == 1)
        #expect(MeterBallistics.fraction(forLevel: 0.001) == 0)
        #expect(isApproximatelyEqual(MeterBallistics.fraction(forLevel: 0.1), 2.0 / 3.0, tolerance: 1e-4))
    }
}

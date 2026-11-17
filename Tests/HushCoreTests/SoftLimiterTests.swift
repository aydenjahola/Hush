import Testing
@testable import HushCore

@Suite struct SoftLimiterTests {
    @Test func identityAtOrBelowThreshold() {
        for x: Float in [0, 0.25, -0.5, 0.9, -0.9] {
            #expect(SoftLimiter.process(x) == x)
        }
    }

    @Test func outputStaysBelowOneUpToTen() {
        var x: Float = 0.901
        while x <= 10 {
            let y = SoftLimiter.process(x)
            #expect(y < 1.0, "process(\(x)) = \(y)")
            #expect(y >= SoftLimiter.threshold)
            x += 0.01
        }
    }

    @Test func symmetricForNegativeInput() {
        for x: Float in [0.95, 1.2, 3, 10] {
            #expect(SoftLimiter.process(-x) == -SoftLimiter.process(x))
        }
    }

    @Test func increasesMonotonically() {
        var previous = SoftLimiter.process(0.9)
        var x: Float = 0.91
        while x < 1.5 {
            let y = SoftLimiter.process(x)
            #expect(y >= previous)
            previous = y
            x += 0.01
        }
    }
}

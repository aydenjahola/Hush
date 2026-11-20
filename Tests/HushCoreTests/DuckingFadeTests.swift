import Foundation
import Testing

@testable import HushCore

@Suite struct DuckingFadeTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func close(_ a: Float, _ b: Float, tolerance: Float = 0.0001) -> Bool { abs(a - b) <= tolerance }

    @Test func anIdleFadeIsAtFullLevel() {
        let fade = DuckingFade()
        #expect(fade.multiplier(at: at(0)) == 1)
        #expect(fade.target == 1)
        #expect(fade.isIdle(at: at(0)))
    }

    @Test func fadingDownTakesTheDownDuration() {
        var fade = DuckingFade()
        fade.retarget(0.09, at: at(0))
        #expect(fade.multiplier(at: at(0)) == 1)
        #expect(!fade.isSettled(at: at(0.2)))
        let middle = fade.multiplier(at: at(DuckingFade.downDuration / 2))
        #expect(close(middle, (1 + 0.09) / 2), "smoothstep passes the midpoint halfway")
        #expect(fade.multiplier(at: at(DuckingFade.downDuration)) == 0.09)
        #expect(fade.multiplier(at: at(5)) == 0.09)
        #expect(fade.isSettled(at: at(DuckingFade.downDuration)))
        #expect(!fade.isIdle(at: at(5)), "settled while ducked is not idle")
    }

    @Test func fadingUpTakesTheUpDuration() {
        var fade = DuckingFade()
        fade.retarget(0.09, at: at(0))
        fade.retarget(1, at: at(10))
        #expect(fade.multiplier(at: at(10)) == 0.09)
        #expect(fade.multiplier(at: at(10 + DuckingFade.downDuration)) < 1, "up is slower than down")
        #expect(fade.multiplier(at: at(10 + DuckingFade.upDuration)) == 1)
        #expect(fade.isIdle(at: at(10 + DuckingFade.upDuration)))
    }

    @Test func theCurveMovesSteadilyWithoutOvershoot() {
        var fade = DuckingFade()
        fade.retarget(0.09, at: at(0))
        var previous: Float = 1
        for step in 1...40 {
            let value = fade.multiplier(at: at(Double(step) * DuckingFade.downDuration / 40))
            #expect(value <= previous)
            #expect(value >= 0.09)
            previous = value
        }
    }

    @Test func theCurveStartsAndEndsGently() {
        // Smoothstep: the first and last steps are much smaller than the middle ones.
        var fade = DuckingFade()
        fade.retarget(0, at: at(0))
        let step = DuckingFade.downDuration / 20
        let first = 1 - fade.multiplier(at: at(step))
        let middle = fade.multiplier(at: at(9 * step)) - fade.multiplier(at: at(10 * step))
        #expect(first < middle / 5)
    }

    @Test func reversingMidFadeStartsFromTheCurrentLevel() {
        var fade = DuckingFade()
        fade.retarget(0.09, at: at(0))
        let current = fade.multiplier(at: at(0.2))
        fade.retarget(1, at: at(0.2))
        #expect(fade.multiplier(at: at(0.2)) == current, "no jump")
        #expect(fade.multiplier(at: at(0.2 + DuckingFade.upDuration)) == 1)
    }

    @Test func changingTheAmountWhileDuckedFadesToTheNewLevel() {
        var fade = DuckingFade()
        fade.retarget(0.09, at: at(0))
        fade.retarget(0.25, at: at(5))
        #expect(fade.multiplier(at: at(5)) == 0.09)
        #expect(fade.multiplier(at: at(5 + DuckingFade.upDuration)) == 0.25)
        fade.retarget(0, at: at(10))
        #expect(fade.multiplier(at: at(10 + DuckingFade.downDuration)) == 0)
    }

    @Test func retargetingToTheSameTargetKeepsTheFadeGoing() {
        var fade = DuckingFade()
        fade.retarget(0.09, at: at(0))
        let before = fade
        fade.retarget(0.09, at: at(0.2))
        #expect(fade == before)
    }

    @Test func endTimeIsWhenTheFadeSettles() {
        var fade = DuckingFade()
        #expect(fade.endTime == nil)
        fade.retarget(0.5, at: at(1))
        #expect(fade.endTime == at(1 + DuckingFade.downDuration))
    }

    @Test func targetsAreClampedToAValidGain() {
        var fade = DuckingFade()
        fade.retarget(-1, at: at(0))
        #expect(fade.target == 0)
        fade.retarget(3, at: at(1))
        #expect(fade.target == 1)
    }
}

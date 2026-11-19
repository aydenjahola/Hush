import Foundation
import Testing

@testable import HushCore

@Suite struct CallActivityTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    @Test func anAppCountsOnceItHasCapturedForTheStartDelay() {
        var activity = CallActivity()
        activity.update(capturing: ["zoom"], at: at(0))
        #expect(activity.activeApps(at: at(0)).isEmpty)
        #expect(activity.activeApps(at: at(0.49)).isEmpty)
        #expect(activity.activeApps(at: at(CallActivity.startDelay)) == ["zoom"])
    }

    @Test func aMomentaryProbeNeverCounts() {
        var activity = CallActivity()
        activity.update(capturing: ["zoom"], at: at(0))
        activity.update(capturing: [], at: at(0.3))
        #expect(activity.activeApps(at: at(0.3)).isEmpty)
        #expect(activity.activeApps(at: at(1)).isEmpty)
        #expect(activity.nextChange(after: at(0.3)) == nil)
    }

    @Test func anAppKeepsCountingForTheStopDelayAfterItStops() {
        var activity = CallActivity()
        activity.update(capturing: ["zoom"], at: at(0))
        activity.update(capturing: [], at: at(10))
        #expect(activity.activeApps(at: at(10)) == ["zoom"])
        #expect(activity.activeApps(at: at(11.9)) == ["zoom"])
        #expect(activity.activeApps(at: at(10 + CallActivity.stopDelay)).isEmpty)
    }

    @Test func resumingWithinTheStopDelayKeepsCountingWithoutANewStartDelay() {
        // Mute and unmute in a call app can stop and restart input.
        var activity = CallActivity()
        activity.update(capturing: ["zoom"], at: at(0))
        activity.update(capturing: [], at: at(10))
        activity.update(capturing: ["zoom"], at: at(11))
        #expect(activity.activeApps(at: at(11)) == ["zoom"])
        #expect(activity.activeApps(at: at(11.2)) == ["zoom"])
        #expect(activity.activeApps(at: at(30)) == ["zoom"])
    }

    @Test func resumingJustBeforeTheHoldEndsKeepsCountingPastIt() {
        // Stop at 0 (held until 2.0), resume at 1.9: the app must not drop out between 2.0 and 2.4.
        var activity = CallActivity()
        activity.update(capturing: ["zoom"], at: at(-10))
        activity.update(capturing: [], at: at(0))
        activity.update(capturing: ["zoom"], at: at(1.9))
        #expect(activity.activeApps(at: at(2.0)) == ["zoom"])
        #expect(activity.activeApps(at: at(2.1)) == ["zoom"])
        #expect(activity.activeApps(at: at(2.5)) == ["zoom"])
        #expect(activity.nextChange(after: at(1.9)) == nil, "already counting, nothing pending")
    }

    @Test func stoppingDuringTheHoldOfAnEarlierStopExtendsTheHold() {
        var activity = CallActivity()
        activity.update(capturing: ["zoom"], at: at(0))
        activity.update(capturing: [], at: at(10))
        activity.update(capturing: ["zoom"], at: at(11))
        activity.update(capturing: [], at: at(11.1))
        #expect(activity.activeApps(at: at(12.5)) == ["zoom"])
        #expect(activity.activeApps(at: at(13.1)).isEmpty)
    }

    @Test func appsAreTrackedSeparately() {
        var activity = CallActivity()
        activity.update(capturing: ["zoom"], at: at(0))
        activity.update(capturing: ["zoom", "teams"], at: at(1))
        #expect(activity.activeApps(at: at(1)) == ["zoom"])
        #expect(activity.activeApps(at: at(1.5)) == ["zoom", "teams"])
        activity.update(capturing: ["teams"], at: at(5))
        #expect(activity.activeApps(at: at(8)) == ["teams"])
    }

    @Test func nextChangeIsTheEarliestPendingStartOrStop() {
        var activity = CallActivity()
        #expect(activity.nextChange(after: at(0)) == nil)
        activity.update(capturing: ["zoom"], at: at(0))
        #expect(activity.nextChange(after: at(0)) == at(CallActivity.startDelay))
        #expect(activity.nextChange(after: at(1)) == nil, "already counting, nothing pending")
        activity.update(capturing: [], at: at(5))
        #expect(activity.nextChange(after: at(5)) == at(5 + CallActivity.stopDelay))
        activity.update(capturing: ["teams"], at: at(6))
        #expect(activity.nextChange(after: at(6)) == at(6 + CallActivity.startDelay))
    }

    @Test func resetForgetsEverything() {
        var activity = CallActivity()
        activity.update(capturing: ["zoom"], at: at(0))
        activity.reset()
        #expect(activity.activeApps(at: at(5)).isEmpty)
        #expect(activity.nextChange(after: at(0)) == nil)
    }

    @Test func repeatingTheSameStateChangesNothing() {
        var activity = CallActivity()
        activity.update(capturing: ["zoom"], at: at(0))
        activity.update(capturing: ["zoom"], at: at(0.4))
        #expect(activity.activeApps(at: at(0.5)) == ["zoom"], "the start time is the first report, not the latest")
    }
}

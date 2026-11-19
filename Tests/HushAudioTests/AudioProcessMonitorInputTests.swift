import CoreAudio
import Testing
@testable import HushAudio

/// Microphone input tracking (`kAudioProcessPropertyIsRunningInput`), which ducking uses to tell
/// when a call app is in a call. It's opt-in: with input polling nil, nothing about input is read.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AudioProcessMonitorInputTests {
    @Test func inputIsNotTrackedUntilAsked() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.hal.capturing[10] = true
        h.start()

        #expect(h.app(100)?.isCapturingInput == false)
        #expect(h.hal.inputReads.isEmpty)
        #expect(!h.hal.selectors(on: 10).contains(kAudioProcessPropertyIsRunningInput))
        #expect(h.monitor.inputPollTargets.isEmpty)
    }

    @Test func trackingReadsEveryObjectOnceAndListensForChanges() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.hal.add(11, pid: 101)
        h.hal.capturing[10] = true
        h.start()

        h.monitor.setInputPolling(.off)
        #expect(h.published.count == 1, "never publishes from inside setInputPolling")
        h.scheduler.runAll()

        #expect(h.app(100)?.isCapturingInput == true)
        #expect(h.app(101)?.isCapturingInput == false)
        #expect(Set(h.hal.inputReads) == [10, 11])
        #expect(h.hal.inputReads.count == 2)
        #expect(h.hal.selectors(on: 10) == [kAudioProcessPropertyIsRunningOutput, kAudioProcessPropertyIsRunningInput])
        #expect(h.monitor.inputPollTargets.isEmpty, ".off listens without polling")
    }

    @Test func anInputChangeReReadsOnlyThatObject() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.hal.add(11, pid: 101)
        h.start()
        h.monitor.setInputPolling(.off)
        h.scheduler.runAll()
        h.hal.resetCounts()

        h.hal.capturing[11] = true
        h.hal.fireInput(11)
        h.scheduler.runAll()

        #expect(h.app(101)?.isCapturingInput == true)
        #expect(h.hal.inputReads == [11])
        #expect(h.hal.runningReads.isEmpty)
        #expect(h.hal.listReads == 0)
    }

    @Test func newObjectsAreReadWhileTracking() {
        let h = MonitorHarness()
        h.start()
        h.monitor.setInputPolling(.off)
        h.scheduler.runAll()

        h.hal.add(10, pid: 100)
        h.hal.capturing[10] = true
        h.hal.fireList()
        h.scheduler.runAll()

        #expect(h.app(100)?.isCapturingInput == true)
        #expect(h.hal.selectors(on: 10).contains(kAudioProcessPropertyIsRunningInput))
    }

    @Test func aCapturingHelperCountsForItsApp() {
        let h = MonitorHarness()
        h.apps.apps[100] = FakeRunningApps.regular("com.browser")
        h.apps.responsible[101] = 100
        h.hal.add(10, pid: 100)
        h.hal.add(11, pid: 101)
        h.hal.bundleIDs[10] = "com.browser"
        h.hal.bundleIDs[11] = "com.browser.helper"
        h.hal.capturing[11] = true
        h.start()
        h.monitor.setInputPolling(.off)
        h.scheduler.runAll()

        #expect(h.latest.map(\.id) == ["com.browser"])
        #expect(h.latest.first?.isCapturingInput == true)
    }

    @Test func stoppingTrackingRemovesTheListenersAndForgetsTheState() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.hal.capturing[10] = true
        h.start()
        h.monitor.setInputPolling(.objects([10]))
        h.scheduler.runAll()
        #expect(h.app(100)?.isCapturingInput == true)

        h.monitor.setInputPolling(nil)
        h.scheduler.runAll()
        #expect(h.app(100)?.isCapturingInput == false)
        #expect(h.hal.selectors(on: 10) == [kAudioProcessPropertyIsRunningOutput])
        #expect(h.monitor.inputPollTargets.isEmpty)

        h.hal.resetCounts()
        h.hal.fireList()
        h.scheduler.runAll()
        #expect(h.hal.inputReads.isEmpty)
    }

    @Test func vanishedObjectsLoseTheirInputListener() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.hal.add(11, pid: 101)
        h.start()
        h.monitor.setInputPolling(.all)
        h.scheduler.runAll()

        h.hal.objects = [10]
        h.hal.fireList()
        h.scheduler.runAll()
        #expect(h.hal.selectors(on: 11).isEmpty)
        #expect(h.monitor.inputPollTargets == [10])
        h.monitor.stop()
    }

    @Test func inputPollTargetsFollowTheDemandSeparatelyFromOutput() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.hal.add(11, pid: 101)
        h.start()

        h.monitor.setInputPolling(.objects([11, 99]))
        h.scheduler.runAll()
        #expect(h.monitor.inputPollTargets == [11], "only objects that exist")
        #expect(h.monitor.pollTargets.isEmpty, "output polling is unchanged")

        h.monitor.setInputPolling(.all)
        #expect(h.monitor.inputPollTargets == [10, 11])
        h.monitor.setInputPolling(.off)
        #expect(h.monitor.inputPollTargets.isEmpty)
        h.monitor.stop()
    }

    @Test func aPolledInputChangeIsPublished() async throws {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.start()
        h.monitor.setInputPolling(.objects([10]))
        h.scheduler.runAll()
        h.hal.resetCounts()

        h.hal.capturing[10] = true  // no HAL notification
        try await waitUntil { h.sleeper.waiting.count == 1 }
        h.sleeper.wakeAll()
        try await waitUntil { h.scheduler.pending.count == 1 }
        h.scheduler.runAll()
        #expect(h.app(100)?.isCapturingInput == true)
        #expect(h.hal.inputReads == [10], "the poll read; the flush didn't read again")
        h.monitor.stop()
    }

    @Test func stopForgetsInputStateAndAStartReadsItAgain() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.hal.capturing[10] = true
        h.start()
        h.monitor.setInputPolling(.off)
        h.scheduler.runAll()

        h.monitor.stop()
        #expect(h.hal.listeners.isEmpty)
        h.start()
        #expect(h.latest.first?.isCapturingInput == true, "still tracking, so a restart reads input again")
        #expect(h.hal.selectors(on: 10).contains(kAudioProcessPropertyIsRunningInput))
        h.monitor.stop()
    }
}

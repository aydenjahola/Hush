import CoreAudio
import Foundation
import HushAudio
import HushCore
import Testing
@testable import HushUI

/// Sleep and wake, and the same output device coming back under a new object ID: engines that
/// are still running are kept, and only engines confirmed stalled or detached are rebuilt.
///
/// The harness's delays are an hour, so the pending check never fires on its own; tests drive
/// its two stages with `checkHealth(confirming:)`, and say when IO ran with `runIO()`.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct MixerStoreWakeTests {
    private let speakers = OutputDevice(id: 1, uid: "built-in", name: "MacBook Pro Speakers")
    private let usb = OutputDevice(id: 2, uid: "usb", name: "USB DAC")

    /// A harness with apps "a" (lowered) and "b" (muted), both with control engines.
    private func twoAdjustedApps() throws -> (Harness, a: FakeEngine, b: FakeEngine) {
        let h = Harness()
        h.processes.emit([makeApp("a"), makeApp("b", objects: [43])])
        h.store.setPercent(50, for: "a")
        h.store.toggleMute(for: "b")
        return (h, try #require(h.factory.live("a")), try #require(h.factory.live("b")))
    }

    private func rebuildCount(_ h: Harness) -> Int {
        h.factory.events.filter { $0.hasPrefix("beginRebuild") }.count
    }

    // MARK: Same UID, new ID

    @Test func sameUIDUnderANewIDKeepsRunningEngines() throws {
        let (h, a, b) = try twoAdjustedApps()

        h.output.emit(OutputDevice(id: 7, uid: speakers.uid, name: speakers.name))
        #expect(h.store.healthCheckTask != nil, "checks instead of rebuilding")
        a.runIO()
        b.runIO()
        h.store.checkHealth(confirming: false)

        #expect(h.store.healthCheckTask == nil, "no suspects, so the check ends")
        #expect(rebuildCount(h) == 0)
        #expect(!a.isStopped && !b.isStopped)
        #expect(a.mode == .control && b.mode == .control)
        #expect(h.store.outputDevice?.id == 7, "the store tracks the new object ID")
    }

    @Test func sameUIDUnderANewIDRebuildsAConfirmedStallOnTheNewID() throws {
        let (h, a, b) = try twoAdjustedApps()

        h.output.emit(OutputDevice(id: 7, uid: speakers.uid, name: speakers.name))
        a.runIO()
        h.store.checkHealth(confirming: false)
        a.runIO()
        h.store.checkHealth(confirming: true)

        #expect(a.rebuiltDeviceIDs.isEmpty)
        #expect(b.rebuiltDeviceIDs == [7])
        #expect(b.mode == .control)
        #expect(h.factory.made.count == 2, "rebuilt in place, not replaced")
    }

    @Test func sameUIDUnderANewIDRebuildsAnEngineThatDidNotReattach() throws {
        let (h, a, b) = try twoAdjustedApps()
        a.attached = false  // IO still runs, but not through the new device

        h.output.emit(OutputDevice(id: 7, uid: speakers.uid, name: speakers.name))
        a.runIO()
        b.runIO()
        h.store.checkHealth(confirming: false)
        a.runIO()
        b.runIO()
        h.store.checkHealth(confirming: true)

        #expect(a.rebuiltDeviceIDs == [7], "a moving counter alone doesn't prove the output is attached")
        #expect(b.rebuiltDeviceIDs.isEmpty)
    }

    @Test func anEngineThatReattachesByTheConfirmationIsKept() throws {
        let (h, a, _) = try twoAdjustedApps()
        a.attached = false

        h.output.emit(OutputDevice(id: 7, uid: speakers.uid, name: speakers.name))
        a.runIO()
        h.store.checkHealth(confirming: false)
        a.attached = true
        a.runIO()
        h.store.checkHealth(confirming: true)

        #expect(a.rebuiltDeviceIDs.isEmpty)
    }

    @Test func anUnreadableSubDeviceListIsNoEvidence() throws {
        let (h, a, b) = try twoAdjustedApps()
        a.attached = nil

        h.simulateWake()
        a.runIO()
        b.runIO()
        h.store.checkHealth(confirming: false)

        #expect(h.store.healthCheckTask == nil)
        #expect(rebuildCount(h) == 0)
    }

    @Test func aDifferentUIDRebuildsEveryEngine() throws {
        let (h, a, b) = try twoAdjustedApps()

        h.output.emit(usb)

        #expect(a.rebuiltDeviceIDs == [2])
        #expect(b.rebuiltDeviceIDs == [2])
        #expect(h.store.healthCheckTask == nil)
    }

    @Test func anUnreadableUIDUnderANewIDRebuilds() throws {
        let h = Harness()
        h.output.emit(OutputDevice(id: 5, uid: "", name: "Output"))
        h.processes.emit([makeApp("a")])
        h.store.setPercent(50, for: "a")
        let engine = try #require(h.factory.live("a"))

        h.output.emit(OutputDevice(id: 6, uid: "", name: "Output"))

        #expect(engine.rebuiltDeviceIDs == [6], "an empty UID can't prove it's the same device")
    }

    @Test func renameOrDataSourceChangeDoesNotRebuild() throws {
        let (h, a, _) = try twoAdjustedApps()

        h.output.emit(OutputDevice(id: 1, uid: speakers.uid, name: "Speakers (renamed)"))
        h.output.emit(
            OutputDevice(id: 1, uid: speakers.uid, name: "External Headphones", transport: .builtInHeadphones))

        #expect(rebuildCount(h) == 0)
        #expect(!a.isStopped)
        #expect(h.store.healthCheckTask == nil, "a same-ID change only reconciles")
        #expect(h.store.outputDevice?.name == "External Headphones")
    }

    // MARK: Wake

    @Test func wakeKeepsRunningEngines() throws {
        let h = Harness()
        h.processes.emit([makeApp("a"), makeApp("b", objects: [43])])
        h.store.setPercent(50, for: "a")
        h.store.popoverDidAppear()
        let control = try #require(h.factory.live("a"))
        let meter = try #require(h.factory.live("b"))
        #expect(meter.mode == .meterOnly)

        h.simulateWake()
        #expect(h.store.healthCheckTask != nil)
        control.runIO()
        meter.runIO()
        h.store.checkHealth(confirming: false)

        #expect(rebuildCount(h) == 0)
        #expect(h.factory.made.count == 2)
    }

    @Test func aSuspectThatRecoversByTheConfirmationIsNotRebuilt() throws {
        // A device that takes longer than the first check to resume IO after a wake.
        let (h, a, b) = try twoAdjustedApps()

        h.simulateWake()
        h.store.checkHealth(confirming: false)
        #expect(h.store.healthCheckTask != nil, "both are suspects")
        a.runIO()
        b.runIO()
        h.store.checkHealth(confirming: true)

        #expect(rebuildCount(h) == 0)
        #expect(h.store.healthCheckTask == nil)
    }

    @Test func wakeRebuildsOnlyTheEngineStillStalledAtTheConfirmation() throws {
        let (h, a, b) = try twoAdjustedApps()

        h.simulateWake()
        h.store.checkHealth(confirming: false)
        a.runIO()
        h.store.checkHealth(confirming: true)

        #expect(a.rebuiltDeviceIDs.isEmpty)
        #expect(b.rebuiltDeviceIDs == [1])
        #expect(b.mode == .control)
        #expect(h.factory.events.filter { $0.hasPrefix("beginRebuild") } == ["beginRebuild b"])
    }

    @Test func theScheduledCheckRunsBothStagesOnItsOwn() async throws {
        let h = Harness(healthCheckDelay: .zero)
        h.processes.emit([makeApp("a")])
        h.store.setPercent(50, for: "a")
        let engine = try #require(h.factory.live("a"))

        h.simulateWake()
        await h.store.healthCheckTask?.value

        #expect(engine.rebuiltDeviceIDs == [1], "never ran IO, so it's confirmed stalled")
        #expect(h.store.healthCheckTask == nil)
    }

    @Test func wakeWithNoEnginesSchedulesNothing() {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        #expect(h.store.engineCount == 0)

        h.simulateWake()

        #expect(h.store.healthCheckTask == nil)
    }

    // MARK: Cancelling a pending check

    @Test func aDifferentUIDChangeCancelsAPendingCheck() throws {
        let (h, a, _) = try twoAdjustedApps()
        h.simulateWake()
        let task = try #require(h.store.healthCheckTask)

        h.output.emit(usb)

        #expect(task.isCancelled)
        #expect(h.store.healthCheckTask == nil)
        #expect(h.store.healthReadings.isEmpty)
        #expect(a.rebuiltDeviceIDs == [2], "rebuilt once, by the output change")
    }

    @Test func losingTheOutputDuringTheCheckCancelsIt() throws {
        let (h, a, b) = try twoAdjustedApps()
        h.simulateWake()
        let task = try #require(h.store.healthCheckTask)

        h.output.emit(nil)
        h.store.checkHealth(confirming: true)  // a stage that was already running bails out

        #expect(task.isCancelled)
        #expect(a.rebuiltDeviceIDs.isEmpty && b.rebuiltDeviceIDs.isEmpty)
    }

    @Test func losingPermissionDuringTheCheckCancelsIt() throws {
        let (h, a, b) = try twoAdjustedApps()
        h.simulateWake()
        let task = try #require(h.store.healthCheckTask)

        h.permission.status = .denied
        h.store.refreshPermission()
        h.store.checkHealth(confirming: true)

        #expect(task.isCancelled)
        #expect(a.rebuiltDeviceIDs.isEmpty && b.rebuiltDeviceIDs.isEmpty)
    }

    @Test func anEngineReplacedDuringTheCheckIsNotRebuilt() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(50, for: "a")
        let first = try #require(h.factory.live("a"))
        first.updateError = FakeError()  // forces make-before-break on the next process change

        h.simulateWake()
        h.processes.emit([makeApp("a", objects: [42, 44])])
        let second = try #require(h.factory.live("a"))
        #expect(second !== first)
        h.store.checkHealth(confirming: false)
        h.store.checkHealth(confirming: true)

        #expect(second.rebuiltDeviceIDs.isEmpty, "only the engine noted at the start of the check is compared")
    }

    @Test func shutdownCancelsTheCheckAndStopsObservingWake() throws {
        let (h, _, _) = try twoAdjustedApps()
        h.simulateWake()
        let task = try #require(h.store.healthCheckTask)

        h.store.shutdown()
        #expect(task.isCancelled)

        h.simulateWake()
        #expect(h.store.healthCheckTask == nil, "the wake observer was removed")
    }

    // MARK: Failed stall rebuilds

    private func failedStallRebuild() throws -> (Harness, FakeEngine) {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(50, for: "a")
        let engine = try #require(h.factory.live("a"))
        engine.rebuildError = FakeError()
        h.simulateWake()
        h.store.checkHealth(confirming: false)
        h.store.checkHealth(confirming: true)
        #expect(engine.isStopped)
        #expect(h.store.engineCount == 0)
        #expect(h.store.strips.first?.engineError != nil, "shows the warning meanwhile")
        #expect(h.store.stallRetryTask != nil)
        return (h, engine)
    }

    @Test func aFailedStallRebuildIsRetriedAfterTheDelay() throws {
        let (h, _) = try failedStallRebuild()

        h.store.retryStalledEngines(afterTimer: true)  // what the retry task does when its delay ends

        let retried = try #require(h.factory.live("a"))
        #expect(retried.mode == .control)
        #expect(h.store.strips.first?.engineError == nil)
        #expect(h.store.stallRetryTask == nil)
    }

    @Test func aFailedStallRebuildIsRetriedWhenTheDeviceListChanges() throws {
        let (h, _) = try failedStallRebuild()

        h.output.emitDevices([speakers, usb])

        #expect(h.factory.live("a")?.mode == .control)
        #expect(h.store.strips.first?.engineError == nil)
    }

    @Test func aFailedStallRebuildIsRetriedWhenTheOutputChanges() throws {
        let (h, _) = try failedStallRebuild()

        h.output.emit(OutputDevice(id: 1, uid: speakers.uid, name: "Speakers (renamed)"))

        #expect(h.factory.live("a")?.mode == .control)
    }

    @Test func aFailedTimedRetryStaysRetryableUntilTheNextDeviceEvent() throws {
        let (h, _) = try failedStallRebuild()
        h.factory.error = FakeError()

        h.store.retryStalledEngines(afterTimer: true)
        #expect(h.store.strips.first?.engineError != nil)
        #expect(h.store.stallRetryIDs == ["a"], "still retryable")
        #expect(h.store.stallRetryTask == nil, "no further timer")
        h.factory.error = nil
        h.output.emitDevices([speakers, usb])

        #expect(h.factory.live("a")?.mode == .control, "the device-list change retried it")
        #expect(h.store.strips.first?.engineError == nil)
    }

    @Test func aFailedEventRetryIsAnOrdinaryFailure() throws {
        let (h, _) = try failedStallRebuild()
        h.factory.error = FakeError()
        h.store.retryStalledEngines(afterTimer: true)

        h.output.emitDevices([speakers, usb])  // the event-triggered retry fails too
        #expect(h.store.stallRetryIDs.isEmpty)
        h.factory.error = nil
        h.output.emitDevices([speakers])

        #expect(h.factory.live("a") == nil, "kept until something relevant changes, like other failures")
        #expect(h.store.strips.first?.engineError != nil)
    }

    @Test func aFailedEventRetryAfterAnOutputChangeIsOrdinary() throws {
        let (h, _) = try failedStallRebuild()
        h.factory.error = FakeError()

        h.output.emit(OutputDevice(id: 1, uid: speakers.uid, name: "Speakers (renamed)"))
        #expect(h.store.stallRetryIDs.isEmpty)
        #expect(h.store.stallRetryTask == nil)
        h.factory.error = nil
        h.output.emitDevices([speakers, usb])

        #expect(h.factory.live("a") == nil)
    }

    @Test func otherFailuresAreNotRetriedOnADeviceListChange() throws {
        let h = Harness()
        h.factory.error = FakeError()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(50, for: "a")
        #expect(h.store.strips.first?.engineError != nil)
        h.factory.error = nil

        h.output.emitDevices([speakers, usb])

        #expect(h.factory.live("a") == nil)
    }
}

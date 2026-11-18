import CoreAudio
import Foundation
import HushAudio
import HushCore
import Testing
@testable import HushUI

/// Sleep and wake, and the same output device coming back under a new object ID: engines that
/// are still running are kept, and only stalled ones are rebuilt.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct MixerStoreWakeTests {
    private let speakers = OutputDevice(id: 1, uid: "built-in", name: "MacBook Pro Speakers")

    @Test func sameUIDUnderANewIDKeepsEveryEngine() async throws {
        let h = Harness()
        h.processes.emit([makeApp("a"), makeApp("b", objects: [43])])
        h.store.setPercent(50, for: "a")
        h.store.toggleMute(for: "b")
        let engineA = try #require(h.factory.live("a"))
        let engineB = try #require(h.factory.live("b"))

        h.output.emit(OutputDevice(id: 7, uid: speakers.uid, name: speakers.name))
        await h.store.healthCheckTask?.value

        #expect(engineA.rebuiltDeviceIDs.isEmpty)
        #expect(engineB.rebuiltDeviceIDs.isEmpty)
        #expect(!engineA.isStopped && !engineB.isStopped)
        #expect(engineA.mode == .control && engineB.mode == .control)
        #expect(h.factory.made.count == 2)
        #expect(h.store.outputDevice?.id == 7, "the store still tracks the new object ID")
    }

    @Test func sameUIDUnderANewIDRebuildsAStalledEngineOnTheNewID() async throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(50, for: "a")
        let engine = try #require(h.factory.live("a"))
        engine.isFlowing = false

        h.output.emit(OutputDevice(id: 7, uid: speakers.uid, name: speakers.name))
        await h.store.healthCheckTask?.value

        #expect(engine.rebuiltDeviceIDs == [7])
        #expect(engine.mode == .control)
        #expect(h.factory.made.count == 1, "rebuilt in place, not replaced")
    }

    @Test func aDifferentUIDRebuildsEveryEngine() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(50, for: "a")
        let engine = try #require(h.factory.live("a"))

        h.output.emit(OutputDevice(id: 2, uid: "usb", name: "USB DAC"))

        #expect(engine.rebuiltDeviceIDs == [2])
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
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(50, for: "a")
        let engine = try #require(h.factory.live("a"))

        h.output.emit(OutputDevice(id: 1, uid: speakers.uid, name: "Speakers (renamed)"))
        h.output.emit(
            OutputDevice(id: 1, uid: speakers.uid, name: "External Headphones", transport: .builtInHeadphones))

        #expect(engine.rebuiltDeviceIDs.isEmpty)
        #expect(!engine.isStopped)
        #expect(h.store.healthCheckTask == nil, "a same-ID change only reconciles")
        #expect(h.store.outputDevice?.name == "External Headphones")
    }

    @Test func wakeKeepsRunningEngines() async throws {
        let h = Harness()
        h.processes.emit([makeApp("a"), makeApp("b", objects: [43])])
        h.store.setPercent(50, for: "a")
        h.store.popoverDidAppear()
        let control = try #require(h.factory.live("a"))
        let meter = try #require(h.factory.live("b"))
        #expect(meter.mode == .meterOnly)

        await h.simulateWake()

        #expect(control.rebuiltDeviceIDs.isEmpty)
        #expect(meter.rebuiltDeviceIDs.isEmpty)
        #expect(h.factory.made.count == 2)
    }

    @Test func wakeRebuildsOnlyTheStalledEngine() async throws {
        let h = Harness()
        h.processes.emit([makeApp("a"), makeApp("b", objects: [43])])
        h.store.setPercent(50, for: "a")
        h.store.toggleMute(for: "b")
        let running = try #require(h.factory.live("a"))
        let stalled = try #require(h.factory.live("b"))
        stalled.isFlowing = false

        await h.simulateWake()

        #expect(running.rebuiltDeviceIDs.isEmpty)
        #expect(stalled.rebuiltDeviceIDs == [1])
        #expect(stalled.mode == .control)
        #expect(h.factory.events.filter { $0.hasPrefix("beginRebuild") } == ["beginRebuild b"])
    }

    @Test func aStalledEngineThatFailsToRebuildIsDroppedAndWarns() async throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(50, for: "a")
        let engine = try #require(h.factory.live("a"))
        engine.isFlowing = false
        engine.rebuildError = FakeError()

        await h.simulateWake()

        #expect(engine.isStopped)
        #expect(h.store.engineCount == 0)
        #expect(h.store.strips.first?.engineError != nil)
    }

    @Test func wakeWithNoEnginesSchedulesNothing() async {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        #expect(h.store.engineCount == 0)

        await h.simulateWake()

        #expect(h.store.healthCheckTask == nil)
    }

    @Test func anEngineReplacedDuringTheCheckIsNotRebuilt() async throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(50, for: "a")
        let first = try #require(h.factory.live("a"))
        first.isFlowing = false
        first.updateError = FakeError()  // forces make-before-break on the next process change

        h.store.scheduleHealthCheck()
        h.processes.emit([makeApp("a", objects: [42, 44])])
        let second = try #require(h.factory.live("a"))
        #expect(second !== first)
        second.isFlowing = false
        await h.store.healthCheckTask?.value

        #expect(second.rebuiltDeviceIDs.isEmpty, "only the engine noted at the start of the check is compared")
    }

    @Test func shutdownCancelsAPendingCheck() async throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(50, for: "a")
        h.store.scheduleHealthCheck()
        let task = try #require(h.store.healthCheckTask)

        h.store.shutdown()
        await task.value

        #expect(h.store.healthCheckTask == nil)
        #expect(h.factory.made.allSatisfy { $0.rebuiltDeviceIDs.isEmpty })
    }
}

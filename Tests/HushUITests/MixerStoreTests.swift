import CoreAudio
import Foundation
import HushAudio
import HushCore
import Testing
@testable import HushUI

@MainActor
@Suite struct MixerStoreTests {
    @Test func appearingAppShowsStripWithSavedSetting() throws {
        let saved = AppVolumeSetting(percent: 62, lastAdjusted: Date(timeIntervalSince1970: 1_700_000_000))
        let h = Harness(document: SettingsDocument(apps: ["com.example.player": saved]))
        h.processes.emit([makeApp("com.example.player")])

        #expect(h.store.strips.map(\.id) == ["com.example.player"])
        #expect(h.store.strips.first?.setting.percent == 62)
        let engine = try #require(h.factory.live("com.example.player"))
        #expect(engine.mode == .control)
        #expect(isApproximatelyEqual(engine.initialGain, 0.3844))
    }

    @Test func untouchedAppGetsNoEngineWhilePopoverClosed() {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        #expect(h.factory.made.isEmpty)
        #expect(h.store.strips.map(\.id) == ["a"])
    }

    @Test func faderTo80CreatesControlEngineWithSquaredGain() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(80, for: "a")

        let engine = try #require(h.factory.live("a"))
        #expect(engine.mode == .control)
        #expect(isApproximatelyEqual(engine.initialGain, 0.64))

        h.store.setPercent(90, for: "a")
        #expect(h.factory.made.count == 1)
        #expect(isApproximatelyEqual(engine.currentGain, 0.81))
    }

    @Test func returningTo100WithPopoverClosedTearsDownEngine() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(80, for: "a")
        let engine = try #require(h.factory.live("a"))

        h.store.setPercent(100, for: "a")
        #expect(engine.isStopped)
        #expect(h.store.engineCount == 0)
        #expect(h.store.strips.first?.setting == AppVolumeSetting())
    }

    @Test func openingPopoverAddsMeterOnlyEnginesForPlayingApps() {
        let h = Harness()
        h.processes.emit([makeApp("a"), makeApp("b"), makeApp("c", playing: false)])
        h.store.setPercent(80, for: "b")

        h.store.popoverDidAppear()
        #expect(h.factory.live("a")?.mode == .meterOnly)
        #expect(h.factory.live("b")?.mode == .control)
        #expect(h.factory.live("c") == nil)

        h.store.popoverDidDisappear()
        #expect(h.factory.live("a") == nil)
        #expect(h.factory.live("b")?.mode == .control)
    }

    @Test func adjustingMeteredAppSwapsToControlEngine() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.popoverDidAppear()
        let meter = try #require(h.factory.live("a"))
        #expect(meter.mode == .meterOnly)

        h.store.setPercent(50, for: "a")
        #expect(meter.isStopped)
        #expect(h.factory.live("a")?.mode == .control)

        h.store.setPercent(100, for: "a")
        #expect(h.factory.live("a")?.mode == .meterOnly)
    }

    @Test func outputChangeRebuildsEveryEngine() throws {
        let h = Harness()
        h.processes.emit([makeApp("a"), makeApp("b", objects: [43])])
        h.store.setPercent(80, for: "a")
        h.store.toggleMute(for: "b")
        let engineA = try #require(h.factory.live("a"))
        let engineB = try #require(h.factory.live("b"))

        h.output.emit(OutputDevice(id: 2, uid: "usb", name: "USB DAC"))
        #expect(engineA.rebuiltDeviceIDs == [2])
        #expect(engineB.rebuiltDeviceIDs == [2])
        #expect(h.factory.made.count == 2)
        #expect(h.store.outputDevice?.name == "USB DAC")
    }

    @Test func failedRebuildTearsDownAndWarns() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(80, for: "a")
        let engine = try #require(h.factory.live("a"))
        engine.rebuildError = FakeError()

        h.output.emit(OutputDevice(id: 2, uid: "usb", name: "USB DAC"))
        #expect(engine.isStopped)
        #expect(h.store.engineCount == 0)
        #expect(h.store.strips.first?.engineError != nil)
    }

    @Test func engineFailureShowsWarningAndRetriesOnNextChange() {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.factory.error = FakeError()

        h.store.setPercent(80, for: "a")
        #expect(h.store.strips.first?.engineError != nil)
        #expect(h.store.engineCount == 0)

        h.factory.error = nil
        h.store.popoverDidAppear()
        #expect(h.factory.made.isEmpty, "no automatic retry")

        h.store.setPercent(70, for: "a")
        #expect(h.factory.live("a")?.mode == .control)
        #expect(h.store.strips.first?.engineError == nil)
    }

    @Test func loweringMaxBoostClampsSettingsAndGain() throws {
        let h = Harness(document: SettingsDocument(apps: ["a": AppVolumeSetting(percent: 200, lastAdjusted: Harness.fixedNow)]))
        h.processes.emit([makeApp("a")])

        h.store.setMaxBoost(.percent150)
        #expect(h.store.maxPercent == 150)
        #expect(h.store.strips.first?.setting.percent == 150)
        let engine = try #require(h.factory.live("a"))
        #expect(isApproximatelyEqual(engine.currentGain, 1.5))

        h.store.flushPendingSave()
        #expect(h.persister.saved.last?.apps["a"]?.percent == 150)
        #expect(h.persister.saved.last?.preferences.maxBoostPercent == .percent150)
    }

    @Test func settingsAreSavedOnlyAfterFlushOrDelay() {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(80, for: "a")
        #expect(h.persister.saved.isEmpty)

        h.store.flushPendingSave()
        #expect(h.persister.saved.count == 1)
        #expect(h.persister.saved.last?.apps["a"] == AppVolumeSetting(percent: 80, lastAdjusted: Harness.fixedNow))

        h.store.flushPendingSave()
        #expect(h.persister.saved.count == 1, "nothing pending, nothing written")
    }

    @Test func deniedPermissionDisablesControls() {
        let h = Harness(permission: .denied)
        h.processes.emit([makeApp("a")])
        #expect(!h.store.controlsEnabled)

        h.store.setPercent(80, for: "a")
        h.store.toggleMute(for: "a")
        h.store.popoverDidAppear()
        #expect(h.factory.made.isEmpty)
        #expect(h.store.strips.first?.setting == AppVolumeSetting())
    }

    @Test func grantingPermissionAppliesSavedSettings() {
        let h = Harness(
            document: SettingsDocument(apps: ["a": AppVolumeSetting(percent: 50, lastAdjusted: Harness.fixedNow)]),
            permission: .denied)
        h.processes.emit([makeApp("a")])
        #expect(h.factory.made.isEmpty)

        h.permission.status = .authorized
        h.store.refreshPermission()
        #expect(h.factory.live("a")?.mode == .control)
    }

    @Test func stoppingPlaybackTearsDownEngineAndKeepsSetting() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(80, for: "a")
        let first = try #require(h.factory.live("a"))

        h.processes.emit([makeApp("a", playing: false)])
        #expect(first.isStopped)
        #expect(h.store.strips.isEmpty)

        h.processes.emit([makeApp("a")])
        let second = try #require(h.factory.live("a"))
        #expect(second !== first)
        #expect(isApproximatelyEqual(second.initialGain, 0.64))
    }

    @Test func processListChangeReplacesEngine() throws {
        let h = Harness()
        h.processes.emit([makeApp("a", objects: [42])])
        h.store.setPercent(80, for: "a")
        let first = try #require(h.factory.live("a"))

        h.processes.emit([makeApp("a", objects: [42, 43])])
        #expect(first.isStopped)
        #expect(h.factory.live("a")?.processObjectIDs == [42, 43])
    }

    @Test func showInactiveAppsIncludesPausedAndSavedApps() {
        let h = Harness(document: SettingsDocument(apps: ["gone": AppVolumeSetting(percent: 50, lastAdjusted: Harness.fixedNow)]))
        h.processes.emit([makeApp("a"), makeApp("b", playing: false)])
        #expect(h.store.strips.map(\.id) == ["a"])

        h.store.setShowInactiveApps(true)
        #expect(Set(h.store.strips.map(\.id)) == ["a", "b", "gone"])
        #expect(h.store.strips.first { $0.id == "gone" }?.isRunning == false)
        #expect(h.store.strips.first?.id == "a", "playing apps first")
    }

    @Test func stripOrderIsFrozenWhilePopoverIsOpen() {
        let h = Harness()
        h.processes.emit([makeApp("a"), makeApp("b")])
        h.store.popoverDidAppear()
        #expect(h.store.strips.map(\.id) == ["a", "b"])

        h.store.setPercent(80, for: "b")
        #expect(h.store.strips.map(\.id) == ["a", "b"])

        h.store.popoverDidDisappear()
        #expect(h.store.strips.map(\.id) == ["b", "a"])
    }

    @Test func attenuationFlagTracksMutedOrQuietApps() {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        #expect(!h.store.isAnyAppAttenuated)

        h.store.setPercent(150, for: "a")
        #expect(!h.store.isAnyAppAttenuated)

        h.store.setPercent(80, for: "a")
        #expect(h.store.isAnyAppAttenuated)

        h.store.setPercent(100, for: "a")
        h.store.toggleMute(for: "a")
        #expect(h.store.isAnyAppAttenuated)
    }

    @Test func meterTickUsesEnginePeak() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.popoverDidAppear()
        let engine = try #require(h.factory.live("a"))
        engine.peak = 0.5

        h.store.tickMeters(elapsed: 1.0 / 30.0)
        #expect(h.store.meterLevels["a"] == 0.5)

        h.store.popoverDidDisappear()
        #expect(h.store.meterLevels.isEmpty)
    }

    @Test func resetAllLevelsClearsEverySetting() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(80, for: "a")
        let engine = try #require(h.factory.live("a"))

        h.store.resetAllLevels()
        #expect(engine.isStopped)
        #expect(h.store.strips.first?.setting == AppVolumeSetting())
        h.store.flushPendingSave()
        #expect(h.persister.saved.last?.apps.isEmpty == true)
    }

    @Test func playingCountCountsOnlyPlayingApps() {
        let h = Harness()
        h.processes.emit([makeApp("a"), makeApp("b"), makeApp("c", playing: false)])
        #expect(h.store.playingCount == 2)
    }

    @Test func shutdownStopsEnginesAndFlushes() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(80, for: "a")
        let engine = try #require(h.factory.live("a"))

        h.store.shutdown()
        #expect(engine.isStopped)
        #expect(h.persister.saved.count == 1)
    }
}

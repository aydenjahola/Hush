import AppKit
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

    @Test func adjustingMeteredAppSwitchesTheSameEngineToControl() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.popoverDidAppear()
        let meter = try #require(h.factory.live("a"))
        #expect(meter.mode == .meterOnly)

        h.store.setPercent(50, for: "a")
        #expect(!meter.isStopped, "converted in place, no new aggregate")
        #expect(meter.mode == .control)
        #expect(meter.currentGain == VolumeCurve.gain(percent: 50))
        #expect(h.factory.made.count == 1)

        h.store.setPercent(100, for: "a")
        #expect(meter.mode == .meterOnly)
        #expect(h.factory.made.count == 1)
    }

    @Test func outputChangeRebuildsEveryEngine() throws {
        let h = Harness()
        h.processes.emit([makeApp("a"), makeApp("b", objects: [43])])
        h.store.setPercent(80, for: "a")
        h.store.toggleMute(for: "b")
        let engineA = try #require(h.factory.live("a"))
        let engineB = try #require(h.factory.live("b"))
        #expect(engineB.mode == .control)
        #expect(engineB.initialGain == 0)

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

    @Test func failedRebuildClearsMeterLevel() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.popoverDidAppear()
        let engine = try #require(h.factory.live("a"))
        engine.peak = 0.5
        h.store.tickMeters(elapsed: 1.0 / 30.0)
        #expect(h.store.meterLevels["a"] != nil)

        engine.rebuildError = FakeError()
        h.output.emit(OutputDevice(id: 2, uid: "usb", name: "USB DAC"))
        #expect(engine.isStopped)
        #expect(h.store.meterLevels["a"] == nil)
    }

    @Test func controlFailureSaysHushCouldNotControlTheApp() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.factory.error = FakeError()
        h.store.setPercent(80, for: "a")
        let message = try #require(h.store.strips.first?.engineError)
        #expect(message.contains("couldn't control this app's audio"))
    }

    @Test func meterOnlyFailureSaysHushCouldNotReadTheLevel() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.factory.error = FakeError()
        h.store.popoverDidAppear()
        let message = try #require(h.store.strips.first?.engineError)
        #expect(message.contains("couldn't read this app's level"))
        #expect(!message.contains("control"))
    }

    @Test func turningMetersOffClearsAMeterOnlyWarning() {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.factory.error = FakeError()
        h.store.popoverDidAppear()
        #expect(h.store.strips.first?.engineError != nil)
        h.store.showLevelMeters = false
        #expect(h.store.strips.first?.engineError == nil)
    }

    @Test func turningMetersOffKeepsAControlWarning() {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.factory.error = FakeError()
        h.store.setPercent(80, for: "a")
        h.store.showLevelMeters = false
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

    @Test func savingLevelsKeepsUpdateSettings() {
        var document = SettingsDocument()
        document.updates.skippedVersion = "0.3.0"
        let h = Harness(document: document)
        h.processes.emit([makeApp("a")])
        h.store.setPercent(80, for: "a")
        h.store.flushPendingSave()
        #expect(h.persister.saved.last?.updates.skippedVersion == "0.3.0")
        #expect(h.persister.saved.last?.apps["a"]?.percent == 80)
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

    @Test func undeterminedPermissionIsRequestedAndGrantAppliesSavedSettings() async throws {
        let h = Harness(
            document: SettingsDocument(apps: ["a": AppVolumeSetting(percent: 50, lastAdjusted: Harness.fixedNow)]),
            permission: .undetermined,
            answer: .authorized)
        h.processes.emit([makeApp("a")])
        #expect(!h.store.controlsEnabled)
        #expect(h.factory.made.isEmpty)

        let request = try #require(h.store.permissionRequest)
        await request.value
        #expect(h.permission.requestCount == 1)
        #expect(h.store.permission == .authorized)
        let engine = try #require(h.factory.live("a"))
        #expect(engine.mode == .control)
        #expect(isApproximatelyEqual(engine.initialGain, 0.25))
    }

    @Test func undeterminedPermissionDeniedKeepsControlsOff() async throws {
        let h = Harness(permission: .undetermined, answer: .denied)
        h.processes.emit([makeApp("a")])
        await h.store.permissionRequest?.value
        #expect(h.store.permission == .denied)
        #expect(!h.store.controlsEnabled)
        #expect(h.factory.made.isEmpty)
    }

    @Test func authorizedPermissionIsNotRequested() {
        let h = Harness()
        #expect(h.store.permissionRequest == nil)
        #expect(h.permission.requestCount == 0)
    }

    @Test func losingOutputDeviceTearsDownEnginesAndReturningRecreatesThem() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(80, for: "a")
        h.store.popoverDidAppear()
        h.processes.emit([makeApp("a"), makeApp("b", objects: [43])])
        let control = try #require(h.factory.live("a"))
        let meter = try #require(h.factory.live("b"))
        #expect(meter.mode == .meterOnly)

        h.output.emit(nil)
        #expect(control.isStopped)
        #expect(meter.isStopped)
        #expect(h.store.engineCount == 0)
        #expect(h.store.outputDevice == nil)
        #expect(h.store.meterLevels.isEmpty)

        h.output.emit(OutputDevice(id: 2, uid: "usb", name: "USB DAC"))
        let newControl = try #require(h.factory.live("a"))
        #expect(newControl !== control)
        #expect(newControl.mode == .control)
        #expect(isApproximatelyEqual(newControl.initialGain, 0.64))
        #expect(h.factory.live("b")?.mode == .meterOnly)
        #expect(h.store.engineCount == 2)
    }

    @Test func stoppingPlaybackTearsDownControlEngineAndKeepsSetting() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(80, for: "a")
        let first = try #require(h.factory.live("a"))
        #expect(first.mode == .control)

        h.processes.emit([makeApp("a", playing: false)])
        #expect(first.isStopped)
        #expect(h.store.engineCount == 0, "lowered apps are processed only while they play")

        h.processes.emit([makeApp("a")])
        let second = try #require(h.factory.live("a"))
        #expect(second !== first)
        #expect(second.mode == .control)
        #expect(isApproximatelyEqual(second.initialGain, 0.64))
    }

    @Test func mutedAppThatIsNotPlayingGetsNoEngineUntilItPlays() throws {
        let h = Harness(document: SettingsDocument(apps: ["chat": mutedSetting()]))
        h.processes.emit([makeApp("chat", playing: false)])
        #expect(h.factory.made.isEmpty, "a tap nobody reads doesn't silence anything")

        h.processes.emit([makeApp("chat")])
        let engine = try #require(h.factory.live("chat"))
        #expect(engine.mode == .control)
        #expect(engine.initialGain == 0)
    }

    @Test func mutedPlayingAppGetsControlEngineAtZeroGain() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.toggleMute(for: "a")
        let engine = try #require(h.factory.live("a"))
        #expect(engine.mode == .control)
        #expect(engine.initialGain == 0)
        #expect(h.store.engineCount == 1)
    }

    @Test func stoppingPlaybackTearsDownMutedAppsEngineAndKeepsMute() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.toggleMute(for: "a")
        let first = try #require(h.factory.live("a"))

        h.processes.emit([makeApp("a", playing: false)])
        #expect(first.isStopped)
        #expect(h.store.engineCount == 0)

        h.processes.emit([makeApp("a")])
        let second = try #require(h.factory.live("a"))
        #expect(second !== first)
        #expect(second.initialGain == 0)
    }

    @Test func unmutingAt50WhilePlayingRestoresQuarterGainOnTheSameEngine() throws {
        let h = Harness(document: SettingsDocument(apps: ["a": mutedSetting(percent: 50)]))
        h.processes.emit([makeApp("a")])
        let engine = try #require(h.factory.live("a"))
        #expect(engine.mode == .control)
        #expect(engine.initialGain == 0)

        h.store.toggleMute(for: "a")
        #expect(h.factory.made.count == 1, "mute is just gain 0, so no engine swap")
        #expect(isApproximatelyEqual(engine.currentGain, 0.25))

        h.store.toggleMute(for: "a")
        #expect(h.factory.made.count == 1)
        #expect(engine.currentGain == 0)
    }

    @Test func loweredAppGetsNoEngineWhileIdleAndControlWhilePlaying() throws {
        let h = Harness(document: SettingsDocument(apps: ["a": AppVolumeSetting(percent: 50, lastAdjusted: Harness.fixedNow)]))
        h.processes.emit([makeApp("a", playing: false)])
        #expect(h.factory.made.isEmpty)

        h.processes.emit([makeApp("a")])
        let engine = try #require(h.factory.live("a"))
        #expect(engine.mode == .control)
        #expect(isApproximatelyEqual(engine.initialGain, 0.25))
    }

    @Test func mutingAndUnmutingIdleAppCreatesNoEngine() {
        let h = Harness()
        h.processes.emit([makeApp("a", playing: false)])
        h.store.setShowInactiveApps(true)
        h.store.popoverDidAppear()

        h.store.toggleMute(for: "a")
        #expect(h.factory.made.isEmpty)
        h.store.toggleMute(for: "a")
        #expect(h.factory.made.isEmpty)
    }

    @Test func appWithoutSettingThatIsNotPlayingGetsNoEngineWithPopoverOpen() {
        let h = Harness()
        h.processes.emit([makeApp("a", playing: false)])
        h.store.setShowInactiveApps(true)
        h.store.popoverDidAppear()
        #expect(h.factory.made.isEmpty)
        #expect(h.store.strips.map(\.id) == ["a"])
    }

    @Test func stoppingPlaybackTearsDownMeterOnlyEngine() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.popoverDidAppear()
        let meter = try #require(h.factory.live("a"))
        #expect(meter.mode == .meterOnly)

        h.processes.emit([makeApp("a", playing: false)])
        #expect(meter.isStopped)
        #expect(h.store.engineCount == 0)
    }

    @Test func mutedAppsControlEngineSurvivesPopoverOpeningAndClosing() throws {
        let h = Harness(document: SettingsDocument(apps: ["a": mutedSetting()]))
        h.processes.emit([makeApp("a")])
        let engine = try #require(h.factory.live("a"))

        h.store.popoverDidAppear()
        h.store.popoverDidDisappear()
        #expect(!engine.isStopped)
        #expect(h.factory.made.count == 1)
    }

    @Test func appDisappearingTearsDownMutedAppsEngineAndKeepsSetting() throws {
        let h = Harness(document: SettingsDocument(apps: ["a": mutedSetting()]))
        h.processes.emit([makeApp("a")])
        let first = try #require(h.factory.live("a"))

        h.processes.emit([])
        #expect(first.isStopped)
        #expect(h.store.engineCount == 0)

        h.processes.emit([makeApp("a")])
        let second = try #require(h.factory.live("a"))
        #expect(second !== first)
        #expect(second.mode == .control)
        #expect(second.initialGain == 0)
    }

    @Test func engineErrorSurvivesStoppingPlaybackAndClearsWhenAppDisappears() throws {
        let h = Harness()
        h.store.setShowInactiveApps(true)
        h.processes.emit([makeApp("a")])
        h.factory.error = FakeError()
        h.store.setPercent(80, for: "a")
        #expect(h.store.strips.first?.engineError != nil)

        h.factory.error = nil
        h.processes.emit([makeApp("a", playing: false)])
        #expect(h.store.strips.first?.engineError != nil, "stopping playback is not a retry")
        h.processes.emit([makeApp("a")])
        #expect(h.factory.made.isEmpty, "resuming playback is not a retry either")

        h.processes.emit([])
        h.processes.emit([makeApp("a")])
        #expect(h.store.strips.first?.engineError == nil)
        #expect(h.factory.live("a")?.mode == .control, "a relaunched app gets a fresh attempt")
    }

    @Test func userChangeOnErroredAppThatStoppedPlayingRetriesWhenItPlays() throws {
        let h = Harness()
        h.store.setShowInactiveApps(true)
        h.processes.emit([makeApp("a")])
        h.factory.error = FakeError()
        h.store.toggleMute(for: "a")
        let message = try #require(h.store.strips.first?.engineError)
        #expect(message.contains("couldn't control this app's audio"))

        h.factory.error = nil
        h.processes.emit([makeApp("a", playing: false)])
        h.store.setPercent(60, for: "a")
        #expect(h.store.strips.first?.engineError == nil, "a user change clears the error")
        #expect(h.factory.made.isEmpty, "idle: nothing to process yet")

        h.processes.emit([makeApp("a")])
        let engine = try #require(h.factory.live("a"))
        #expect(engine.initialGain == 0, "still muted")
    }

    @Test func mutedAppProcessListChangeUpdatesTheEngineInPlace() throws {
        let h = Harness(document: SettingsDocument(apps: ["a": mutedSetting()]))
        h.processes.emit([makeApp("a", objects: [42])])
        let engine = try #require(h.factory.live("a"))

        h.processes.emit([makeApp("a", objects: [42, 43])])
        #expect(!engine.isStopped, "a rebuild lets the app through at full level while the old tap goes away")
        #expect(engine.processObjectIDs == [42, 43])
        #expect(engine.currentGain == 0, "still muted")
        #expect(h.factory.made.count == 1)
    }

    @Test func outputChangeRebuildsMutedAppsEngine() throws {
        let h = Harness(document: SettingsDocument(apps: ["a": mutedSetting()]))
        h.processes.emit([makeApp("a")])
        let engine = try #require(h.factory.live("a"))

        h.output.emit(OutputDevice(id: 2, uid: "usb", name: "USB DAC"))
        #expect(engine.rebuiltDeviceIDs == [2])
        #expect(h.factory.made.count == 1)
    }

    @Test func meterTickCoversEveryPlayingAppsEngine() throws {
        let h = Harness(document: SettingsDocument(apps: ["c": mutedSetting()]))
        h.processes.emit([makeApp("b", objects: [43]), makeApp("c", objects: [44])])
        h.store.popoverDidAppear()
        #expect(h.store.engineCount == 2)

        h.store.tickMeters(elapsed: 1.0 / 30.0)
        #expect(Set(h.store.meterLevels.keys) == ["b", "c"])
    }

    @Test func revokingPermissionTearsDownEveryEngine() throws {
        let h = Harness(document: SettingsDocument(apps: [
            "muted": mutedSetting(),
            "lowered": AppVolumeSetting(percent: 50, lastAdjusted: Harness.fixedNow),
        ]))
        h.processes.emit([
            makeApp("muted", objects: [1]),
            makeApp("lowered", objects: [2]),
            makeApp("plain", objects: [3]),
        ])
        h.store.popoverDidAppear()
        let engines = [h.factory.live("muted"), h.factory.live("lowered"), h.factory.live("plain")].compactMap { $0 }
        let modes = engines.map { $0.mode }
        #expect(modes == [.control, .control, .meterOnly])

        h.permission.status = .denied
        h.store.refreshPermission()
        #expect(!h.store.controlsEnabled)
        #expect(engines.filter { !$0.isStopped }.isEmpty)
        #expect(h.store.engineCount == 0)
    }

    @Test func processListChangeUpdatesTheEngineInPlace() throws {
        let h = Harness()
        h.processes.emit([makeApp("a", objects: [42])])
        h.store.setPercent(80, for: "a")
        let engine = try #require(h.factory.live("a"))

        h.processes.emit([makeApp("a", objects: [42, 43])])
        #expect(!engine.isStopped)
        #expect(engine.processObjectIDs == [42, 43])

        h.processes.emit([makeApp("a", objects: [43])])  // a helper exited
        #expect(engine.processObjectIDs == [43])
        #expect(h.factory.made.count == 1)
    }

    @Test func meterOnlyProcessListChangeUpdatesTheEngineInPlace() throws {
        let h = Harness()
        h.processes.emit([makeApp("a", objects: [42])])
        h.store.popoverDidAppear()
        let before = h.factory.events.count

        h.processes.emit([makeApp("a", objects: [42, 43])])
        #expect(Array(h.factory.events.dropFirst(before)) == ["update a [42, 43]"])
        #expect(h.factory.live("a")?.mode == .meterOnly)
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

    @Test func showInactiveAppsShowsPausedRegularApp() {
        let h = Harness()
        h.processes.emit([makeApp("com.example.player", playing: false, regular: true)])
        h.store.setShowInactiveApps(true)
        #expect(h.store.strips.map(\.id) == ["com.example.player"])
        #expect(h.store.strips.first?.isRunning == true)
    }

    @Test func showInactiveAppsHidesPausedBackgroundProcesses() {
        let h = Harness()
        h.processes.emit([makeApp("callservicesd", playing: false, regular: false)])
        h.store.setShowInactiveApps(true)
        #expect(h.store.strips.isEmpty)
    }

    @Test func playingBackgroundProcessAlwaysShows() {
        let h = Harness()
        h.processes.emit([makeApp("afplay", playing: true, regular: false)])
        #expect(h.store.strips.map(\.id) == ["afplay"])
    }

    @Test func pausedBackgroundProcessWithSavedSettingShows() {
        let h = Harness(document: SettingsDocument(apps: ["afplay": AppVolumeSetting(percent: 40, lastAdjusted: Harness.fixedNow)]))
        h.processes.emit([makeApp("afplay", playing: false, regular: false)])
        h.store.setShowInactiveApps(true)
        #expect(h.store.strips.map(\.id) == ["afplay"])
        #expect(h.store.strips.first?.isRunning == true)
    }

    @Test func savedAppThatIsNotRunningUsesInstalledAppNameAndIcon() throws {
        let icon = NSImage(size: NSSize(width: 8, height: 8))
        let h = Harness(
            document: SettingsDocument(apps: [
                "com.example.player": AppVolumeSetting(percent: 50, lastAdjusted: Harness.fixedNow),
                "com.example.uninstalled": AppVolumeSetting(percent: 70, lastAdjusted: Harness.fixedNow),
            ]),
            installedApp: { id in
                id == "com.example.player" ? InstalledAppInfo(displayName: "Player", icon: icon) : nil
            })
        h.store.setShowInactiveApps(true)

        let player = try #require(h.store.strips.first { $0.id == "com.example.player" })
        #expect(player.displayName == "Player")
        #expect(player.icon === icon)
        #expect(player.isRunning == false)
        let missing = try #require(h.store.strips.first { $0.id == "com.example.uninstalled" })
        #expect(missing.displayName == "com.example.uninstalled")
        #expect(missing.icon == nil)
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

    @Test func meterLoopSleepsWithATenPercentTolerance() {
        #expect(MixerStore.meterTolerance == MixerStore.meterInterval / 10)
        #expect(MixerStore.meterTolerance > .zero)
    }

    @Test func meterPollingDoesNotWriteAfterPopoverCloses() async throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(80, for: "a")
        h.store.popoverDidAppear()
        let engine = try #require(h.factory.live("a"))
        engine.peak = 0.5

        // Let the poll loop reach its sleep, then close while it is suspended.
        try await Task.sleep(for: .milliseconds(20))
        h.store.popoverDidDisappear()
        try await Task.sleep(for: .milliseconds(100))
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

    @Test func popoverVisibilityPollsEveryProcess() {
        let h = Harness()
        h.processes.emit([makeApp("a", objects: [1]), makeApp("b", playing: false, objects: [2])])
        #expect(h.processes.pollingCalls.isEmpty, "nothing depends on running state: no polling")

        h.store.popoverDidAppear()
        #expect(h.processes.pollingCalls == [.all], "live strips")

        h.store.popoverDidDisappear()
        #expect(h.processes.pollingCalls == [.all, .off])
    }

    @Test func idleLoweredAppPollsOnlyItsOwnObjects() {
        let h = Harness()
        h.processes.emit([makeApp("a", playing: false, objects: [5, 6]), makeApp("b", playing: false, objects: [7])])

        h.store.setPercent(60, for: "a")
        #expect(h.processes.pollingCalls == [.objects([5, 6])], "a missed start would otherwise play unprocessed")

        h.store.setPercent(70, for: "a")
        #expect(h.processes.pollingCalls == [.objects([5, 6])], "pushed only when it changes")

        h.store.resetVolume(for: "a")
        #expect(h.processes.pollingCalls == [.objects([5, 6]), .off])
    }

    @Test func playingAdjustedAppIsPolledSoAMissedStopIsCaught() {
        // The HAL often skips IsRunningOutput on a browser pause; without polling, the control
        // engine would keep running on silence (device and Bluetooth awake, isPlaying stale).
        let h = Harness()
        h.processes.emit([makeApp("a", objects: [5])])
        h.store.setPercent(60, for: "a")
        #expect(h.factory.live("a")?.mode == .control)
        #expect(h.processes.pollingCalls == [.objects([5])])

        h.processes.emit([makeApp("a", playing: false, objects: [5])])
        #expect(h.processes.pollingCalls == [.objects([5])], "still polled, so it's caught when it starts again")
    }

    @Test func aStopFoundByThePollTearsDownTheControlEngine() throws {
        let h = Harness(document: SettingsDocument(apps: ["zen": mutedSetting()]))
        h.processes.emit([makeApp("zen", objects: [7, 8])])
        let engine = try #require(h.factory.live("zen"))
        #expect(h.processes.pollingCalls == [.objects([7, 8])])

        // What the monitor publishes when its poll reads IsRunningOutput = 0 for both objects.
        h.processes.emit([makeApp("zen", playing: false, objects: [7, 8])])
        #expect(engine.isStopped)
        #expect(h.store.engineCount == 0)
    }

    @Test func staleProcessListAndModeChangeUpdateThenSwitchAndRebuildCleanlyIfTheSwitchFails() throws {
        let h = Harness()
        h.processes.emit([makeApp("a", objects: [42, 43])])
        h.store.popoverDidAppear()
        let meter = try #require(h.factory.live("a"))
        meter.forceProcessObjectIDs([42])  // as if a helper joined since the engine was last updated
        meter.switchError = FakeError()
        let before = h.factory.events.count

        h.store.setPercent(50, for: "a")
        #expect(Array(h.factory.events.dropFirst(before)) == ["update a [42, 43]", "switch a control", "make a control", "stop a meterOnly"])
        #expect(meter.isStopped)
        let replacement = try #require(h.factory.live("a"))
        #expect(replacement.mode == .control)
        #expect(replacement.processObjectIDs == [42, 43])
        #expect(replacement.initialGain == VolumeCurve.gain(percent: 50))
        #expect(h.store.strips.first?.engineError == nil)
    }

    @Test func savedLoweredSettingPollsWhenTheAppAppearsAndStopsWhenItLeaves() {
        let h = Harness(document: SettingsDocument(apps: ["a": AppVolumeSetting(percent: 150, lastAdjusted: Harness.fixedNow)]))
        h.processes.emit([makeApp("a", playing: false, objects: [9])])
        #expect(h.processes.pollingCalls == [.objects([9])])

        h.processes.emit([makeApp("a", playing: false, objects: [9, 10])])
        #expect(h.processes.pollingCalls == [.objects([9]), .objects([9, 10])], "a new helper is polled too")

        h.processes.emit([])
        #expect(h.processes.pollingCalls == [.objects([9]), .objects([9, 10]), .off])
    }

    @Test func idleMutedAppIsPolled() {
        let h = Harness(document: SettingsDocument(apps: ["a": mutedSetting()]))
        h.processes.emit([makeApp("a", playing: false)])
        #expect(h.processes.pollingCalls == [.objects([42])], "a muted app's missed start plays unmuted until the next poll")

        h.store.toggleMute(for: "a")
        #expect(h.processes.pollingCalls == [.objects([42]), .off])
    }

    @Test func idleLoweredAppKeepsBeingPolledAfterThePopoverCloses() {
        let h = Harness()
        h.processes.emit([makeApp("a", playing: false)])
        h.store.setPercent(60, for: "a")
        h.store.popoverDidAppear()
        h.store.popoverDidDisappear()
        #expect(h.processes.pollingCalls == [.objects([42]), .all, .objects([42])])
    }

    @Test func withoutPermissionAdjustedAppsAreNotPolled() {
        let h = Harness(document: SettingsDocument(apps: ["a": mutedSetting()]), permission: .denied)
        h.processes.emit([makeApp("a", playing: false)])
        #expect(h.processes.pollingCalls.isEmpty, "no engine can start, so nothing depends on it")
    }

    @Test func mutingPlayingLoweredAppChangesGainWithoutReplacingEngine() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(50, for: "a")
        let engine = try #require(h.factory.live("a"))
        let before = h.factory.events.count

        h.store.toggleMute(for: "a")
        #expect(h.factory.events.count == before)
        #expect(engine.currentGain == 0)
    }

    @Test func controlToMeterOnlySwitchesInPlace() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(50, for: "a")
        h.store.popoverDidAppear()
        let before = h.factory.events.count

        h.store.resetVolume(for: "a")
        #expect(Array(h.factory.events.dropFirst(before)) == ["switch a meterOnly"])
        #expect(h.factory.live("a")?.mode == .meterOnly)
    }

    @Test func processListChangeUpdatesInsteadOfRebuilding() throws {
        let h = Harness(document: SettingsDocument(apps: ["a": mutedSetting()]))
        h.processes.emit([makeApp("a", objects: [42])])
        let before = h.factory.events.count

        h.processes.emit([makeApp("a", objects: [42, 43])])
        #expect(Array(h.factory.events.dropFirst(before)) == ["update a [42, 43]"])
    }

    @Test func failedInPlaceUpdateFallsBackToMakeBeforeBreak() throws {
        let h = Harness(document: SettingsDocument(apps: ["a": mutedSetting()]))
        h.processes.emit([makeApp("a", objects: [42])])
        let old = try #require(h.factory.live("a"))
        old.updateError = FakeError()
        let before = h.factory.events.count

        h.processes.emit([makeApp("a", objects: [42, 43])])
        #expect(Array(h.factory.events.dropFirst(before)) == ["update a [42, 43]", "make a control", "stop a control"])
        #expect(old.isStopped)
        let replacement = try #require(h.factory.live("a"))
        #expect(replacement.processObjectIDs == [42, 43])
        #expect(replacement.initialGain == 0)
    }

    @Test func meterToControlSwitchesInPlaceAndKeepsTheMeter() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.popoverDidAppear()
        let meter = try #require(h.factory.live("a"))
        meter.peak = 0.5
        h.store.tickMeters(elapsed: 1.0 / 30.0)
        let level = h.store.meterLevels["a"]
        let before = h.factory.events.count

        h.store.setPercent(50, for: "a")
        #expect(Array(h.factory.events.dropFirst(before)) == ["switch a control"])
        #expect(h.store.meterLevels["a"] == level, "the same tap keeps metering")
    }

    @Test func failedModeSwitchFallsBackToMakeBeforeBreakAndClearsMeterLevel() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.popoverDidAppear()
        let meter = try #require(h.factory.live("a"))
        meter.switchError = FakeError()
        meter.peak = 0.5
        h.store.tickMeters(elapsed: 1.0 / 30.0)
        let before = h.factory.events.count

        h.store.setPercent(50, for: "a")
        #expect(Array(h.factory.events.dropFirst(before)) == ["switch a control", "make a control", "stop a meterOnly"])
        #expect(h.factory.live("a")?.mode == .control)
        #expect(h.store.meterLevels["a"] == nil, "the new engine starts with a fresh meter")
    }

    @Test func failedReplacementStopsOldEngineAndRecordsError() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.popoverDidAppear()
        let meter = try #require(h.factory.live("a"))

        meter.switchError = FakeError()
        h.factory.error = FakeError()
        h.store.setPercent(50, for: "a")
        #expect(meter.isStopped, "never keep an engine in the wrong mode")
        #expect(h.store.engineCount == 0)
        let message = try #require(h.store.strips.first?.engineError)
        #expect(message.contains("couldn't control this app's audio"))
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

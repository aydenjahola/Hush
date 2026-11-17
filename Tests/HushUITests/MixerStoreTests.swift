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
        #expect(engineB.mode == .muteOnly)

        h.output.emit(OutputDevice(id: 2, uid: "usb", name: "USB DAC"))
        #expect(engineA.rebuiltDeviceIDs == [2])
        #expect(engineB.rebuiltDeviceIDs == [2], "the store asks every engine; mute-only engines treat it as a no-op")
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

    @Test func mutedAppThatIsNotPlayingGetsMuteOnlyEngine() throws {
        let h = Harness(document: SettingsDocument(apps: ["chat": mutedSetting()]))
        h.processes.emit([makeApp("chat", playing: false)])

        let engine = try #require(h.factory.live("chat"))
        #expect(engine.mode == .muteOnly)
    }

    @Test func mutedPlayingAppGetsMuteOnlyEngineNotControl() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.toggleMute(for: "a")
        let engine = try #require(h.factory.live("a"))
        #expect(engine.mode == .muteOnly)
        #expect(h.store.engineCount == 1)
    }

    @Test func stoppingPlaybackKeepsMuteOnlyEngine() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.toggleMute(for: "a")
        let engine = try #require(h.factory.live("a"))

        h.processes.emit([makeApp("a", playing: false)])
        h.processes.emit([makeApp("a")])
        #expect(!engine.isStopped)
        #expect(h.factory.made.count == 1, "the mute tap was already in place when playback resumed")
    }

    @Test func unmutingAt50WhilePlayingSwapsToControlAtQuarterGain() throws {
        let h = Harness(document: SettingsDocument(apps: ["a": mutedSetting(percent: 50)]))
        h.processes.emit([makeApp("a")])
        let mute = try #require(h.factory.live("a"))
        #expect(mute.mode == .muteOnly)

        h.store.toggleMute(for: "a")
        #expect(mute.isStopped)
        let control = try #require(h.factory.live("a"))
        #expect(control.mode == .control)
        #expect(isApproximatelyEqual(control.initialGain, 0.25))

        h.store.toggleMute(for: "a")
        #expect(control.isStopped)
        #expect(h.factory.live("a")?.mode == .muteOnly)
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

    @Test func mutingAndUnmutingIdleAppAddsAndRemovesMuteOnlyEngine() throws {
        let h = Harness()
        h.processes.emit([makeApp("a", playing: false)])
        h.store.setShowInactiveApps(true)
        h.store.popoverDidAppear()

        h.store.setPercent(50, for: "a")
        #expect(h.factory.made.isEmpty, "idle and lowered: nothing to process yet")

        h.store.toggleMute(for: "a")
        let engine = try #require(h.factory.live("a"))
        #expect(engine.mode == .muteOnly)

        h.store.toggleMute(for: "a")
        #expect(engine.isStopped)
        #expect(h.store.engineCount == 0)
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

    @Test func muteOnlyEngineSurvivesPopoverOpeningAndClosing() throws {
        let h = Harness(document: SettingsDocument(apps: ["a": mutedSetting()]))
        h.processes.emit([makeApp("a")])
        let engine = try #require(h.factory.live("a"))

        h.store.popoverDidAppear()
        h.store.popoverDidDisappear()
        #expect(!engine.isStopped)
        #expect(h.factory.made.count == 1)
    }

    @Test func appDisappearingTearsDownMuteOnlyEngineAndKeepsSetting() throws {
        let h = Harness(document: SettingsDocument(apps: ["a": mutedSetting()]))
        h.processes.emit([makeApp("a", playing: false)])
        let first = try #require(h.factory.live("a"))

        h.processes.emit([])
        #expect(first.isStopped)
        #expect(h.store.engineCount == 0)

        h.processes.emit([makeApp("a", playing: false)])
        let second = try #require(h.factory.live("a"))
        #expect(second !== first)
        #expect(second.mode == .muteOnly)
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

    @Test func userChangeOnIdleErroredAppRetries() throws {
        let h = Harness()
        h.store.setShowInactiveApps(true)
        h.processes.emit([makeApp("a", playing: false)])
        h.factory.error = FakeError()
        h.store.toggleMute(for: "a")
        let message = try #require(h.store.strips.first?.engineError)
        #expect(message.contains("couldn't mute this app"))

        h.factory.error = nil
        h.store.setPercent(60, for: "a")
        #expect(h.factory.live("a")?.mode == .muteOnly)
        #expect(h.store.strips.first?.engineError == nil)
    }

    @Test func idleMutedAppProcessListChangeReplacesEngine() throws {
        let h = Harness(document: SettingsDocument(apps: ["a": mutedSetting()]))
        h.processes.emit([makeApp("a", playing: false, objects: [42])])
        let first = try #require(h.factory.live("a"))

        h.processes.emit([makeApp("a", playing: false, objects: [42, 43])])
        #expect(first.isStopped)
        #expect(h.factory.live("a")?.mode == .muteOnly)
        #expect(h.factory.live("a")?.processObjectIDs == [42, 43])
    }

    @Test func outputChangeKeepsMuteOnlyEngine() throws {
        let h = Harness(document: SettingsDocument(apps: ["a": mutedSetting()]))
        h.processes.emit([makeApp("a", playing: false)])
        let engine = try #require(h.factory.live("a"))
        #expect(engine.mode == .muteOnly)

        h.output.emit(OutputDevice(id: 2, uid: "usb", name: "USB DAC"))
        #expect(!engine.isStopped)
        #expect(h.factory.made.count == 1)
        #expect(h.store.strips.isEmpty || h.store.strips.first?.engineError == nil)

        h.output.emit(nil)
        #expect(engine.isStopped, "no output device: everything is torn down")
        h.output.emit(OutputDevice(id: 3, uid: "bt", name: "Headphones"))
        #expect(h.factory.live("a")?.mode == .muteOnly)
    }

    @Test func meterTickSkipsMuteOnlyEnginesAndAppsThatAreNotPlaying() throws {
        let h = Harness(document: SettingsDocument(apps: ["idle": mutedSetting(), "c": mutedSetting()]))
        h.processes.emit([makeApp("idle", playing: false), makeApp("b", objects: [43]), makeApp("c", objects: [44])])
        h.store.popoverDidAppear()
        #expect(h.store.engineCount == 3)

        h.store.tickMeters(elapsed: 1.0 / 30.0)
        #expect(Set(h.store.meterLevels.keys) == ["b"])
    }

    @Test func revokingPermissionTearsDownEveryEngineIncludingIdleMuteOnly() throws {
        let h = Harness(document: SettingsDocument(apps: [
            "muted": mutedSetting(),
            "lowered": AppVolumeSetting(percent: 50, lastAdjusted: Harness.fixedNow),
        ]))
        h.processes.emit([
            makeApp("muted", playing: false, objects: [1]),
            makeApp("lowered", objects: [2]),
            makeApp("plain", objects: [3]),
        ])
        h.store.popoverDidAppear()
        let engines = [h.factory.live("muted"), h.factory.live("lowered"), h.factory.live("plain")].compactMap { $0 }
        let modes = engines.map { $0.mode }
        #expect(modes == [.muteOnly, .control, .meterOnly])

        h.permission.status = .denied
        h.store.refreshPermission()
        #expect(!h.store.controlsEnabled)
        #expect(engines.filter { !$0.isStopped }.isEmpty)
        #expect(h.store.engineCount == 0)
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

    @Test func popoverVisibilityTogglesFastProcessPolling() {
        let h = Harness()
        #expect(h.processes.fastPollingCalls.isEmpty)

        h.store.popoverDidAppear()
        #expect(h.processes.fastPollingCalls == [true])

        h.store.popoverDidDisappear()
        #expect(h.processes.fastPollingCalls == [true, false])
    }

    @Test func presentLoweredAppTurnsFastPollingOnAndResetTurnsItOff() {
        let h = Harness()
        h.processes.emit([makeApp("a", playing: false)])
        #expect(h.processes.fastPollingCalls.isEmpty)

        h.store.setPercent(60, for: "a")
        #expect(h.processes.fastPollingCalls == [true], "a missed start would otherwise play unprocessed for up to the slow interval")

        h.store.setPercent(70, for: "a")
        #expect(h.processes.fastPollingCalls == [true], "pushed only when it changes")

        h.store.resetVolume(for: "a")
        #expect(h.processes.fastPollingCalls == [true, false])
    }

    @Test func savedLoweredSettingTurnsFastPollingOnWhenAppAppearsAndOffWhenItLeaves() {
        let h = Harness(document: SettingsDocument(apps: ["a": AppVolumeSetting(percent: 150, lastAdjusted: Harness.fixedNow)]))
        h.processes.emit([makeApp("a", playing: false)])
        #expect(h.processes.fastPollingCalls == [true])

        h.processes.emit([])
        #expect(h.processes.fastPollingCalls == [true, false])
    }

    @Test func mutedOnlyAppDoesNotNeedFastPolling() {
        let h = Harness(document: SettingsDocument(apps: ["a": mutedSetting(percent: 50)]))
        h.processes.emit([makeApp("a", playing: false)])
        #expect(h.processes.fastPollingCalls.isEmpty, "the mute tap is always on, so a missed start is already silent")
    }

    @Test func loweredAppKeepsFastPollingAfterPopoverCloses() {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(60, for: "a")
        h.store.popoverDidAppear()
        h.store.popoverDidDisappear()
        #expect(h.processes.fastPollingCalls == [true])
    }

    @Test func unmutingPlayingAppMakesControlEngineBeforeStoppingMuteTap() throws {
        let h = Harness(document: SettingsDocument(apps: ["a": mutedSetting(percent: 50)]))
        h.processes.emit([makeApp("a")])
        let mute = try #require(h.factory.live("a"))
        let before = h.factory.events.count

        h.store.toggleMute(for: "a")
        #expect(Array(h.factory.events.dropFirst(before)) == ["make a control", "stop a muteOnly"])
        #expect(mute.isStopped)
        #expect(h.factory.live("a")?.mode == .control)
        #expect(h.store.engineCount == 1)
    }

    @Test func mutingPlayingAppMakesMuteTapBeforeStoppingControlEngine() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(50, for: "a")
        let before = h.factory.events.count

        h.store.toggleMute(for: "a")
        #expect(Array(h.factory.events.dropFirst(before)) == ["make a muteOnly", "stop a control"])
        #expect(h.factory.live("a")?.mode == .muteOnly)
    }

    @Test func processListChangeMakesNewMuteTapBeforeStoppingOldOne() throws {
        let h = Harness(document: SettingsDocument(apps: ["a": mutedSetting()]))
        h.processes.emit([makeApp("a", objects: [42])])
        let old = try #require(h.factory.live("a"))
        let before = h.factory.events.count

        h.processes.emit([makeApp("a", objects: [42, 43])])
        #expect(Array(h.factory.events.dropFirst(before)) == ["make a muteOnly", "stop a muteOnly"])
        #expect(old.isStopped)
        #expect(h.factory.live("a")?.processObjectIDs == [42, 43])
    }

    @Test func meterToControlSwapIsMakeBeforeBreakAndClearsMeterLevel() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.popoverDidAppear()
        let meter = try #require(h.factory.live("a"))
        meter.peak = 0.5
        h.store.tickMeters(elapsed: 1.0 / 30.0)
        let before = h.factory.events.count

        h.store.setPercent(50, for: "a")
        #expect(Array(h.factory.events.dropFirst(before)) == ["make a control", "stop a meterOnly"])
        #expect(h.store.meterLevels["a"] == nil, "the new engine starts with a fresh meter")
    }

    @Test func failedReplacementStopsOldEngineAndRecordsError() throws {
        let h = Harness(document: SettingsDocument(apps: ["a": mutedSetting(percent: 50)]))
        h.processes.emit([makeApp("a")])
        let mute = try #require(h.factory.live("a"))

        h.factory.error = FakeError()
        h.store.toggleMute(for: "a")
        #expect(mute.isStopped, "never keep an engine in the wrong mode")
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

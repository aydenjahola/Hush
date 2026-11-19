import CoreAudio
import Foundation
import HushAudio
import HushCore
import Testing

@testable import HushUI

/// "Lower other apps during calls" in the store: detection, fades, engines, polling and saving.
/// Wake-ups never fire on their own here; `Harness.tick(after:)` moves the clock and runs one.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct DuckingStoreTests {
    static let zoomID = "us.zoom.xos"
    static let ducked = VolumeCurve.gain(percent: DuckingSettings.defaultPercent)

    func zoom(capturing: Bool, playing: Bool = false, objects: [AudioObjectID] = [7]) -> AudioApp {
        AudioApp(
            id: Self.zoomID, displayName: "zoom.us", processObjectIDs: objects, isPlaying: playing,
            isCapturingInput: capturing)
    }

    func app(_ id: String, playing: Bool = true, objects: [AudioObjectID], capturing: Bool = false) -> AudioApp {
        AudioApp(id: id, displayName: id, processObjectIDs: objects, isPlaying: playing, isCapturingInput: capturing)
    }

    /// A harness with ducking on and nothing playing yet.
    func duckingHarness(document: SettingsDocument = SettingsDocument()) -> Harness {
        var document = document
        if document.ducking == nil { document.ducking = DuckingSettings(isEnabled: true) }
        return Harness(document: document)
    }

    /// Starts a call in Zoom with `others` playing, and runs the fade down to the end.
    func startCall(_ h: Harness, others: [AudioApp]) {
        h.processes.emit([zoom(capturing: true)] + others)
        h.tick(after: CallActivity.startDelay)
        h.tick(after: DuckingFade.downDuration)
    }

    // MARK: Off by default

    @Test func offByDefaultNothingChanges() {
        let h = Harness()
        h.processes.emit([zoom(capturing: true), app("music", objects: [42])])
        h.clock.advance(5)

        #expect(!h.store.duckingEnabled)
        #expect(h.factory.made.isEmpty)
        #expect(h.processes.inputPollingCalls.isEmpty, "input is never tracked")
        #expect(h.store.pendingDuckingWake == nil)
        #expect(h.store.duckingIndicator == nil)
        #expect(h.store.duckingTask == nil)
    }

    @Test func enablingTracksTheCallAppsInputAndDisablingStops() {
        let h = Harness()
        h.processes.emit([zoom(capturing: false), app("music", objects: [42])])

        h.store.setDuckingEnabled(true)
        #expect(h.processes.inputPollingCalls.last == .objects([7]))

        h.store.setDuckingEnabled(false)
        #expect(h.processes.inputPollingCalls.last == .some(nil))
    }

    @Test func withNoCallAppPresentInputIsStillListenedTo() {
        let h = Harness()
        h.processes.emit([app("music", objects: [42])])
        h.store.setDuckingEnabled(true)
        #expect(h.processes.inputPollingCalls.last == .off, "listeners catch a call app appearing")
    }

    @Test func aHiddenCallAppIsStillPolled() {
        let h = duckingHarness(
            document: SettingsDocument(hiddenApps: [HiddenApp(bundleID: Self.zoomID, displayName: "zoom.us")]))
        h.processes.emit([zoom(capturing: false)])
        #expect(h.processes.inputPollingCalls.last == .objects([7]))
    }

    @Test func noInputTrackingWithoutPermission() {
        let h = duckingHarness()
        let denied = Harness(document: SettingsDocument(ducking: DuckingSettings(isEnabled: true)), permission: .denied)
        h.processes.emit([zoom(capturing: false)])
        denied.processes.emit([zoom(capturing: true), app("music", objects: [42])])
        denied.tick(after: 1)
        #expect(denied.processes.inputPollingCalls.isEmpty)
        #expect(denied.store.activeCallApps.isEmpty)
        #expect(denied.factory.made.isEmpty)
    }

    // MARK: Detection and fades

    @Test func aCallDucksOtherAppsAfterTheStartDelay() throws {
        let h = duckingHarness()
        h.processes.emit([zoom(capturing: true), app("music", objects: [42])])
        #expect(h.store.activeCallApps.isEmpty)
        #expect(h.factory.made.isEmpty)
        #expect(h.store.pendingDuckingWake == .milliseconds(500))

        h.tick(after: CallActivity.startDelay)
        #expect(h.store.activeCallApps == [Self.zoomID])
        let engine = try #require(h.factory.live("music"))
        #expect(engine.mode == .control, "a playing app at 100% is taken over while ducked")
        #expect(engine.initialGain == 1, "the fade starts at full level")
        #expect(h.store.pendingDuckingWake == .milliseconds(20), "fade steps")

        h.tick(after: DuckingFade.downDuration / 2)
        #expect(engine.currentGain < 1 && engine.currentGain > Self.ducked)

        h.tick(after: DuckingFade.downDuration / 2)
        #expect(isApproximatelyEqual(engine.currentGain, Self.ducked))
        #expect(h.store.pendingDuckingWake == nil, "settled with nothing pending")
        #expect(h.factory.live(Self.zoomID) == nil, "the call app isn't touched")
    }

    @Test func aMomentaryMicrophoneProbeDucksNothing() {
        let h = duckingHarness()
        h.processes.emit([zoom(capturing: true), app("music", objects: [42])])
        h.clock.advance(0.2)
        h.processes.emit([zoom(capturing: false), app("music", objects: [42])])
        h.tick(after: 1)
        #expect(h.store.activeCallApps.isEmpty)
        #expect(h.factory.made.isEmpty)
        #expect(h.store.pendingDuckingWake == nil)
    }

    @Test func endingTheCallFadesBackUpAfterTheStopDelayAndDropsTheEngine() throws {
        let h = duckingHarness()
        startCall(h, others: [app("music", objects: [42])])
        let engine = try #require(h.factory.live("music"))

        h.processes.emit([zoom(capturing: false), app("music", objects: [42])])
        #expect(h.store.activeCallApps == [Self.zoomID], "held for the stop delay")
        #expect(isApproximatelyEqual(engine.currentGain, Self.ducked))
        #expect(h.store.pendingDuckingWake == .seconds(2))

        h.tick(after: CallActivity.stopDelay)
        #expect(h.store.activeCallApps.isEmpty)
        #expect(h.store.duckingIndicator == nil)
        h.tick(after: DuckingFade.upDuration / 2)
        #expect(engine.currentGain > Self.ducked && engine.currentGain < 1)
        #expect(!engine.isStopped)

        h.tick(after: DuckingFade.upDuration / 2)
        #expect(engine.isStopped, "at 100% with the popover closed, no engine once the fade is done")
        #expect(h.store.engineCount == 0)
        #expect(h.store.pendingDuckingWake == nil)
    }

    @Test func unmutingWithinTheStopDelayKeepsDucking() throws {
        let h = duckingHarness()
        startCall(h, others: [app("music", objects: [42])])
        let engine = try #require(h.factory.live("music"))

        h.processes.emit([zoom(capturing: false), app("music", objects: [42])])
        h.clock.advance(1)
        h.processes.emit([zoom(capturing: true), app("music", objects: [42])])
        h.tick(after: 5)
        #expect(h.store.activeCallApps == [Self.zoomID])
        #expect(isApproximatelyEqual(engine.currentGain, Self.ducked))
    }

    @Test func anAppThatStartsPlayingMidCallIsDuckedAtOnce() throws {
        let h = duckingHarness()
        startCall(h, others: [])
        h.processes.emit([zoom(capturing: true), app("music", objects: [42])])
        let engine = try #require(h.factory.live("music"))
        #expect(engine.mode == .control)
        #expect(isApproximatelyEqual(engine.initialGain, Self.ducked))
    }

    // MARK: What is ducked

    @Test func callAppsExceptionsAndHiddenAppsAreNotDucked() throws {
        var ducking = DuckingSettings(isEnabled: true)
        ducking.addException(DuckingApp(bundleID: "podcast", displayName: "Podcast"))
        let h = duckingHarness(
            document: SettingsDocument(
                hiddenApps: [HiddenApp(bundleID: "hidden", displayName: "Hidden")], ducking: ducking))
        startCall(
            h,
            others: [
                app("com.apple.Safari", objects: [1]), app("podcast", objects: [2]), app("hidden", objects: [3]),
                app("music", objects: [4]),
            ])
        #expect(h.factory.live("com.apple.Safari") == nil, "a call app that isn't in the call keeps its level")
        #expect(h.factory.live("podcast") == nil)
        #expect(h.factory.live("hidden") == nil, "Hush never adjusts a hidden app")
        #expect(h.factory.live("music") != nil)
    }

    @Test func aHiddenCallAppStillStartsDucking() {
        let h = duckingHarness(
            document: SettingsDocument(hiddenApps: [HiddenApp(bundleID: Self.zoomID, displayName: "zoom.us")]))
        startCall(h, others: [app("music", objects: [42])])
        #expect(h.store.activeCallApps == [Self.zoomID])
        #expect(h.factory.live("music") != nil)
    }

    @Test func aHelperCapturingCountsThroughItsApp() {
        // The monitor groups helpers under their app, so a browser tab in a Meet call reports
        // the browser itself as capturing.
        let h = duckingHarness()
        h.processes.emit([app("com.google.Chrome", playing: false, objects: [5, 6], capturing: true)])
        h.tick(after: CallActivity.startDelay)
        #expect(h.store.activeCallApps == ["com.google.Chrome"])
    }

    // MARK: Gain

    @Test func duckingMultipliesTheAppsOwnLevel() throws {
        let h = duckingHarness(
            document: SettingsDocument(apps: ["music": AppVolumeSetting(percent: 50, lastAdjusted: Harness.fixedNow)]))
        startCall(h, others: [app("music", objects: [42])])
        let engine = try #require(h.factory.live("music"))
        #expect(isApproximatelyEqual(engine.currentGain, 0.25 * Self.ducked))
    }

    @Test func aMutedAppStaysMuted() throws {
        let h = duckingHarness(document: SettingsDocument(apps: ["music": mutedSetting()]))
        startCall(h, others: [app("music", objects: [42])])
        #expect(try #require(h.factory.live("music")).currentGain == 0)
    }

    @Test func changingTheLevelMidDuckKeepsTheMultiplier() throws {
        let h = duckingHarness()
        startCall(h, others: [app("music", objects: [42])])
        let engine = try #require(h.factory.live("music"))

        h.store.setPercent(50, for: "music")
        #expect(isApproximatelyEqual(engine.currentGain, 0.25 * Self.ducked))
        #expect(h.store.strips.first { $0.id == "music" }?.setting.percent == 50, "the fader shows the own level")
    }

    @Test func changingTheAmountMidDuckFadesToTheNewLevel() throws {
        let h = duckingHarness()
        startCall(h, others: [app("music", objects: [42])])
        let engine = try #require(h.factory.live("music"))

        h.store.duckingPercent = 50
        #expect(isApproximatelyEqual(engine.currentGain, Self.ducked), "no jump")
        h.tick(after: DuckingFade.upDuration)
        #expect(isApproximatelyEqual(engine.currentGain, 0.25))
    }

    @Test func turningDuckingOffMidCallFadesBackUp() throws {
        let h = duckingHarness()
        startCall(h, others: [app("music", objects: [42])])
        let engine = try #require(h.factory.live("music"))

        h.store.setDuckingEnabled(false)
        #expect(h.store.activeCallApps.isEmpty)
        #expect(isApproximatelyEqual(engine.currentGain, Self.ducked), "no jump")
        h.tick(after: DuckingFade.upDuration / 2)
        #expect(engine.currentGain > Self.ducked && engine.currentGain < 1)
        h.tick(after: DuckingFade.upDuration / 2)
        #expect(engine.isStopped)
    }

    @Test func switchingOutputMidDuckKeepsTheMultiplier() throws {
        let h = duckingHarness()
        startCall(h, others: [app("music", objects: [42])])
        let engine = try #require(h.factory.live("music"))

        h.output.emit(OutputDevice(id: 2, uid: "airpods", name: "AirPods"))
        #expect(engine.rebuiltDeviceIDs == [2])
        #expect(isApproximatelyEqual(engine.currentGain, Self.ducked))
        #expect(engine.mode == .control)
    }

    @Test func perDeviceLevelsLoadedMidDuckAreDucked() throws {
        var preferences = Preferences()
        preferences.rememberLevelsPerDevice = true
        let h = duckingHarness(
            document: SettingsDocument(
                preferences: preferences,
                deviceLevels: [
                    "airpods": DeviceLevels(
                        name: "AirPods", apps: ["music": AppVolumeSetting(percent: 50, lastAdjusted: Harness.fixedNow)])
                ]))
        startCall(h, others: [app("music", objects: [42])])
        let engine = try #require(h.factory.live("music"))

        h.output.emit(OutputDevice(id: 2, uid: "airpods", name: "AirPods"))
        #expect(isApproximatelyEqual(engine.gainsAtRebuild.last ?? -1, 0.25 * Self.ducked))
        #expect(isApproximatelyEqual(engine.currentGain, 0.25 * Self.ducked))
    }

    @Test func applyingAPresetMidDuckKeepsTheMultiplier() throws {
        let h = duckingHarness()
        startCall(h, others: [app("music", objects: [42])])
        h.store.setPercent(50, for: "music")
        let preset = try #require(h.store.saveCurrentLevelsAsPreset(named: "Quiet"))
        h.store.setPercent(100, for: "music")
        #expect(h.store.activePresetID == nil)
        h.store.applyPreset(preset.id)
        #expect(isApproximatelyEqual(try #require(h.factory.live("music")).currentGain, 0.25 * Self.ducked))
        #expect(h.store.activePresetID == preset.id, "the checkmark follows the own levels")
    }

    // MARK: Never saved

    @Test func duckingIsNeverWrittenIntoLevelsPresetsOrTheFile() throws {
        let h = duckingHarness()
        startCall(h, others: [app("music", objects: [42])])
        h.store.flushPendingSave()

        #expect(h.store.settings.isEmpty)
        #expect(h.store.strips.first { $0.id == "music" }?.setting == AppVolumeSetting())
        #expect(h.persister.saved.allSatisfy { $0.apps.isEmpty })
        #expect(h.persister.document.apps.isEmpty)
        #expect(h.store.saveCurrentLevelsAsPreset(named: "During call")?.apps.isEmpty == true)
    }

    @Test func duckingSettingsAreSavedWithTheLevelsAndNotClobbered() throws {
        let h = Harness()
        h.processes.emit([app("music", objects: [42])])
        h.store.setDuckingEnabled(true)
        h.store.duckingPercent = 45
        h.store.addDuckingException(DuckingApp(bundleID: "podcast", displayName: "Podcast"))
        h.store.flushPendingSave()
        #expect(h.persister.document.ducking?.percent == 45)

        h.store.setPercent(60, for: "music")
        h.store.flushPendingSave()
        let saved = try #require(h.persister.document.ducking)
        #expect(saved.isEnabled)
        #expect(saved.percent == 45)
        #expect(saved.isException("podcast"))
        #expect(h.persister.document.apps["music"]?.percent == 60)
    }

    @Test func defaultDuckingSettingsAreNotWritten() {
        let h = Harness()
        h.store.setDuckingEnabled(true)
        h.store.setDuckingEnabled(false)
        h.store.flushPendingSave()
        #expect(h.persister.document.ducking == nil)
    }

    @Test func savedDuckingSettingsLoad() {
        let h = Harness(document: SettingsDocument(ducking: DuckingSettings(isEnabled: true, percent: 20)))
        #expect(h.store.duckingEnabled)
        #expect(h.store.duckingPercent == 20)
    }

    // MARK: Lists

    @Test func editingTheListsAppliesAtOnce() throws {
        let h = duckingHarness()
        startCall(h, others: [app("music", objects: [42])])
        let engine = try #require(h.factory.live("music"))

        h.store.addDuckingException(DuckingApp(bundleID: "music", displayName: "Music"))
        #expect(engine.isStopped, "an exception is never ducked")

        h.store.removeDuckingException("music")
        h.store.removeCallApp(Self.zoomID)
        #expect(h.store.activeCallApps == [Self.zoomID], "a removed call app counts as stopped, so it's held")
        h.tick(after: CallActivity.stopDelay)
        #expect(h.store.activeCallApps.isEmpty)

        h.store.restoreDefaultCallApps()
        #expect(h.store.duckingSettings.usesDefaultCallApps)
    }

    @Test func candidatesAreRunningAppsNotAlreadyListed() {
        let h = Harness()
        h.processes.emit([
            zoom(capturing: false), app("music", objects: [1]),
            AudioApp(id: "daemon", displayName: "daemon", processObjectIDs: [2], isPlaying: false, isRegularApp: false),
            AudioApp(id: HushIdentity.bundleID, displayName: "Hush", processObjectIDs: [3], isPlaying: true),
        ])
        let candidates = h.store.duckingCandidates(excluding: [Self.zoomID])
        #expect(candidates.map(\.bundleID) == ["music"])
    }

    // MARK: Indicator

    @Test func theIndicatorNamesTheCallAppOrCountsThem() {
        let h = duckingHarness()
        h.processes.emit([
            zoom(capturing: true),
            app("com.hnc.Discord", playing: false, objects: [8], capturing: true),
        ])
        #expect(h.store.duckingIndicator == nil)
        h.tick(after: CallActivity.startDelay)
        #expect(h.store.duckingIndicator == DuckingIndicator(appNames: ["Discord", "Zoom"]))

        h.processes.emit([zoom(capturing: true)])
        h.tick(after: CallActivity.stopDelay)
        #expect(h.store.duckingIndicator == DuckingIndicator(appNames: ["Zoom"]), "the call list's name")
    }

    // MARK: Polling

    @Test func duckedAppsArePolledWhileDuckedAndNotAfter() {
        let h = duckingHarness()
        startCall(h, others: [app("music", objects: [42]), app("paused", playing: false, objects: [43])])
        #expect(h.processes.pollingCalls.last == .objects([42, 43]))

        h.processes.emit([
            zoom(capturing: false), app("music", objects: [42]), app("paused", playing: false, objects: [43]),
        ])
        h.tick(after: CallActivity.stopDelay)
        h.tick(after: DuckingFade.upDuration)
        #expect(h.processes.pollingCalls.last == .off)
    }

    @Test func aBurstOfAppChangesKeepsThePendingFadeStep() throws {
        let h = duckingHarness()
        h.processes.emit([zoom(capturing: true), app("music", objects: [42])])
        h.tick(after: CallActivity.startDelay)
        let step = try #require(h.store.duckingTask)

        h.clock.advance(0.01)
        h.processes.emit([
            zoom(capturing: true), app("music", objects: [42]), app("other", playing: false, objects: [9]),
        ])
        h.processes.emit([zoom(capturing: true), app("music", objects: [42])])
        #expect(h.store.duckingTask == step, "the step that was due sooner isn't pushed back")
    }

    @Test func aMidFadeStepOnlySetsGains() throws {
        let h = duckingHarness()
        h.processes.emit([zoom(capturing: true), app("music", objects: [42])])
        h.tick(after: CallActivity.startDelay)
        let engine = try #require(h.factory.live("music"))
        // A process list that differs from the app's is only corrected by a full reconcile, so it
        // shows which steps reconcile: not the mid-fade one, but the one that settles the fade.
        engine.forceProcessObjectIDs([99])

        h.tick(after: DuckingFade.downDuration / 2)
        #expect(engine.currentGain < 1 && engine.currentGain > Self.ducked)
        #expect(engine.processObjectIDs == [99])

        h.tick(after: DuckingFade.downDuration / 2)
        #expect(isApproximatelyEqual(engine.currentGain, Self.ducked))
        #expect(engine.processObjectIDs == [42])
    }

    @Test func aFailedDuckingOnlyEngineShowsNoWarningAndIsRetriedNextCall() throws {
        let h = duckingHarness()
        h.factory.error = FakeError()
        startCall(h, others: [app("music", objects: [42])])
        let attempts = { h.factory.events.filter { $0 == "make music control" }.count }
        #expect(attempts() == 1)
        #expect(h.store.strips.first { $0.id == "music" }?.engineError == nil, "the user's level didn't fail")

        h.processes.emit([
            zoom(capturing: true), app("music", objects: [42]), app("other", playing: false, objects: [9]),
        ])
        #expect(attempts() == 1, "not retried during the same call")

        // End the call and let the fade finish, then a new call tries again.
        h.processes.emit([zoom(capturing: false), app("music", objects: [42])])
        h.tick(after: CallActivity.stopDelay)
        h.tick(after: DuckingFade.upDuration)
        h.factory.error = nil
        startCall(h, others: [app("music", objects: [42])])
        #expect(attempts() == 2)
        #expect(h.factory.live("music")?.mode == .control)
    }

    @Test func aRelaunchedAppGetsAFreshDuckingTryInTheSameCall() {
        let h = duckingHarness()
        h.factory.error = FakeError()
        startCall(h, others: [app("music", objects: [42])])
        let attempts = { h.factory.events.filter { $0 == "make music control" }.count }
        #expect(attempts() == 1)

        h.factory.error = nil
        h.processes.emit([zoom(capturing: true)])  // music quits
        h.processes.emit([zoom(capturing: true), app("music", objects: [50])])  // and comes back
        #expect(attempts() == 2)
        #expect(h.factory.live("music")?.mode == .control)
    }

    @Test func aFailedEngineForALoweredAppStillWarns() {
        let h = duckingHarness(
            document: SettingsDocument(apps: ["music": AppVolumeSetting(percent: 50, lastAdjusted: Harness.fixedNow)]))
        h.factory.error = FakeError()
        startCall(h, others: [app("music", objects: [42])])
        #expect(h.store.strips.first { $0.id == "music" }?.engineError != nil)
    }

    // MARK: Wake-ups, input tracking and saving

    @Test func aDebounceDeadlineFiresATickOnItsOwn() async throws {
        // Only the 0.5 s debounce sleep returns; fade steps (20 ms) stay suspended.
        let h = Harness(
            document: SettingsDocument(ducking: DuckingSettings(isEnabled: true)),
            duckingSleep: { duration in
                if duration == .milliseconds(500) { return }
                try await Task.sleep(for: .seconds(3600))
            })
        h.processes.emit([zoom(capturing: true), app("music", objects: [42])])
        h.clock.advance(CallActivity.startDelay)  // the time when the sleep returns

        var spins = 0
        while h.store.activeCallApps.isEmpty {
            spins += 1
            try #require(spins < 10_000, "the deadline never fired")
            await Task.yield()
        }
        #expect(h.store.activeCallApps == [Self.zoomID])
        #expect(h.factory.live("music")?.mode == .control)
        h.store.shutdown()
    }

    @Test func aFreshStoreWithDuckingOffSchedulesNothingAndTracksNoInput() {
        let h = Harness()
        h.processes.emit([zoom(capturing: false), app("music", objects: [42])])
        #expect(h.store.duckingTask == nil)
        #expect(h.store.currentInputPolling == nil)
        #expect(h.processes.inputPollingCalls.allSatisfy { $0 == nil }, "never asks the source to track input")
    }

    @Test func losingPermissionStopsInputTracking() {
        let h = duckingHarness()
        h.processes.emit([zoom(capturing: false)])
        #expect(h.processes.inputPollingCalls.last == .objects([7]))

        h.permission.status = .denied
        h.store.refreshPermission()
        #expect(h.processes.inputPollingCalls.last == .some(nil))
    }

    @Test func aLevelSaveKeepsLoadedDuckingSettings() {
        var ducking = DuckingSettings(isEnabled: true, percent: 15)
        ducking.removeCallApp("com.apple.Safari")
        let h = Harness(document: SettingsDocument(ducking: ducking))
        h.processes.emit([app("music", objects: [42])])

        h.store.setPercent(70, for: "music")
        h.store.flushPendingSave()
        #expect(h.persister.document.ducking == ducking)
        #expect(h.persister.document.apps["music"]?.percent == 70)
    }

    @Test func shutdownCancelsThePendingWake() {
        let h = duckingHarness()
        h.processes.emit([zoom(capturing: true)])
        #expect(h.store.duckingTask != nil)
        h.store.shutdown()
        #expect(h.store.duckingTask == nil)
    }
}

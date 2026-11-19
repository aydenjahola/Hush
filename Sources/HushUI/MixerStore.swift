import AppKit
import CoreAudio
import Foundation
import HushAudio
import HushCore
import Observation
import os

@MainActor
@Observable
package final class MixerStore {
    package struct Strip: Identifiable, Equatable {
        package let id: String
        package var displayName: String
        package var icon: NSImage?
        package var isPlaying: Bool
        /// False for saved apps that aren't running (only shown with "show inactive apps").
        package var isRunning: Bool
        package var setting: AppVolumeSetting
        /// Tooltip text for the warning badge when the engine failed.
        package var engineError: String?
    }

    // MARK: Published state

    package internal(set) var strips: [Strip] = []
    /// Ballistics state for the meters. Not observed: views read their `StripMeter` instead.
    @ObservationIgnored package internal(set) var meterLevels: [String: Float] = [:]
    package internal(set) var preferences: Preferences
    package private(set) var permission: AudioCapturePermissionStatus = .undetermined
    /// The system default output, as last reported by the output source (never set optimistically).
    package internal(set) var outputDevice: OutputDevice?
    /// Every output device the user can switch to from the header menu.
    package internal(set) var outputDevices: [OutputDevice] = []
    /// A short-lived message after choosing an output failed; cleared after a few seconds or on the next success.
    package internal(set) var outputSelectionError: String?
    package internal(set) var isPopoverVisible = false
    /// Apps hidden from the mixer, sorted by name. Shown again from Settings.
    package private(set) var hiddenApps: [HiddenApp]
    /// Saved presets; see MixerStore+Presets. Saved in the same write as the levels.
    package internal(set) var presetLibrary: PresetLibrary
    /// Each output device's saved levels; see MixerStore+DeviceLevels. Saved in the same write as
    /// the levels, and kept while "Remember levels for each output device" is off.
    package internal(set) var deviceLevelBook: DeviceLevelBook
    /// "Lower other apps during calls"; see MixerStore+Ducking. Saved in the same write as the
    /// levels. Only the settings are saved, never whether a call is on.
    package internal(set) var duckingSettings: DuckingSettings
    /// The call apps in a call right now (debounced by `CallActivity`), for the popover's indicator.
    package internal(set) var activeCallApps: Set<String> = []

    package var controlsEnabled: Bool { permission == .authorized }
    package var playingCount: Int { apps.filter(\.isPlaying).count }
    package var maxPercent: Int { preferences.maxBoostPercent.rawValue }
    package var isAnyAppAttenuated: Bool {
        apps.contains { app in
            guard let setting = settings[app.id] else { return false }
            return setting.isMuted || setting.percent < 100
        }
    }

    // MARK: Private state

    /// The apps the mixer works with: `allApps` minus the hidden ones (see `HiddenAppsPlan`).
    var apps: [AudioApp] = []
    /// Every app the process source last reported, hidden ones included.
    var allApps: [AudioApp] = []
    var settings: [String: AppVolumeSetting]
    var engineErrors: [String: String] = [:]
    /// Apps whose current error came from a meter-only engine, so turning meters off can clear it.
    @ObservationIgnored var meterOnlyErrorIDs: Set<String> = []

    @ObservationIgnored let processSource: any AudioProcessSource
    @ObservationIgnored let outputSource: any OutputDeviceSource
    /// How long `outputSelectionError` stays up.
    @ObservationIgnored let outputErrorDuration: Duration
    @ObservationIgnored var outputErrorTask: Task<Void, Never>?
    @ObservationIgnored let engineFactory: any AudioEngineFactory
    /// Where `NSWorkspace.didWakeNotification` arrives (injectable for tests).
    @ObservationIgnored private let wakeNotifications: NotificationCenter
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?
    /// How long the health check waits before its first reading (see `scheduleHealthCheck`).
    @ObservationIgnored let healthCheckDelay: Duration
    /// How much longer it waits before confirming a suspected stall and rebuilding.
    @ObservationIgnored let stallConfirmDelay: Duration
    /// How long after a failed stall rebuild Hush tries that app again.
    @ObservationIgnored let stallRetryDelay: Duration
    /// The pending health check, if any (exposed for tests).
    @ObservationIgnored var healthCheckTask: Task<Void, Never>?
    /// The engines the pending health check is watching, as of its last reading.
    @ObservationIgnored var healthReadings: [String: EngineReading] = [:]
    /// Apps whose current error came from a failed stall rebuild, so it's retried automatically.
    @ObservationIgnored var stallRetryIDs: Set<String> = []
    @ObservationIgnored var stallRetryTask: Task<Void, Never>?
    @ObservationIgnored private let permissionSource: any AudioCapturePermissionSource
    @ObservationIgnored private let persister: any SettingsPersisting
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored let installedApp: @MainActor (String) -> InstalledAppInfo?
    @ObservationIgnored var installedAppCache: [String: InstalledAppInfo?] = [:]
    @ObservationIgnored var engines: [String: any AudioEngineHandle] = [:]
    /// The output device the current levels belong to while levels are remembered per device;
    /// nil while the feature is off or before the first output with a UID is reported.
    @ObservationIgnored var levelsDevice: DeviceLevelBook.Device?
    @ObservationIgnored var order: [String] = []
    @ObservationIgnored let saver: DebouncedSaver
    @ObservationIgnored var meterTask: Task<Void, Never>?
    @ObservationIgnored let meterBank = MeterBank()
    /// Last value pushed to `processSource.setPolling`.
    @ObservationIgnored var currentPolling: ProcessPolling = .off
    /// The first-launch permission request, if one was made (exposed for tests).
    @ObservationIgnored private(set) var permissionRequest: Task<Void, Never>?
    @ObservationIgnored let logger = Logger(subsystem: HushIdentity.bundleID, category: "engine")
    /// Last value pushed to `processSource.setInputPolling` (nil, the source's default, is "off").
    @ObservationIgnored var currentInputPolling: ProcessPolling?
    /// Which call apps capture input, debounced over time.
    @ObservationIgnored var callActivity = CallActivity()
    /// The ducking multiplier over time.
    @ObservationIgnored var duckingFade = DuckingFade()
    /// The next ducking wake-up: a fade step or a call-detection deadline.
    @ObservationIgnored var duckingTask: Task<Void, Never>?
    /// How long until `duckingTask` wakes (exposed for tests); nil when none is pending.
    @ObservationIgnored var pendingDuckingWake: Duration?
    /// How often a fade steps the gain. The IOProc ramps each step across one buffer.
    @ObservationIgnored let duckingStep: Duration
    @ObservationIgnored let duckingSleep: @Sendable (Duration) async throws -> Void

    package init(
        processSource: any AudioProcessSource,
        outputSource: any OutputDeviceSource,
        engineFactory: any AudioEngineFactory,
        permissionSource: any AudioCapturePermissionSource,
        persister: any SettingsPersisting,
        saveDelay: Duration = .milliseconds(500),
        outputErrorDuration: Duration = .seconds(4),
        wakeNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
        healthCheckDelay: Duration = .milliseconds(300),
        stallConfirmDelay: Duration = .milliseconds(1700),
        stallRetryDelay: Duration = .seconds(3),
        duckingStep: Duration = .milliseconds(20),
        duckingSleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping () -> Date = Date.init,
        installedApp: @escaping @MainActor (String) -> InstalledAppInfo? = InstalledAppInfo.lookUp(bundleID:)
    ) {
        self.processSource = processSource
        self.outputSource = outputSource
        self.engineFactory = engineFactory
        self.permissionSource = permissionSource
        self.persister = persister
        self.saver = DebouncedSaver(delay: saveDelay)
        self.outputErrorDuration = outputErrorDuration
        self.wakeNotifications = wakeNotifications
        self.healthCheckDelay = healthCheckDelay
        self.stallConfirmDelay = stallConfirmDelay
        self.stallRetryDelay = stallRetryDelay
        self.duckingStep = duckingStep
        self.duckingSleep = duckingSleep
        self.now = now
        self.installedApp = installedApp
        let document = persister.load()
        self.preferences = document.preferences
        let hiddenApps = document.hiddenApps?.normalized() ?? []
        self.hiddenApps = hiddenApps
        self.settings = HiddenAppsPlan.visibleSettings(document.apps, hidden: hiddenApps.ids)
        self.presetLibrary = PresetLibrary(presets: document.presets ?? [])
        self.deviceLevelBook = DeviceLevelBook(sets: document.deviceLevels ?? [:])
            .normalized(excluding: hiddenApps.ids)
        self.duckingSettings = document.ducking ?? DuckingSettings()
        saver.perform = { [weak self] in self?.persistNow() }
    }

    package func start() {
        permission = permissionSource.currentStatus()
        outputSource.start { [weak self] device in self?.outputDidChange(device) }
        outputSource.observeDevices { [weak self] devices in self?.outputDevicesDidChange(devices) }
        processSource.start { [weak self] apps in self?.appsDidChange(apps) }
        wakeObserver = wakeNotifications.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemDidWake() }
        }
        if permission == .undetermined {
            permissionRequest = Task { [weak self] in
                guard let self else { return }
                let status = await self.permissionSource.requestAccess()
                self.permissionDidChange(status)
            }
        }
    }

    // MARK: User actions

    package func setPercent(_ percent: Int, for id: String) {
        guard controlsEnabled, !isHidden(id) else { return }
        var setting = settings[id] ?? AppVolumeSetting()
        setting.setPercent(percent, maxPercent: maxPercent)
        setting.lastAdjusted = now()
        commit(setting, for: id)
    }

    package func resetVolume(for id: String) {
        setPercent(100, for: id)
    }

    package func toggleMute(for id: String) {
        guard controlsEnabled else { return }
        var setting = settings[id] ?? AppVolumeSetting()
        setting.isMuted.toggle()
        setting.lastAdjusted = now()
        commit(setting, for: id)
    }

    /// Mutes every app that's playing right now, keeping each one's percent. Apps that aren't
    /// playing are left alone. One debounced save, like `toggleMute(for:)`.
    package func muteAllPlaying() {
        guard controlsEnabled else { return }
        let ids = apps.filter(\.isPlaying).map(\.id).filter { settings[$0]?.isMuted != true }
        guard !ids.isEmpty else { return }
        for id in ids {
            var setting = settings[id] ?? AppVolumeSetting()
            setting.isMuted = true
            setting.lastAdjusted = now()
            settings[id] = setting
            engineErrors[id] = nil
        }
        settingsDidChange()
    }

    /// Unmutes every muted app, playing or not, including saved settings for apps that aren't
    /// running, so nothing stays silenced after "Unmute All". Percents are kept.
    package func unmuteAll() {
        guard controlsEnabled else { return }
        let ids = settings.filter(\.value.isMuted).map(\.key)
        guard !ids.isEmpty else { return }
        for id in ids {
            guard var setting = settings[id] else { continue }
            setting.isMuted = false
            setting.lastAdjusted = now()
            settings[id] = setting.isDefault ? nil : setting
            engineErrors[id] = nil
        }
        settingsDidChange()
    }

    /// What the quick menu's bulk mute item offers: "Unmute All" once every playing app is muted
    /// (or nothing plays but something is muted), otherwise "Mute All Playing Apps".
    package var bulkMute: BulkMuteAction {
        let playing = apps.filter(\.isPlaying)
        let anyMuted = settings.values.contains(where: \.isMuted)
        let allPlayingMuted = playing.allSatisfy { settings[$0.id]?.isMuted == true }
        if anyMuted, allPlayingMuted {
            return BulkMuteAction(kind: .unmuteAll, isEnabled: controlsEnabled)
        }
        return BulkMuteAction(kind: .muteAllPlaying, isEnabled: controlsEnabled && !playing.isEmpty)
    }

    package func setMaxBoost(_ limit: BoostLimit) {
        preferences.maxBoostPercent = limit
        settings = SettingsDocument(preferences: preferences, apps: settings).normalized().apps
        settingsDidChange()
    }

    package func setShowInactiveApps(_ show: Bool) {
        preferences.showInactiveApps = show
        settingsDidChange()
    }

    /// Settable views of the preferences, so Settings can bind to them with `@Bindable`.
    package var maxBoost: BoostLimit {
        get { preferences.maxBoostPercent }
        set { setMaxBoost(newValue) }
    }

    package var showInactiveApps: Bool {
        get { preferences.showInactiveApps }
        set { setShowInactiveApps(newValue) }
    }

    /// Applies a Settings → Appearance change, persists it and updates meters and order to match.
    func updateAppearance(_ change: (inout AppearancePreferences) -> Void) {
        let old = preferences.appearance
        change(&preferences.appearance)
        let new = preferences.appearance
        guard new != old else { return }
        if new.sortMode != old.sortMode { order = [] }
        if !new.showLevelMeters, old.showLevelMeters {
            // "Couldn't read this app's level" is moot once nothing reads levels.
            for id in meterOnlyErrorIDs { engineErrors[id] = nil }
            meterOnlyErrorIDs = []
        }
        if new.showLevelMeters != old.showLevelMeters, isPopoverVisible {
            if new.showLevelMeters {
                startMeterPolling()
            } else {
                stopMeterPolling()
                clearMeterLevels()
            }
        }
        settingsDidChange()
    }

    /// Hides an app from the mixer. Its saved level is dropped, so it plays at its normal volume,
    /// and its engine (if any) is torn down. Allowed without permission: it never adjusts audio.
    package func hideApp(_ id: String, displayName: String) {
        let result = HiddenAppsPlan.hide(
            HiddenApp(bundleID: id, displayName: displayName), hidden: hiddenApps, settings: settings)
        hiddenApps = result.hidden
        settings = result.settings
        engineErrors[id] = nil
        meterOnlyErrorIDs.remove(id)
        stallRetryIDs.remove(id)
        hiddenAppsDidChange()
    }

    func isHidden(_ id: String) -> Bool {
        hiddenApps.contains { $0.bundleID == id }
    }

    /// Shows a hidden app in the mixer again, at 100% and unmuted.
    package func showApp(_ id: String) {
        guard hiddenApps.contains(where: { $0.bundleID == id }) else { return }
        hiddenApps = hiddenApps.showing(id)
        hiddenAppsDidChange()
    }

    /// The icon for a hidden app's row in Settings: the running app's, else the installed app's.
    package func icon(forHiddenApp id: String) -> NSImage? {
        allApps.first { $0.id == id }?.icon ?? cachedInstalledApp(id)?.icon
    }

    private func hiddenAppsDidChange() {
        apps = HiddenAppsPlan.visibleApps(allApps, hidden: hiddenApps.ids)
        // A hidden app plays at 100% on every device, so no device keeps a level for it.
        deviceLevelBook = deviceLevelBook.normalized(excluding: hiddenApps.ids)
        settingsDidChange()
    }

    /// Resets the current levels and clears every output device's saved levels.
    package func resetAllLevels() {
        settings = [:]
        deviceLevelBook.reset()
        engineErrors = [:]
        meterOnlyErrorIDs = []
        settingsDidChange()
    }

    // MARK: Popover lifecycle

    package func popoverDidAppear() {
        guard !isPopoverVisible else { return }
        refreshPermission()
        rebuildStrips()  // fresh order while still "closed"
        isPopoverVisible = true
        reconcile()
        rebuildStrips()  // pick up meter-engine failures; order is already frozen
        if preferences.appearance.showLevelMeters { startMeterPolling() }
    }

    package func popoverDidDisappear() {
        guard isPopoverVisible else { return }
        isPopoverVisible = false
        stopMeterPolling()
        clearMeterLevels()
        reconcile()
        rebuildStrips()
    }

    package func refreshPermission() {
        permissionDidChange(permissionSource.currentStatus())
    }

    // MARK: Persistence

    package func flushPendingSave() {
        saver.flush()
    }

    private func persistNow() {
        let preferences = preferences
        let apps = settings
        let hiddenApps = hiddenApps
        let presets = presetLibrary.presets
        let deviceLevels = deviceLevelBook
        let ducking = duckingSettings
        persister.update { document in
            document.preferences = preferences
            document.apps = apps
            document.hiddenApps = hiddenApps.isEmpty ? nil : hiddenApps
            document.presets = presets.isEmpty ? nil : presets
            document.deviceLevels = deviceLevels.isEmpty ? nil : deviceLevels.sets
            document.ducking = ducking.isDefault ? nil : ducking
        }
    }

    package func shutdown() {
        flushPendingSave()
        stopMeterPolling()
        if let wakeObserver { wakeNotifications.removeObserver(wakeObserver) }
        wakeObserver = nil
        cancelHealthCheck()
        stallRetryTask?.cancel()
        stallRetryTask = nil
        cancelDuckingWake()
        tearDownAllEngines()
    }

    // MARK: Test hooks

    var engineCount: Int { engines.count }

    func engineMode(for id: String) -> EngineMode? { engines[id]?.mode }

    // MARK: Source callbacks

    private func appsDidChange(_ newApps: [AudioApp]) {
        allApps = newApps
        apps = HiddenAppsPlan.visibleApps(newApps, hidden: hiddenApps.ids)
        updateCallActivity()
        reconcile()
        rebuildStrips()
    }

    private func outputDidChange(_ device: OutputDevice?) {
        let previous = outputDevice
        outputDevice = device
        // Before any engine is rebuilt, so the rebuilt engines start at the new device's levels.
        let switchedLevels = switchDeviceLevels(to: device)
        if let device, let previous, previous.id != device.id {
            if OutputDevice.isSameDevice(previous, device) {
                // The same device under a new object ID (it was re-enumerated, as can happen
                // across sleep). The aggregates name it by UID, so keep every engine and only
                // rebuild the ones whose IO stopped or that didn't reattach to the new ID.
                scheduleHealthCheck()
            } else {
                if switchedLevels { prepareEnginesForSwitchedLevels() }
                rebuildEngines(onOutputDevice: device)
            }
        }
        if switchedLevels { saver.schedule() }
        clearStallRetries()  // a device that wasn't ready may be now
        reconcile()
        rebuildStrips()
    }

    private func permissionDidChange(_ status: AudioCapturePermissionStatus) {
        guard status != permission else { return }
        permission = status
        updateCallActivity()
        reconcile()
        rebuildStrips()
    }

    // MARK: Core logic

    /// Hidden apps always play at 100%, so nothing may write a level for one.
    private func commit(_ setting: AppVolumeSetting, for id: String) {
        guard !isHidden(id) else { return }
        settings[id] = setting.isDefault ? nil : setting
        engineErrors[id] = nil
        settingsDidChange()
    }

    func settingsDidChange() {
        storeCurrentDeviceLevels()
        saver.schedule()
        reconcile()
        rebuildStrips()
    }
}

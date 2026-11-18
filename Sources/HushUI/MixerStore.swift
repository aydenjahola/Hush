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
    package internal(set) var outputDevice: OutputDevice?
    package internal(set) var isPopoverVisible = false

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

    var apps: [AudioApp] = []
    var settings: [String: AppVolumeSetting]
    var engineErrors: [String: String] = [:]
    /// Apps whose current error came from a meter-only engine, so turning meters off can clear it.
    @ObservationIgnored var meterOnlyErrorIDs: Set<String> = []

    @ObservationIgnored let processSource: any AudioProcessSource
    @ObservationIgnored private let outputSource: any OutputDeviceSource
    @ObservationIgnored let engineFactory: any AudioEngineFactory
    @ObservationIgnored private let permissionSource: any AudioCapturePermissionSource
    @ObservationIgnored private let persister: any SettingsPersisting
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored let installedApp: @MainActor (String) -> InstalledAppInfo?
    @ObservationIgnored var installedAppCache: [String: InstalledAppInfo?] = [:]
    @ObservationIgnored var engines: [String: any AudioEngineHandle] = [:]
    @ObservationIgnored var order: [String] = []
    @ObservationIgnored private let saver: DebouncedSaver
    @ObservationIgnored var meterTask: Task<Void, Never>?
    @ObservationIgnored let meterBank = MeterBank()
    /// Last value pushed to `processSource.setPolling`.
    @ObservationIgnored var currentPolling: ProcessPolling = .off
    /// The first-launch permission request, if one was made (exposed for tests).
    @ObservationIgnored private(set) var permissionRequest: Task<Void, Never>?
    @ObservationIgnored let logger = Logger(subsystem: HushIdentity.bundleID, category: "engine")

    package init(
        processSource: any AudioProcessSource,
        outputSource: any OutputDeviceSource,
        engineFactory: any AudioEngineFactory,
        permissionSource: any AudioCapturePermissionSource,
        persister: any SettingsPersisting,
        saveDelay: Duration = .milliseconds(500),
        now: @escaping () -> Date = Date.init,
        installedApp: @escaping @MainActor (String) -> InstalledAppInfo? = InstalledAppInfo.lookUp(bundleID:)
    ) {
        self.processSource = processSource
        self.outputSource = outputSource
        self.engineFactory = engineFactory
        self.permissionSource = permissionSource
        self.persister = persister
        self.saver = DebouncedSaver(delay: saveDelay)
        self.now = now
        self.installedApp = installedApp
        let document = persister.load()
        self.preferences = document.preferences
        self.settings = document.apps
        saver.perform = { [weak self] in self?.persistNow() }
    }

    package func start() {
        permission = permissionSource.currentStatus()
        outputSource.start { [weak self] device in self?.outputDidChange(device) }
        processSource.start { [weak self] apps in self?.appsDidChange(apps) }
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
        guard controlsEnabled else { return }
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

    package func resetAllLevels() {
        settings = [:]
        engineErrors = [:]
        meterOnlyErrorIDs = []
        settingsDidChange()
    }

    // MARK: Popover lifecycle

    package func popoverDidAppear() {
        guard !isPopoverVisible else { return }
        refreshPermission()
        rebuildStrips()          // fresh order while still "closed"
        isPopoverVisible = true
        reconcile()
        rebuildStrips()          // pick up meter-engine failures; order is already frozen
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
        persister.update { document in
            document.preferences = preferences
            document.apps = apps
        }
    }

    package func shutdown() {
        flushPendingSave()
        stopMeterPolling()
        tearDownAllEngines()
    }

    // MARK: Test hooks

    var engineCount: Int { engines.count }

    func engineMode(for id: String) -> EngineMode? { engines[id]?.mode }

    // MARK: Source callbacks

    private func appsDidChange(_ newApps: [AudioApp]) {
        apps = newApps
        reconcile()
        rebuildStrips()
    }

    private func outputDidChange(_ device: OutputDevice?) {
        let previous = outputDevice
        outputDevice = device
        if let device, let previous, previous.id != device.id {
            rebuildEngines(onOutputDevice: device)
        }
        reconcile()
        rebuildStrips()
    }

    private func permissionDidChange(_ status: AudioCapturePermissionStatus) {
        guard status != permission else { return }
        permission = status
        reconcile()
        rebuildStrips()
    }

    // MARK: Core logic

    private func commit(_ setting: AppVolumeSetting, for id: String) {
        settings[id] = setting.isDefault ? nil : setting
        engineErrors[id] = nil
        settingsDidChange()
    }

    private func settingsDidChange() {
        saver.schedule()
        reconcile()
        rebuildStrips()
    }
}

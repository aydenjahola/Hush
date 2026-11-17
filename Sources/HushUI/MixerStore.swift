import AppKit
import CoreAudio
import Foundation
import HushAudio
import HushCore
import Observation
import os

@MainActor
@Observable
public final class MixerStore {
    public struct Strip: Identifiable, Equatable {
        public let id: String
        public var displayName: String
        public var icon: NSImage?
        public var isPlaying: Bool
        /// False for saved apps that aren't running (only shown with "show inactive apps").
        public var isRunning: Bool
        public var setting: AppVolumeSetting
        /// Tooltip text for the warning badge when the engine failed.
        public var engineError: String?
    }

    // MARK: Published state

    public private(set) var strips: [Strip] = []
    public private(set) var meterLevels: [String: Float] = [:]
    public private(set) var preferences: Preferences
    public private(set) var permission: AudioCapturePermissionStatus = .undetermined
    public private(set) var outputDevice: OutputDevice?
    public private(set) var isPopoverVisible = false

    public var controlsEnabled: Bool { permission == .authorized }
    public var playingCount: Int { apps.filter(\.isPlaying).count }
    public var maxPercent: Int { preferences.maxBoostPercent.rawValue }
    public var isAnyAppAttenuated: Bool {
        apps.contains { app in
            guard let setting = settings[app.id] else { return false }
            return setting.isMuted || setting.percent < 100
        }
    }

    // MARK: Private state

    private var apps: [AudioApp] = []
    private var settings: [String: AppVolumeSetting]
    private var engineErrors: [String: String] = [:]

    @ObservationIgnored private let processSource: any AudioProcessSource
    @ObservationIgnored private let outputSource: any OutputDeviceSource
    @ObservationIgnored private let engineFactory: any AudioEngineFactory
    @ObservationIgnored private let permissionSource: any AudioCapturePermissionSource
    @ObservationIgnored private let persister: any SettingsPersisting
    @ObservationIgnored private let saveDelay: Duration
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let installedApp: @MainActor (String) -> InstalledAppInfo?
    @ObservationIgnored private var installedAppCache: [String: InstalledAppInfo?] = [:]
    @ObservationIgnored private var engines: [String: any AudioEngineHandle] = [:]
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var hasPendingSave = false
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.hush-mixer.Hush", category: "engine")

    public init(
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
        self.saveDelay = saveDelay
        self.now = now
        self.installedApp = installedApp
        let document = persister.load()
        self.preferences = document.preferences
        self.settings = document.apps
    }

    public func start() {
        permission = permissionSource.currentStatus()
        outputSource.start { [weak self] device in self?.outputDidChange(device) }
        processSource.start { [weak self] apps in self?.appsDidChange(apps) }
        if permission == .undetermined {
            Task { [weak self] in
                guard let self else { return }
                let status = await self.permissionSource.requestAccess()
                self.permissionDidChange(status)
            }
        }
    }

    // MARK: User actions

    public func setPercent(_ percent: Int, for id: String) {
        guard controlsEnabled else { return }
        var setting = settings[id] ?? AppVolumeSetting()
        setting.setPercent(percent, maxPercent: maxPercent)
        setting.lastAdjusted = now()
        commit(setting, for: id)
    }

    public func resetVolume(for id: String) {
        setPercent(100, for: id)
    }

    public func toggleMute(for id: String) {
        guard controlsEnabled else { return }
        var setting = settings[id] ?? AppVolumeSetting()
        setting.isMuted.toggle()
        setting.lastAdjusted = now()
        commit(setting, for: id)
    }

    public func setMaxBoost(_ limit: BoostLimit) {
        preferences.maxBoostPercent = limit
        settings = SettingsDocument(preferences: preferences, apps: settings).normalized().apps
        settingsDidChange()
    }

    public func setShowInactiveApps(_ show: Bool) {
        preferences.showInactiveApps = show
        settingsDidChange()
    }

    public func resetAllLevels() {
        settings = [:]
        engineErrors = [:]
        settingsDidChange()
    }

    // MARK: Popover lifecycle

    public func popoverDidAppear() {
        guard !isPopoverVisible else { return }
        refreshPermission()
        rebuildStrips()          // fresh order while still "closed"
        isPopoverVisible = true
        reconcile()
        rebuildStrips()          // pick up meter-engine failures; order is already frozen
        startMeterPolling()
    }

    public func popoverDidDisappear() {
        guard isPopoverVisible else { return }
        isPopoverVisible = false
        stopMeterPolling()
        meterLevels = [:]
        reconcile()
        rebuildStrips()
    }

    public func refreshPermission() {
        permissionDidChange(permissionSource.currentStatus())
    }

    // MARK: Persistence

    public func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        guard hasPendingSave else { return }
        hasPendingSave = false
        persister.save(SettingsDocument(preferences: preferences, apps: settings))
    }

    public func shutdown() {
        flushPendingSave()
        stopMeterPolling()
        tearDownAllEngines()
    }

    // MARK: Test hooks

    var engineCount: Int { engines.count }

    func engineMode(for id: String) -> EngineMode? { engines[id]?.mode }

    // MARK: Meters

    func tickMeters(elapsed: Double) {
        var levels: [String: Float] = [:]
        for (id, engine) in engines {
            levels[id] = MeterBallistics.next(
                displayed: meterLevels[id] ?? 0,
                peak: engine.currentPeak(),
                elapsed: elapsed)
        }
        meterLevels = levels
    }

    private func startMeterPolling() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard !Task.isCancelled, let self else { break }
                let current = clock.now
                let elapsed = (current - last) / .seconds(1)
                last = current
                self.tickMeters(elapsed: elapsed)
            }
        }
    }

    private func stopMeterPolling() {
        meterTask?.cancel()
        meterTask = nil
    }

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
            engineErrors = [:]
            for (id, engine) in engines {
                do {
                    try engine.rebuild(outputDeviceID: device.id)
                } catch {
                    tearDownEngine(id)
                    recordFailure(error, for: id, mode: engine.mode)
                }
            }
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
        scheduleSave()
        reconcile()
        rebuildStrips()
    }

    /// Makes the set of running engines match the reconcile rule in spec section 4.3.
    private func reconcile() {
        guard controlsEnabled, let device = outputDevice else {
            tearDownAllEngines()
            return
        }

        var playing: [String: AudioApp] = [:]
        for app in apps where app.isPlaying { playing[app.id] = app }

        for id in engines.keys where playing[id] == nil { tearDownEngine(id) }
        for id in engineErrors.keys where playing[id] == nil { engineErrors[id] = nil }

        for (id, app) in playing {
            let setting = settings[id] ?? AppVolumeSetting()
            let desired: EngineMode? = setting.needsEngine ? .control : (isPopoverVisible ? .meterOnly : nil)

            if let engine = engines[id] {
                if engine.mode == desired && engine.processObjectIDs == app.processObjectIDs {
                    if desired == .control { engine.setGain(setting.effectiveGain) }
                    continue
                }
                tearDownEngine(id)
            }

            guard let mode = desired, engineErrors[id] == nil else { continue }
            do {
                engines[id] = try engineFactory.makeEngine(
                    appID: id,
                    processObjectIDs: app.processObjectIDs,
                    mode: mode,
                    initialGain: mode == .control ? setting.effectiveGain : 1,
                    outputDeviceID: device.id)
            } catch {
                recordFailure(error, for: id, mode: mode)
            }
        }
    }

    private func tearDownEngine(_ id: String) {
        engines.removeValue(forKey: id)?.stop()
        meterLevels[id] = nil
    }

    private func tearDownAllEngines() {
        for id in engines.keys { tearDownEngine(id) }
    }

    private func recordFailure(_ error: any Error, for id: String, mode: EngineMode) {
        let summary = switch mode {
        case .control: "Hush couldn't control this app's audio, so it's playing normally."
        case .meterOnly: "Hush couldn't read this app's level."
        }
        engineErrors[id] = "\(summary) (\(error))"
        logger.error("Engine for \(id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
    }

    private func scheduleSave() {
        hasPendingSave = true
        saveTask?.cancel()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flushPendingSave()
        }
    }

    // MARK: Strips

    private func rebuildStrips() {
        var byID: [String: Strip] = [:]
        // Idle apps are listed only when they're real (Dock) apps or the user has a level saved for them;
        // otherwise every daemon with a Core Audio process object would get a strip.
        for app in apps where app.isPlaying
            || (preferences.showInactiveApps && (app.isRegularApp || settings[app.id] != nil)) {
            byID[app.id] = Strip(
                id: app.id,
                displayName: app.displayName,
                icon: app.icon,
                isPlaying: app.isPlaying,
                isRunning: true,
                setting: settings[app.id] ?? AppVolumeSetting(),
                engineError: engineErrors[app.id])
        }
        if preferences.showInactiveApps {
            for (id, setting) in settings where byID[id] == nil {
                let info = cachedInstalledApp(id)
                byID[id] = Strip(
                    id: id, displayName: info?.displayName ?? id, icon: info?.icon, isPlaying: false,
                    isRunning: false, setting: setting, engineError: nil)
            }
        }

        if isPopoverVisible {
            let survivors = order.filter { byID[$0] != nil }
            let known = Set(survivors)
            let newcomers = sortedIDs(byID.values.filter { !known.contains($0.id) })
            order = survivors + newcomers
        } else {
            order = sortedIDs(Array(byID.values))
        }
        strips = order.compactMap { byID[$0] }
    }

    private func cachedInstalledApp(_ id: String) -> InstalledAppInfo? {
        if let cached = installedAppCache[id] { return cached }
        let info = installedApp(id)
        installedAppCache[id] = info
        return info
    }

    private func sortedIDs(_ candidates: [Strip]) -> [String] {
        StripOrdering.sorted(candidates.map { strip in
            StripSortKey(
                id: strip.id,
                displayName: strip.displayName,
                isPlaying: strip.isPlaying,
                lastAdjusted: settings[strip.id]?.lastAdjusted)
        }).map(\.id)
    }
}

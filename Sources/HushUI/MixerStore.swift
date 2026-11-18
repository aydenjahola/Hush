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
    /// Ballistics state for the meters. Not observed: views read their `StripMeter` instead.
    @ObservationIgnored public private(set) var meterLevels: [String: Float] = [:]
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
    @ObservationIgnored let meterBank = MeterBank()
    /// Last value pushed to `processSource.setPolling`.
    @ObservationIgnored private var currentPolling: ProcessPolling = .off
    /// The first-launch permission request, if one was made (exposed for tests).
    @ObservationIgnored private(set) var permissionRequest: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: HushIdentity.bundleID, category: "engine")

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
            permissionRequest = Task { [weak self] in
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

    /// Settable views of the preferences, so Settings can bind to them with `@Bindable`.
    public var maxBoost: BoostLimit {
        get { preferences.maxBoostPercent }
        set { setMaxBoost(newValue) }
    }

    public var showInactiveApps: Bool {
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
        if new.showLevelMeters != old.showLevelMeters, isPopoverVisible {
            if new.showLevelMeters {
                startMeterPolling()
            } else {
                stopMeterPolling()
                meterLevels = [:]
                meterBank.publish(meterLevels)
            }
        }
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
        if preferences.appearance.showLevelMeters { startMeterPolling() }
    }

    public func popoverDidDisappear() {
        guard isPopoverVisible else { return }
        isPopoverVisible = false
        stopMeterPolling()
        meterLevels = [:]
        meterBank.publish(meterLevels)
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
        let preferences = preferences
        let apps = settings
        persister.update { document in
            document.preferences = preferences
            document.apps = apps
        }
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

    /// The live meter for a strip. Only `LevelMeter` should read its value.
    func meter(for id: String) -> StripMeter { meterBank.meter(for: id) }

    /// Advances the ballistics and publishes to the per-strip meters, which notify their views
    /// only when the displayed height changes by a step.
    func tickMeters(elapsed: Double) {
        guard !engines.isEmpty || !meterLevels.isEmpty || !meterBank.isSilent else { return }
        for id in meterLevels.keys where engines[id] == nil { meterLevels[id] = nil }
        for (id, engine) in engines {
            meterLevels[id] = MeterBallistics.next(
                displayed: meterLevels[id] ?? 0,
                peak: engine.currentPeak(),
                elapsed: elapsed)
        }
        meterBank.publish(meterLevels)
    }

    /// About 30 Hz. Engines report the peak since the last read, so no peak is missed between ticks.
    static let meterInterval: Duration = .milliseconds(33)
    /// About 10%: lets the system coalesce meter wakeups; the ballistics use the real elapsed time.
    static let meterTolerance: Duration = meterInterval / 10

    private func startMeterPolling() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.meterInterval, tolerance: Self.meterTolerance)
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

    /// Makes the set of running engines match the reconcile rule in spec section 4.3:
    /// muted, lowered or boosted playing apps get a `.control` engine (gain 0 when muted), other
    /// playing apps a `.meterOnly` engine while the popover is open, the rest none.
    private func reconcile() {
        defer { updatePolling() }
        guard controlsEnabled, let device = outputDevice else {
            tearDownAllEngines()
            return
        }

        var present: [String: AudioApp] = [:]
        for app in apps { present[app.id] = app }

        // An app that's gone takes its engine and its error with it; the setting stays for its return.
        for id in engines.keys where present[id] == nil { tearDownEngine(id) }
        for id in engineErrors.keys where present[id] == nil { engineErrors[id] = nil }

        for (id, app) in present {
            let setting = settings[id] ?? AppVolumeSetting()
            // Muting is a control engine at gain 0: a `.muted` tap that nothing reads doesn't
            // silence the app (confirmed live), so idle apps get no engine at all.
            let desired: EngineMode? = if setting.needsEngine && app.isPlaying {
                .control
            } else if app.isPlaying && isPopoverVisible && preferences.appearance.showLevelMeters {
                .meterOnly
            } else {
                nil
            }

            let existing = engines[id]
            if let existing, existing.mode == desired, existing.processObjectIDs == app.processObjectIDs {
                if desired == .control { existing.setGain(setting.effectiveGain) }
                continue
            }

            guard let mode = desired, engineErrors[id] == nil else {
                tearDownEngine(id)
                continue
            }
            // Change the running engine in place when possible: destroying a muted tap lets the
            // app through at full level until a replacement's IO runs, and a new aggregate starts
            // with a gap. A helper spawning (process list) or the user adjusting a metered app
            // (mode) therefore keeps the same tap, aggregate and IOProc.
            if let existing, applyInPlace(to: existing, id: id, processObjectIDs: app.processObjectIDs, mode: mode, setting: setting) {
                continue
            }
            // Fallback, make before break: the old engine keeps the app muted or processed until
            // the new one exists.
            do {
                let replacement = try engineFactory.makeEngine(
                    appID: id,
                    processObjectIDs: app.processObjectIDs,
                    mode: mode,
                    initialGain: mode == .control ? setting.effectiveGain : 1,
                    outputDeviceID: device.id)
                engines[id] = replacement
                existing?.stop()
                if existing != nil { meterLevels[id] = nil }
            } catch {
                tearDownEngine(id)  // never keep an engine in the wrong mode
                recordFailure(error, for: id, mode: mode)
            }
        }
    }

    /// Updates the process list first, then the mode. Returns false (after logging) if the engine
    /// refused either change, so the caller replaces it.
    private func applyInPlace(
        to engine: any AudioEngineHandle,
        id: String,
        processObjectIDs: [AudioObjectID],
        mode: EngineMode,
        setting: AppVolumeSetting
    ) -> Bool {
        do {
            if engine.processObjectIDs != processObjectIDs {
                try engine.updateProcesses(processObjectIDs)
            }
            if engine.mode != mode {
                try engine.switchMode(to: mode, gain: setting.effectiveGain)
            } else if mode == .control {
                engine.setGain(setting.effectiveGain)
            }
            return true
        } catch {
            logger.error("In-place change for \(id, privacy: .public) failed, rebuilding: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Polls only what decisions depend on:
    /// - every process while the popover is open (live strips);
    /// - otherwise the objects of every present muted, lowered or boosted app, playing or not. Its
    ///   control engine starts only once Hush sees it play and stops once Hush sees it stop. The HAL
    ///   often skips both notifications (a browser pausing and resuming), so the poll catches a
    ///   missed start (audio unprocessed) and a missed stop (an IOProc running on silence keeps the
    ///   output device and Bluetooth awake).
    /// - nothing otherwise; the HAL listeners still give best-effort updates.
    private func updatePolling() {
        let polling: ProcessPolling
        if isPopoverVisible {
            polling = .all
        } else {
            var objects: Set<AudioObjectID> = []
            if controlsEnabled {
                for app in apps where settings[app.id]?.needsEngine ?? false {
                    objects.formUnion(app.processObjectIDs)
                }
            }
            polling = objects.isEmpty ? .off : .objects(objects)
        }
        guard polling != currentPolling else { return }
        currentPolling = polling
        processSource.setPolling(polling)
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

        // Alphabetical order doesn't jump around, so only activity order is frozen while open.
        if isPopoverVisible && preferences.appearance.sortMode == .activity {
            let survivors = order.filter { byID[$0] != nil }
            let known = Set(survivors)
            let newcomers = sortedIDs(byID.values.filter { !known.contains($0.id) })
            order = survivors + newcomers
        } else {
            order = sortedIDs(Array(byID.values))
        }
        strips = order.compactMap { byID[$0] }
        meterBank.retain(only: Set(order))
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
        }, mode: preferences.appearance.sortMode).map(\.id)
    }
}

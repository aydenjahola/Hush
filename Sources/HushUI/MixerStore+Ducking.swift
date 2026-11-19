import AppKit
import HushAudio
import HushCore

/// What the popover's ducking line says: "Ducking for Zoom", or "Ducking for 2 apps".
package struct DuckingIndicator: Equatable {
    /// The names of the call apps in a call, sorted.
    package var appNames: [String]
}

/// The ducking multiplier as of one moment, taken once per reconcile so every app sees the same
/// value. Pure; see `DuckingPlan`.
struct DuckingState {
    /// The fade's multiplier (1 at full level).
    var fade: Float
    /// The fade is lowered or still moving. While false nothing is ducked and nothing changes
    /// from a Hush without ducking.
    var isActive: Bool
    var settings: DuckingSettings

    /// Whether `id` needs ducking right now: it's duckable and the fade is active.
    func isDucked(_ id: String) -> Bool {
        isActive && DuckingPlan.isDuckable(id, settings: settings)
    }

    /// The gain `id` plays at: its own level times its multiplier.
    func gain(for id: String, setting: AppVolumeSetting) -> Float {
        let multiplier = isActive ? DuckingPlan.multiplier(for: id, fade: fade, settings: settings) : 1
        return DuckingPlan.gain(own: setting, multiplier: multiplier)
    }

    /// The apps among `apps` that are ducked, playing or not (for polling).
    func duckableApps(in apps: [AudioApp]) -> Set<String> {
        DuckingPlan.duckedApps(playing: apps.map(\.id), settings: settings, isActive: isActive)
    }
}

/// "Lower other apps during calls": while a call app captures from a microphone, every other
/// playing app is lowered, then restored when the call ends.
///
/// Detection: the process source tracks input only while ducking is on (`EnginePlan.inputPolling`).
/// Each change of the app list feeds the call apps that capture into `callActivity`, which
/// debounces them. A wake-up task (`duckingTask`) runs when a debounce deadline passes and steps
/// the fade every `duckingStep` while it moves; each step reconciles, which sets every ducked
/// engine's gain to its own level times the fade's multiplier.
///
/// Ducking is never saved: `settings`, presets, device levels and the strips keep the user's own
/// levels throughout, and only `duckingSettings` is written to the settings file.
package extension MixerStore {
    var duckingEnabled: Bool {
        get { duckingSettings.isEnabled }
        set { setDuckingEnabled(newValue) }
    }

    /// "Lower other apps to N%".
    var duckingPercent: Int {
        get { duckingSettings.percent }
        set { updateDucking { $0.setPercent(newValue) } }
    }

    func setDuckingEnabled(_ on: Bool) {
        updateDucking { $0.isEnabled = on }
    }

    func addCallApp(_ app: DuckingApp) {
        updateDucking { $0.addCallApp(app) }
    }

    func removeCallApp(_ id: String) {
        updateDucking { $0.removeCallApp(id) }
    }

    func restoreDefaultCallApps() {
        updateDucking { $0.restoreDefaultCallApps() }
    }

    func addDuckingException(_ app: DuckingApp) {
        updateDucking { $0.addException(app) }
    }

    func removeDuckingException(_ id: String) {
        updateDucking { $0.removeException(id) }
    }

    /// The popover's ducking line, while a call app is in a call and ducking is on.
    var duckingIndicator: DuckingIndicator? {
        guard !activeCallApps.isEmpty else { return nil }
        let names = activeCallApps.map(duckingDisplayName(for:))
        return DuckingIndicator(appNames: names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    /// The running apps the Settings "Add" menus offer: apps Core Audio knows about (hidden ones
    /// included) that are regular apps or playing, minus Hush and the apps in `excluding`,
    /// sorted by name.
    func duckingCandidates(excluding: Set<String>) -> [DuckingApp] {
        allApps
            .filter {
                ($0.isRegularApp || $0.isPlaying) && $0.id != HushIdentity.bundleID && !excluding.contains($0.id)
            }
            .map { DuckingApp(bundleID: $0.id, displayName: $0.displayName) }
            .normalizedDuckingList()
    }

    /// The icon for a row in the ducking lists: the running app's, else the installed app's.
    func icon(forDuckingApp id: String) -> NSImage? {
        allApps.first { $0.id == id }?.icon ?? cachedInstalledApp(id)?.icon
    }
}

extension MixerStore {
    /// Applies a ducking settings change, saves it and re-evaluates ducking. Turning ducking off
    /// forgets the call state, so turning it on again waits for the start delay as usual.
    func updateDucking(_ change: (inout DuckingSettings) -> Void) {
        var updated = duckingSettings
        change(&updated)
        guard updated != duckingSettings else { return }
        if !updated.isEnabled { callActivity.reset() }
        duckingSettings = updated
        updateCallActivity()
        settingsDidChange()
    }

    /// Feeds the listed call apps that capture input into `callActivity` and refreshes ducking.
    /// Uses every app, hidden ones included: a hidden call app still counts. Without control
    /// permission nothing can be ducked, so nothing counts.
    func updateCallActivity() {
        let now = now()
        let capturing =
            controlsEnabled
            ? DuckingPlan.capturingCallApps(allApps.filter(\.isCapturingInput).map(\.id), settings: duckingSettings)
            : []
        callActivity.update(capturing: capturing, at: now)
        refreshDucking(at: now)
    }

    /// Reads which call apps are in a call at `now`, retargets the fade and schedules the next
    /// wake-up. Doesn't reconcile; callers do.
    func refreshDucking(at now: Date) {
        let active = duckingSettings.isEnabled ? callActivity.activeApps(at: now) : []
        if active != activeCallApps { activeCallApps = active }
        duckingFade.retarget(active.isEmpty ? 1 : duckingSettings.duckedGain, at: now)
        scheduleDuckingWake(at: now)
    }

    func duckingState() -> DuckingState {
        let now = now()
        return DuckingState(
            fade: duckingFade.multiplier(at: now), isActive: !duckingFade.isIdle(at: now), settings: duckingSettings)
    }

    /// A wake-up: a debounce deadline passed or the fade takes a step. Reconciling applies the new
    /// multiplier, starts engines for newly ducked apps and, once the fade back up has finished,
    /// drops the engines only ducking needed.
    func duckingTick() {
        duckingTask = nil
        pendingDuckingWake = nil
        let errors = engineErrors
        refreshDucking(at: now())
        reconcile()
        if engineErrors != errors { rebuildStrips() }
    }

    func cancelDuckingWake() {
        duckingTask?.cancel()
        duckingTask = nil
        pendingDuckingWake = nil
    }

    /// Every `duckingStep` while the fade moves, else at the next debounce deadline, else never.
    private func scheduleDuckingWake(at now: Date) {
        cancelDuckingWake()
        let delay: Duration
        if !duckingFade.isSettled(at: now) {
            delay = duckingStep
        } else if let next = callActivity.nextChange(after: now) {
            delay = .seconds(max(next.timeIntervalSince(now), 0))
        } else {
            return
        }
        pendingDuckingWake = delay
        let sleep = duckingSleep
        duckingTask = Task { [weak self] in
            try? await sleep(delay)
            guard !Task.isCancelled else { return }
            self?.duckingTick()
        }
    }

    /// The call app list's name for `id` (so FaceTime's call agent reads as FaceTime), else the
    /// running app's name, else the ID.
    private func duckingDisplayName(for id: String) -> String {
        duckingSettings.callApps.first { $0.bundleID == id }?.displayName
            ?? allApps.first { $0.id == id }?.displayName
            ?? id
    }
}

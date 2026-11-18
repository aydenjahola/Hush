import HushAudio
import HushCore

/// Builds the strip list and its order from the store's state. Pure apart from the injected
/// installed-app lookup, which is only consulted for saved apps that aren't running.
struct StripListBuilder {
    var apps: [AudioApp]
    var settings: [String: AppVolumeSetting]
    var preferences: Preferences
    var engineErrors: [String: String]
    var isPopoverVisible: Bool
    /// The previous order, kept (minus departed apps) while the popover is open in activity order.
    var previousOrder: [String]

    func build(installedApp: (String) -> InstalledAppInfo?) -> (strips: [MixerStore.Strip], order: [String]) {
        var byID: [String: MixerStore.Strip] = [:]
        // Idle apps are listed only when they're real (Dock) apps or the user has a level saved for them;
        // otherwise every daemon with a Core Audio process object would get a strip.
        for app in apps where app.isPlaying
            || (preferences.showInactiveApps && (app.isRegularApp || settings[app.id] != nil)) {
            byID[app.id] = MixerStore.Strip(
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
                let info = installedApp(id)
                byID[id] = MixerStore.Strip(
                    id: id, displayName: info?.displayName ?? id, icon: info?.icon, isPlaying: false,
                    isRunning: false, setting: setting, engineError: nil)
            }
        }

        // Alphabetical order doesn't jump around, so only activity order is frozen while open.
        let order: [String]
        if isPopoverVisible && preferences.appearance.sortMode == .activity {
            let survivors = previousOrder.filter { byID[$0] != nil }
            let known = Set(survivors)
            let newcomers = sortedIDs(byID.values.filter { !known.contains($0.id) })
            order = survivors + newcomers
        } else {
            order = sortedIDs(Array(byID.values))
        }
        return (order.compactMap { byID[$0] }, order)
    }

    private func sortedIDs(_ candidates: [MixerStore.Strip]) -> [String] {
        StripOrdering.sorted(candidates.map { strip in
            StripSortKey(
                id: strip.id,
                displayName: strip.displayName,
                isPlaying: strip.isPlaying,
                lastAdjusted: settings[strip.id]?.lastAdjusted)
        }, mode: preferences.appearance.sortMode).map(\.id)
    }
}

import HushAudio
import HushCore

/// The pure rules behind hiding apps from the mixer. A hidden app is never adjusted: the store
/// filters it out of the app list before strips, engines, polling, the playing count and the bulk
/// mute actions see it, and hiding it drops any saved level so it plays at 100%.
enum HiddenAppsPlan {
    /// The apps the mixer works with: every app the source reports except the hidden ones.
    static func visibleApps(_ apps: [AudioApp], hidden: Set<String>) -> [AudioApp] {
        hidden.isEmpty ? apps : apps.filter { !hidden.contains($0.id) }
    }

    /// Saved levels without the hidden apps' entries.
    static func visibleSettings(
        _ settings: [String: AppVolumeSetting], hidden: Set<String>
    ) -> [String: AppVolumeSetting] {
        hidden.isEmpty ? settings : settings.filter { !hidden.contains($0.key) }
    }

    /// Hiding `app`: it joins the hidden list and loses its saved level, so it goes back to 100%
    /// and unmuted.
    static func hide(
        _ app: HiddenApp,
        hidden: [HiddenApp],
        settings: [String: AppVolumeSetting]
    ) -> (hidden: [HiddenApp], settings: [String: AppVolumeSetting]) {
        var settings = settings
        settings[app.bundleID] = nil
        return (hidden.hiding(app), settings)
    }
}

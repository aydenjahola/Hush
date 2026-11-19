/// The pure rules for which apps ducking listens to and which it lowers.
package enum DuckingPlan {
    /// Whether ducking may lower `id`: every app except the call apps, the exceptions and Hush.
    /// A call app that isn't in a call is still a call app, so a browser playing music while
    /// another app is in a call keeps its level (the browser may be the one in a Meet call).
    package static func isDuckable(_ id: String, settings: DuckingSettings) -> Bool {
        settings.isEnabled && id != HushIdentity.bundleID && !settings.isCallApp(id) && !settings.isException(id)
    }

    /// The playing apps that ducking lowers while a call is on.
    package static func duckedApps(playing: some Sequence<String>, settings: DuckingSettings) -> Set<String> {
        Set(playing.filter { isDuckable($0, settings: settings) })
    }

    /// The listed call apps among the apps capturing input. Hush never counts, even if listed.
    package static func capturingCallApps(_ capturing: some Sequence<String>, settings: DuckingSettings) -> Set<String>
    {
        guard settings.isEnabled else { return [] }
        return Set(capturing.filter { $0 != HushIdentity.bundleID && settings.isCallApp($0) })
    }

    /// The gain a ducked app plays at: its own gain (0 when muted) times the ducking multiplier.
    package static func gain(own setting: AppVolumeSetting, multiplier: Float) -> Float {
        setting.effectiveGain * multiplier
    }
}

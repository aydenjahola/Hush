/// The pure rules for which apps ducking listens to and which it lowers.
///
/// Whether ducking is on is carried by the fade, not by these rules: turning it off mid-call
/// starts a fade back up, and the multiplier keeps applying to duckable apps until that finishes,
/// so nothing jumps.
package enum DuckingPlan {
    /// Whether ducking may lower `id`: every app except the call apps, the exceptions and Hush.
    /// A call app that isn't in a call is still a call app, so a browser playing music while
    /// another app is in a call keeps its level (the browser may be the one in a Meet call).
    package static func isDuckable(_ id: String, settings: DuckingSettings) -> Bool {
        id != HushIdentity.bundleID && !settings.isCallApp(id) && !settings.isException(id)
    }

    /// The multiplier for `id` when the fade is at `fade`: the fade for duckable apps, else 1.
    package static func multiplier(for id: String, fade: Float, settings: DuckingSettings) -> Float {
        isDuckable(id, settings: settings) ? fade : 1
    }

    /// The playing apps that are lowered (or fading) while `isActive`: the fade is ducked or
    /// still moving. None while it's idle at full level.
    package static func duckedApps(
        playing: some Sequence<String>, settings: DuckingSettings, isActive: Bool
    ) -> Set<String> {
        guard isActive else { return [] }
        return Set(playing.filter { isDuckable($0, settings: settings) })
    }

    /// The listed call apps among the apps capturing input. Hush never counts, even if listed,
    /// and nothing counts while ducking is off.
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

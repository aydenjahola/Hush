import Observation

/// A place in Settings that AppKit code, such as the quick menu, can ask the window to show.
package enum SettingsDestination: Equatable, Sendable {
    /// The Presets section.
    case presets
    /// The Presets section with the "Save Current Levels as Preset" sheet open.
    case savePreset
}

/// Carries a request from the quick menu to the Settings window, which may not be open yet.
/// The caller sets `pending` and opens Settings; `SettingsView` shows the destination when it
/// appears (or at once if it's already open) and clears the request.
@MainActor
@Observable
package final class SettingsNavigator {
    package var pending: SettingsDestination?

    package init() {}

    package func request(_ destination: SettingsDestination) {
        pending = destination
    }

    /// Returns the pending request and clears it.
    package func take() -> SettingsDestination? {
        defer { pending = nil }
        return pending
    }
}

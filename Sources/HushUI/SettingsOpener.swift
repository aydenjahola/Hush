import AppKit
import SwiftUI

/// Opens the Settings window from AppKit code, such as the quick menu.
///
/// `openSettings` (and `SettingsLink`) only exist inside SwiftUI views, so a tiny
/// `SettingsOpenerBridge` view, kept alive in the menu bar, hands its environment's action to this
/// object. Until the bridge has appeared, `open()` falls back to the `showSettingsWindow:` action.
@MainActor
package final class SettingsOpener {
    private(set) var action: OpenSettingsAction?

    package init() {}

    package func capture(_ action: OpenSettingsAction) {
        self.action = action
    }

    /// Brings Hush to the front, then opens (or focuses) the Settings window.
    package func open() {
        NSApp.activate()
        if let action {
            action()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}

/// An invisible view that captures `openSettings` for a `SettingsOpener`.
package struct SettingsOpenerBridge: View {
    let opener: SettingsOpener
    @Environment(\.openSettings) private var openSettings

    package init(opener: SettingsOpener) {
        self.opener = opener
    }

    package var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear { opener.capture(openSettings) }
    }
}

import SwiftUI

/// The popover's line while ducking is active: "Ducking for Zoom", or "Ducking for 2 apps".
struct DuckingIndicatorLine: View {
    /// A speaker with a minus: other apps are being turned down. Also the quick menu item's image.
    static let symbolName = "speaker.minus.fill"

    let indicator: DuckingIndicator

    var body: some View {
        Label {
            Text(Self.text(for: indicator))
        } icon: {
            Image(systemName: Self.symbolName)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }

    static func text(for indicator: DuckingIndicator) -> LocalizedStringResource {
        if indicator.appNames.count == 1, let name = indicator.appNames.first {
            L10n.duckingFor(name)
        } else {
            L10n.duckingForApps(indicator.appNames.count)
        }
    }
}

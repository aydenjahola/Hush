import HushCore
import SwiftUI

/// Settings → Levels: the apps hidden from the mixer, each with a Show button that brings it back.
struct HiddenAppsList: View {
    let store: MixerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.hiddenApps)
            if store.hiddenApps.isEmpty {
                Text(L10n.noHiddenApps)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.hiddenApps) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: store.icon(forHiddenApp: app.id) ?? FallbackAppIcon.image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                        Text(verbatim: app.displayName)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(Text(verbatim: app.displayName))
                        Spacer(minLength: 8)
                        Button(L10n.show) { store.showApp(app.id) }
                            .accessibilityLabel(Text(L10n.showApp(app.displayName)))
                    }
                }
            }
        }
    }
}

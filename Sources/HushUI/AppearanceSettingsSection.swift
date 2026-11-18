import HushCore
import SwiftUI

/// Settings → Appearance: layout, meters, size, percentages, sort, accent, menu bar icon, with a
/// live preview of the chosen layout.
struct AppearanceSettingsSection: View {
    @Bindable var store: MixerStore

    static let recordingIndicatorNote: LocalizedStringKey = "The purple dot in the menu bar is macOS's audio-recording indicator. It appears while Hush is adjusting an app's volume and, with meters on, while the mixer is open."

    var body: some View {
        Section("Appearance") {
            AppearancePreview(appearance: MixerAppearance(store.preferences.appearance), maxPercent: store.maxPercent)
                .padding(.vertical, 4)

            Picker("Layout", selection: $store.layout) {
                Text("Channel strips").tag(MixerLayout.channelStrips)
                Text("Classic rows").tag(MixerLayout.classicRows)
                Text("Tiles").tag(MixerLayout.tiles)
            }
            .pickerStyle(.segmented)

            Picker("Size", selection: $store.density) {
                Text("Comfortable").tag(MixerDensity.comfortable)
                Text("Compact").tag(MixerDensity.compact)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Show level meters", isOn: $store.showLevelMeters)
                Text(Self.recordingIndicatorNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Show percentages", isOn: $store.showPercentages)

            Picker("Sort apps", selection: $store.sortMode) {
                Text("Playing & recently adjusted first").tag(StripSortMode.activity)
                Text("Alphabetical").tag(StripSortMode.alphabetical)
            }

            Picker("Accent colour", selection: $store.accent) {
                Text("Amber").tag(AccentChoice.amber)
                Text("System accent").tag(AccentChoice.system)
            }

            Picker("Menu bar icon", selection: $store.menuBarIconStyle) {
                Label {
                    Text("Speaker")
                } icon: {
                    Image(nsImage: MenuBarIcon.image(style: .speaker, attenuated: false, badged: false))
                }
                .tag(MenuBarIconStyle.speaker)
                Label {
                    Text("Fader glyph")
                } icon: {
                    Image(nsImage: MenuBarIcon.image(style: .fader, attenuated: false, badged: false))
                }
                .tag(MenuBarIconStyle.fader)
            }
        }
    }
}

import HushCore
import SwiftUI

/// Settings → Appearance: layout, meters, size, percentages, sort, accent, menu bar icon, with a
/// live preview of the chosen layout.
struct AppearanceSettingsSection: View {
    @Bindable var store: MixerStore

    var body: some View {
        Section(L10n.appearance) {
            AppearancePreview(appearance: MixerAppearance(store.preferences.appearance), maxPercent: store.maxPercent)
                .padding(.vertical, 4)

            Picker(L10n.layout, selection: $store.layout) {
                Text(L10n.channelStrips).tag(MixerLayout.channelStrips)
                Text(L10n.classicRows).tag(MixerLayout.classicRows)
                Text(L10n.tiles).tag(MixerLayout.tiles)
            }
            .pickerStyle(.segmented)

            Picker(L10n.size, selection: $store.density) {
                Text(L10n.comfortable).tag(MixerDensity.comfortable)
                Text(L10n.compact).tag(MixerDensity.compact)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Toggle(L10n.showLevelMeters, isOn: $store.showLevelMeters)
                Text(L10n.recordingIndicatorNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(L10n.showPercentages, isOn: $store.showPercentages)

            Picker(L10n.sortApps, selection: $store.sortMode) {
                Text(L10n.sortActivity).tag(StripSortMode.activity)
                Text(L10n.sortAlphabetical).tag(StripSortMode.alphabetical)
            }

            Picker(L10n.accentColour, selection: $store.accent) {
                Text(L10n.amber).tag(AccentChoice.amber)
                Text(L10n.systemAccent).tag(AccentChoice.system)
            }

            Picker(L10n.menuBarIcon, selection: $store.menuBarIconStyle) {
                Label {
                    Text(L10n.speaker)
                } icon: {
                    Image(nsImage: MenuBarIcon.image(style: .speaker, attenuated: false, badged: false))
                }
                .tag(MenuBarIconStyle.speaker)
                Label {
                    Text(L10n.faderGlyph)
                } icon: {
                    Image(nsImage: MenuBarIcon.image(style: .fader, attenuated: false, badged: false))
                }
                .tag(MenuBarIconStyle.fader)
            }
        }
    }
}

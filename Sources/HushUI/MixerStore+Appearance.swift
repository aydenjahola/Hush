import HushCore

/// Settable views of Settings → Appearance, so SettingsView can bind to them with `@Bindable`.
/// Every write goes through `updateAppearance`, which persists it and updates meters and order.
public extension MixerStore {
    var layout: MixerLayout {
        get { preferences.appearance.layout }
        set { updateAppearance { $0.layout = newValue } }
    }

    /// Off: no meter-only taps are created and meters are hidden.
    var showLevelMeters: Bool {
        get { preferences.appearance.showLevelMeters }
        set { updateAppearance { $0.showLevelMeters = newValue } }
    }

    var density: MixerDensity {
        get { preferences.appearance.density }
        set { updateAppearance { $0.density = newValue } }
    }

    var showPercentages: Bool {
        get { preferences.appearance.showPercentages }
        set { updateAppearance { $0.showPercentages = newValue } }
    }

    var sortMode: StripSortMode {
        get { preferences.appearance.sortMode }
        set { updateAppearance { $0.sortMode = newValue } }
    }

    var accent: AccentChoice {
        get { preferences.appearance.accent }
        set { updateAppearance { $0.accent = newValue } }
    }

    var menuBarIconStyle: MenuBarIconStyle {
        get { preferences.appearance.menuBarIcon }
        set { updateAppearance { $0.menuBarIcon = newValue } }
    }
}

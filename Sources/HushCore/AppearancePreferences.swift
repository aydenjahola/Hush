/// How the popover lays out the apps.
package enum MixerLayout: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Vertical faders side by side (the original layout).
    case channelStrips = "strips"
    /// One dense row per app with a horizontal slider, like Control Center.
    case classicRows = "rows"
    /// One row per app that is itself the slider.
    case tiles

    package var id: String { rawValue }
}

package enum MixerDensity: String, Codable, CaseIterable, Sendable, Identifiable {
    case comfortable
    case compact

    package var id: String { rawValue }
}

package enum StripSortMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Playing apps first, then most recently adjusted, then by name (`StripOrdering`).
    case activity
    case alphabetical

    package var id: String { rawValue }
}

package enum AccentChoice: String, Codable, CaseIterable, Sendable, Identifiable {
    case amber
    case system

    package var id: String { rawValue }
}

package enum MenuBarIconStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case speaker
    case fader

    package var id: String { rawValue }
}

/// Settings → Appearance. Each key is optional in settings.json: a missing or unrecognised value
/// (for example one written by a newer Hush) falls back to its default instead of failing the file.
package struct AppearancePreferences: Codable, Equatable, Sendable {
    package var layout: MixerLayout
    package var showLevelMeters: Bool
    package var density: MixerDensity
    package var showPercentages: Bool
    package var sortMode: StripSortMode
    package var accent: AccentChoice
    package var menuBarIcon: MenuBarIconStyle

    package init(
        layout: MixerLayout = .channelStrips,
        showLevelMeters: Bool = true,
        density: MixerDensity = .comfortable,
        showPercentages: Bool = true,
        sortMode: StripSortMode = .activity,
        accent: AccentChoice = .amber,
        menuBarIcon: MenuBarIconStyle = .speaker
    ) {
        self.layout = layout
        self.showLevelMeters = showLevelMeters
        self.density = density
        self.showPercentages = showPercentages
        self.sortMode = sortMode
        self.accent = accent
        self.menuBarIcon = menuBarIcon
    }

    private enum CodingKeys: String, CodingKey {
        case layout, showLevelMeters, density, showPercentages, sortMode, accent, menuBarIcon
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        let defaults = AppearancePreferences()
        layout = value(.layout, defaults.layout)
        showLevelMeters = value(.showLevelMeters, defaults.showLevelMeters)
        density = value(.density, defaults.density)
        showPercentages = value(.showPercentages, defaults.showPercentages)
        sortMode = value(.sortMode, defaults.sortMode)
        accent = value(.accent, defaults.accent)
        menuBarIcon = value(.menuBarIcon, defaults.menuBarIcon)
    }
}

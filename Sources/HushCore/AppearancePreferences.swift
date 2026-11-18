/// How the popover lays out the apps.
public enum MixerLayout: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Vertical faders side by side (the original layout).
    case channelStrips = "strips"
    /// One dense row per app with a horizontal slider, like Control Center.
    case classicRows = "rows"
    /// One row per app that is itself the slider.
    case tiles

    public var id: String { rawValue }
}

public enum MixerDensity: String, Codable, CaseIterable, Sendable, Identifiable {
    case comfortable
    case compact

    public var id: String { rawValue }
}

public enum StripSortMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Playing apps first, then most recently adjusted, then by name (`StripOrdering`).
    case activity
    case alphabetical

    public var id: String { rawValue }
}

public enum AccentChoice: String, Codable, CaseIterable, Sendable, Identifiable {
    case amber
    case system

    public var id: String { rawValue }
}

public enum MenuBarIconStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case speaker
    case fader

    public var id: String { rawValue }
}

/// Settings → Appearance. Each key is optional in settings.json: a missing or unrecognised value
/// (for example one written by a newer Hush) falls back to its default instead of failing the file.
public struct AppearancePreferences: Codable, Equatable, Sendable {
    public var layout: MixerLayout
    public var showLevelMeters: Bool
    public var density: MixerDensity
    public var showPercentages: Bool
    public var sortMode: StripSortMode
    public var accent: AccentChoice
    public var menuBarIcon: MenuBarIconStyle

    public init(
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

    public init(from decoder: any Decoder) throws {
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

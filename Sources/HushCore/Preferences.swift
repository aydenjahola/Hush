/// The allowed maximum boost values shown in Settings.
package enum BoostLimit: Int, Codable, CaseIterable, Sendable, Identifiable {
    case percent100 = 100
    case percent150 = 150
    case percent200 = 200

    package var id: Int { rawValue }
}

package struct Preferences: Codable, Equatable, Sendable {
    package var maxBoostPercent: BoostLimit
    package var showInactiveApps: Bool
    /// Settings → Appearance. Every field is optional on disk, so older files still decode.
    package var appearance: AppearancePreferences
    /// Settings → Levels → "Remember levels for each output device". Off by default, and optional
    /// on disk (added after version 1 shipped). The sets themselves are `SettingsDocument.deviceLevels`.
    package var rememberLevelsPerDevice: Bool

    package init(
        maxBoostPercent: BoostLimit = .percent200,
        showInactiveApps: Bool = false,
        appearance: AppearancePreferences = AppearancePreferences(),
        rememberLevelsPerDevice: Bool = false
    ) {
        self.maxBoostPercent = maxBoostPercent
        self.showInactiveApps = showInactiveApps
        self.appearance = appearance
        self.rememberLevelsPerDevice = rememberLevelsPerDevice
    }

    private enum CodingKeys: String, CodingKey {
        case maxBoostPercent, showInactiveApps, appearance, rememberLevelsPerDevice
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxBoostPercent = try container.decodeIfPresent(BoostLimit.self, forKey: .maxBoostPercent) ?? .percent200
        showInactiveApps = try container.decodeIfPresent(Bool.self, forKey: .showInactiveApps) ?? false
        // A malformed appearance section falls back to defaults rather than discarding the file.
        appearance =
            (try? container.decodeIfPresent(AppearancePreferences.self, forKey: .appearance))
            ?? AppearancePreferences()
        rememberLevelsPerDevice =
            (try? container.decodeIfPresent(Bool.self, forKey: .rememberLevelsPerDevice)) ?? false
    }
}

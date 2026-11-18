import Foundation

/// The persisted root stored at ~/Library/Application Support/Hush/settings.json.
package struct SettingsDocument: Codable, Equatable, Sendable {
    package static let currentVersion = 1

    package enum DecodingFailure: Error, Equatable {
        case unsupportedVersion(Int)
    }

    package var version: Int
    package var preferences: Preferences
    /// Keyed by bundle ID, or executable name when there is no bundle ID.
    package var apps: [String: AppVolumeSetting]
    /// Added after version 1 shipped; optional on disk, so it didn't need a version bump.
    package var updates: UpdateSettings
    /// The shortcut that opens the mixer from anywhere; nil (the default) means none. Added after
    /// version 1 shipped and optional on disk. It lives at the top level rather than in
    /// `preferences` because Settings owns it, not the mixer, so the mixer's saves leave it alone.
    package var globalShortcut: GlobalShortcut?
    /// Apps hidden from the mixer. Added after version 1 shipped; nil (absent on disk) means none.
    package var hiddenApps: [HiddenApp]?
    /// Saved volume presets, in order; nil (the default) when there are none, so files without
    /// presets don't change. Added after version 1 shipped and optional on disk. The mixer owns
    /// it and writes it in the same save as `apps`.
    package var presets: [Preset]?

    package init(
        preferences: Preferences = Preferences(),
        apps: [String: AppVolumeSetting] = [:],
        updates: UpdateSettings = UpdateSettings(),
        globalShortcut: GlobalShortcut? = nil,
        hiddenApps: [HiddenApp]? = nil,
        presets: [Preset]? = nil
    ) {
        self.version = Self.currentVersion
        self.preferences = preferences
        self.apps = apps
        self.updates = updates
        self.globalShortcut = globalShortcut
        self.hiddenApps = hiddenApps
        self.presets = presets
    }

    private enum CodingKeys: String, CodingKey {
        case version, preferences, apps, updates, globalShortcut, hiddenApps, presets
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        preferences = try container.decode(Preferences.self, forKey: .preferences)
        apps = try container.decode([String: AppVolumeSetting].self, forKey: .apps)
        updates = try container.decodeIfPresent(UpdateSettings.self, forKey: .updates) ?? UpdateSettings()
        // A malformed shortcut is dropped (no shortcut) rather than discarding the whole file.
        globalShortcut = (try? container.decodeIfPresent(GlobalShortcut.self, forKey: .globalShortcut)) ?? nil
        // A malformed list is dropped rather than discarding the whole file.
        hiddenApps = (try? container.decodeIfPresent([HiddenApp].self, forKey: .hiddenApps)) ?? nil
        // A malformed preset is dropped rather than discarding the other presets or the whole
        // file, and a presets value that isn't a list is dropped too.
        presets = (try? container.decodeIfPresent(LossyList<Preset>.self, forKey: .presets))?.elements
    }

    /// Decodes a JSON array, skipping elements that don't decode.
    private struct LossyList<Element: Decodable>: Decodable {
        var elements: [Element] = []

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            while !container.isAtEnd {
                if let element = try? container.decode(Element.self) {
                    elements.append(element)
                } else if (try? container.decode(Skipped.self)) == nil {
                    break  // Couldn't step past the bad element; keep what decoded so far.
                }
            }
        }

        /// Decodes any value without reading it, to step past an element that didn't decode.
        private struct Skipped: Decodable {
            init(from decoder: any Decoder) throws {}
        }
    }

    private struct VersionProbe: Decodable {
        let version: Int
    }

    package static func decode(from data: Data) throws -> SettingsDocument {
        let probe = try JSONDecoder().decode(VersionProbe.self, from: data)
        guard probe.version == currentVersion else {
            throw DecodingFailure.unsupportedVersion(probe.version)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SettingsDocument.self, from: data).normalized()
    }

    package func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(normalized())
    }

    /// Clamps every app to the current maximum boost and drops default entries. Hidden apps are
    /// listed once each, sorted, and never keep a level (they always play at 100%); an empty
    /// hidden list is stored as absent. Presets follow `PresetLibrary`'s rules (and become nil
    /// when none are left); their levels keep their saved percent and are clamped only when applied.
    package func normalized() -> SettingsDocument {
        let maxPercent = preferences.maxBoostPercent.rawValue
        let hidden = hiddenApps?.normalized() ?? []
        let hiddenIDs = hidden.ids
        var copy = self
        copy.apps = apps.compactMapValues { setting in
            var clamped = setting
            clamped.setPercent(setting.percent, maxPercent: maxPercent)
            return clamped.isDefault ? nil : clamped
        }
        .filter { !hiddenIDs.contains($0.key) }
        copy.hiddenApps = hidden.isEmpty ? nil : hidden
        copy.presets = presets.flatMap { presets in
            let kept = PresetLibrary(presets: presets).presets
            return kept.isEmpty ? nil : kept
        }
        return copy
    }
}

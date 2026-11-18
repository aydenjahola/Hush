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
    /// Each output device's saved levels, keyed by device UID, for "Remember levels for each
    /// output device". nil (the default) when there are none. Added after version 1 shipped and
    /// optional on disk. The mixer owns it and writes it in the same save as `apps`; the sets stay
    /// when the feature is turned off, so turning it on again brings them back.
    package var deviceLevels: [String: DeviceLevels]?

    package init(
        preferences: Preferences = Preferences(),
        apps: [String: AppVolumeSetting] = [:],
        updates: UpdateSettings = UpdateSettings(),
        globalShortcut: GlobalShortcut? = nil,
        hiddenApps: [HiddenApp]? = nil,
        presets: [Preset]? = nil,
        deviceLevels: [String: DeviceLevels]? = nil
    ) {
        self.version = Self.currentVersion
        self.preferences = preferences
        self.apps = apps
        self.updates = updates
        self.globalShortcut = globalShortcut
        self.hiddenApps = hiddenApps
        self.presets = presets
        self.deviceLevels = deviceLevels
    }

    private enum CodingKeys: String, CodingKey {
        case version, preferences, apps, updates, globalShortcut, hiddenApps, presets, deviceLevels
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
        // A malformed device's set is dropped rather than discarding the other devices or the
        // whole file, and a value that isn't an object is dropped too.
        deviceLevels =
            (try? container.decodeIfPresent(LossyDictionary<DeviceLevels>.self, forKey: .deviceLevels))?.elements
    }

    /// Decodes a JSON object with string keys, skipping values that don't decode.
    private struct LossyDictionary<Value: Decodable>: Decodable {
        var elements: [String: Value] = [:]

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: AnyKey.self)
            for key in container.allKeys {
                if let value = try? container.decode(Value.self, forKey: key) {
                    elements[key.stringValue] = value
                }
            }
        }

        private struct AnyKey: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }
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
    /// Device sets lose default entries and hidden apps like `apps`, but keep their saved percent
    /// (clamped only when loaded, like presets); a device whose set is empty stays (it means every
    /// app at 100% there), and no sets at all become nil.
    package func normalized() -> SettingsDocument {
        let maxPercent = preferences.maxBoostPercent.rawValue
        let hidden = hiddenApps?.normalized() ?? []
        let hiddenIDs = hidden.ids
        var copy = self
        copy.apps = DeviceLevelBook.cleaned(apps, maxPercent: maxPercent, excluding: hiddenIDs)
        copy.hiddenApps = hidden.isEmpty ? nil : hidden
        copy.presets = presets.flatMap { presets in
            let kept = PresetLibrary(presets: presets).presets
            return kept.isEmpty ? nil : kept
        }
        copy.deviceLevels = deviceLevels.flatMap { sets in
            let book = DeviceLevelBook(sets: sets).normalized(excluding: hiddenIDs)
            return book.isEmpty ? nil : book.sets
        }
        return copy
    }
}

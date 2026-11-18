import Foundation

/// The persisted root stored at ~/Library/Application Support/Hush/settings.json.
public struct SettingsDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public enum DecodingFailure: Error, Equatable {
        case unsupportedVersion(Int)
    }

    public var version: Int
    public var preferences: Preferences
    /// Keyed by bundle ID, or executable name when there is no bundle ID.
    public var apps: [String: AppVolumeSetting]
    /// Added after version 1 shipped; optional on disk, so it didn't need a version bump.
    public var updates: UpdateSettings

    public init(
        preferences: Preferences = Preferences(),
        apps: [String: AppVolumeSetting] = [:],
        updates: UpdateSettings = UpdateSettings()
    ) {
        self.version = Self.currentVersion
        self.preferences = preferences
        self.apps = apps
        self.updates = updates
    }

    private enum CodingKeys: String, CodingKey {
        case version, preferences, apps, updates
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        preferences = try container.decode(Preferences.self, forKey: .preferences)
        apps = try container.decode([String: AppVolumeSetting].self, forKey: .apps)
        updates = try container.decodeIfPresent(UpdateSettings.self, forKey: .updates) ?? UpdateSettings()
    }

    private struct VersionProbe: Decodable {
        let version: Int
    }

    public static func decode(from data: Data) throws -> SettingsDocument {
        let probe = try JSONDecoder().decode(VersionProbe.self, from: data)
        guard probe.version == currentVersion else {
            throw DecodingFailure.unsupportedVersion(probe.version)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SettingsDocument.self, from: data).normalized()
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(normalized())
    }

    /// Clamps every app to the current maximum boost and drops default entries.
    public func normalized() -> SettingsDocument {
        let maxPercent = preferences.maxBoostPercent.rawValue
        var copy = self
        copy.apps = apps.compactMapValues { setting in
            var clamped = setting
            clamped.setPercent(setting.percent, maxPercent: maxPercent)
            return clamped.isDefault ? nil : clamped
        }
        return copy
    }
}

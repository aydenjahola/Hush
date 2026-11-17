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

    public init(preferences: Preferences = Preferences(), apps: [String: AppVolumeSetting] = [:]) {
        self.version = Self.currentVersion
        self.preferences = preferences
        self.apps = apps
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

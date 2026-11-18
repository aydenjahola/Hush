import Foundation

/// Persisted update-notifier state, stored under "updates" in settings.json. Every field is
/// optional on disk, so settings files written before the notifier existed still decode.
public struct UpdateSettings: Codable, Equatable, Sendable {
    public var automaticUpdateChecks: Bool
    /// The version the user chose to skip; that version and older ones stay silent.
    public var skippedVersion: String?
    /// "Later": the banner, badge and notification stay hidden until this time.
    public var snoozedUntil: Date?
    /// When a check last completed successfully.
    public var lastUpdateCheck: Date?
    /// The last version a macOS notification was posted for, so each version notifies once.
    public var notifiedVersion: String?

    public init(
        automaticUpdateChecks: Bool = true,
        skippedVersion: String? = nil,
        snoozedUntil: Date? = nil,
        lastUpdateCheck: Date? = nil,
        notifiedVersion: String? = nil
    ) {
        self.automaticUpdateChecks = automaticUpdateChecks
        self.skippedVersion = skippedVersion
        self.snoozedUntil = snoozedUntil
        self.lastUpdateCheck = lastUpdateCheck
        self.notifiedVersion = notifiedVersion
    }

    private enum CodingKeys: String, CodingKey {
        case automaticUpdateChecks, skippedVersion, snoozedUntil, lastUpdateCheck, notifiedVersion
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        automaticUpdateChecks = try container.decodeIfPresent(Bool.self, forKey: .automaticUpdateChecks) ?? true
        skippedVersion = try container.decodeIfPresent(String.self, forKey: .skippedVersion)
        snoozedUntil = try container.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        lastUpdateCheck = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
        notifiedVersion = try container.decodeIfPresent(String.self, forKey: .notifiedVersion)
    }
}

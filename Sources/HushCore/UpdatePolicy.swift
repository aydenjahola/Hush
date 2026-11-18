import Foundation

/// The subset of GitHub's "get the latest release" response that Hush reads.
public struct GitHubRelease: Decodable, Equatable, Sendable {
    public struct Asset: Decodable, Equatable, Sendable {
        public var name: String
        public var browserDownloadURL: URL

        public init(name: String, browserDownloadURL: URL) {
            self.name = name
            self.browserDownloadURL = browserDownloadURL
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    public var tagName: String
    public var htmlURL: URL
    public var draft: Bool
    public var prerelease: Bool
    public var assets: [Asset]

    public init(tagName: String, htmlURL: URL, draft: Bool, prerelease: Bool, assets: [Asset]) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.draft = draft
        self.prerelease = prerelease
        self.assets = assets
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease, assets
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
    }

    public static func decode(from data: Data) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}

/// A release newer than the running copy of Hush.
public struct AvailableUpdate: Equatable, Sendable {
    public var version: SemanticVersion
    /// The versioned DMG, or the release page when that asset is missing.
    public var downloadURL: URL
    public var releasePageURL: URL

    public init(version: SemanticVersion, downloadURL: URL, releasePageURL: URL) {
        self.version = version
        self.downloadURL = downloadURL
        self.releasePageURL = releasePageURL
    }
}

/// Pure decisions for the update notifier.
public enum UpdatePolicy {
    public static let releasesPageURL = URL(string: "https://github.com/aydenjahola/Hush/releases/latest")!

    /// Drafts, prereleases (by flag or by a "-beta"-style tag) and unparseable tags carry no update.
    public static func isIgnored(_ release: GitHubRelease) -> Bool {
        guard !release.draft, !release.prerelease, let version = SemanticVersion(release.tagName) else { return true }
        return version.isPrerelease
    }

    /// The update `release` offers over `current`, or nil if it's ignored or not newer.
    public static func availableUpdate(in release: GitHubRelease, current: SemanticVersion) -> AvailableUpdate? {
        guard !isIgnored(release), let version = SemanticVersion(release.tagName), version > current else { return nil }
        let page = isTrusted(release.htmlURL) ? release.htmlURL : releasesPageURL
        let dmgName = "Hush-\(version).dmg"
        let asset = release.assets.first { $0.name == dmgName }?.browserDownloadURL
        let download = asset.flatMap { isTrusted($0) ? $0 : nil } ?? page
        return AvailableUpdate(version: version, downloadURL: download, releasePageURL: page)
    }

    /// True while the user has asked not to hear about `update`: snoozed, or this version (or a newer one) skipped.
    public static func isSuppressed(_ update: AvailableUpdate, settings: UpdateSettings, now: Date) -> Bool {
        if let snoozedUntil = settings.snoozedUntil, now < snoozedUntil { return true }
        if let skipped = settings.skippedVersion.flatMap(SemanticVersion.init), update.version <= skipped { return true }
        return false
    }

    /// Hush only ever opens release links on github.com over HTTPS.
    static func isTrusted(_ url: URL) -> Bool {
        url.scheme == "https" && url.host() == "github.com"
    }
}

/// When the next automatic check is due: shortly after launch, then once a day.
public struct UpdateSchedule: Equatable, Sendable {
    public var launchDelay: TimeInterval
    public var interval: TimeInterval

    public init(launchDelay: TimeInterval = 30, interval: TimeInterval = 24 * 60 * 60) {
        self.launchDelay = launchDelay
        self.interval = interval
    }

    /// `lastAttempt` is this session's last check attempt (successful or not), nil before the first.
    public func nextCheck(lastAttempt: Date?, launchedAt: Date, now: Date) -> Date {
        guard let lastAttempt else { return launchedAt.addingTimeInterval(launchDelay) }
        // If the wall clock moved backwards, don't wait longer than one interval from now.
        return min(lastAttempt.addingTimeInterval(interval), now.addingTimeInterval(interval))
    }
}

import Foundation

/// The subset of GitHub's "get the latest release" response that Hush reads.
package struct GitHubRelease: Decodable, Equatable, Sendable {
    package struct Asset: Decodable, Equatable, Sendable {
        package var name: String
        package var browserDownloadURL: URL

        package init(name: String, browserDownloadURL: URL) {
            self.name = name
            self.browserDownloadURL = browserDownloadURL
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    package var tagName: String
    package var htmlURL: URL
    package var draft: Bool
    package var prerelease: Bool
    package var assets: [Asset]

    package init(tagName: String, htmlURL: URL, draft: Bool, prerelease: Bool, assets: [Asset]) {
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

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
    }

    package static func decode(from data: Data) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}

/// A release newer than the running copy of Hush.
package struct AvailableUpdate: Equatable, Sendable {
    package var version: SemanticVersion
    /// The versioned DMG, or the release page when that asset is missing.
    package var downloadURL: URL
    package var releasePageURL: URL

    package init(version: SemanticVersion, downloadURL: URL, releasePageURL: URL) {
        self.version = version
        self.downloadURL = downloadURL
        self.releasePageURL = releasePageURL
    }
}

/// Pure decisions for the update notifier.
package enum UpdatePolicy {
    package static let releasesPageURL = URL(string: "https://github.com/aydenjahola/Hush/releases/latest")!

    /// Drafts, prereleases (by flag or by a "-beta"-style tag) and unparseable tags carry no update.
    package static func isIgnored(_ release: GitHubRelease) -> Bool {
        guard !release.draft, !release.prerelease, let version = SemanticVersion(release.tagName) else { return true }
        return version.isPrerelease
    }

    /// The update `release` offers over `current`, or nil if it's ignored or not newer.
    package static func availableUpdate(in release: GitHubRelease, current: SemanticVersion) -> AvailableUpdate? {
        guard !isIgnored(release), let version = SemanticVersion(release.tagName), version > current else { return nil }
        let page = isTrusted(release.htmlURL) ? release.htmlURL : releasesPageURL
        let dmgName = "Hush-\(version).dmg"
        let asset = release.assets.first { $0.name == dmgName }?.browserDownloadURL
        let download = asset.flatMap { isTrustedDownload($0) ? $0 : nil } ?? page
        return AvailableUpdate(version: version, downloadURL: download, releasePageURL: page)
    }

    /// True while the user has asked not to hear about `update`: snoozed, or this version (or a newer one) skipped.
    package static func isSuppressed(_ update: AvailableUpdate, settings: UpdateSettings, now: Date) -> Bool {
        if let snoozedUntil = settings.snoozedUntil, now < snoozedUntil { return true }
        if let skipped = settings.skippedVersion.flatMap(SemanticVersion.init), update.version <= skipped { return true }
        return false
    }

    private static let releasesPathPrefix = "/aydenjahola/hush/releases/"

    /// Hush only opens its own release pages: `https://github.com/aydenjahola/Hush/releases/…`, with
    /// no port, no user or password, and no ".." segments (checked on the standardized, decoded path).
    package static func isTrusted(_ url: URL) -> Bool {
        trustedPath(of: url) != nil
    }

    /// A release asset: a trusted URL under `/releases/download/`.
    package static func isTrustedDownload(_ url: URL) -> Bool {
        trustedPath(of: url)?.hasPrefix(releasesPathPrefix + "download/") == true
    }

    /// The lowercased, standardized, percent-decoded path of a trusted URL, or nil.
    private static func trustedPath(of url: URL) -> String? {
        guard url.scheme?.lowercased() == "https",
              url.host(percentEncoded: false)?.lowercased() == "github.com",
              url.port == nil,
              url.user(percentEncoded: false) == nil,
              url.password(percentEncoded: false) == nil
        else { return nil }
        let raw = url.path(percentEncoded: false)
        let standardized = url.standardized.path(percentEncoded: false)
        // Reject any dot segment, raw or percent-encoded, rather than trusting what it resolves to.
        let segments = raw.split(separator: "/", omittingEmptySubsequences: false)
        guard raw == standardized, !segments.contains(".."), !segments.contains(".") else { return nil }
        let path = standardized.lowercased()
        return path.hasPrefix(releasesPathPrefix) ? path : nil
    }
}

/// When the next automatic check is due: shortly after launch, then once a day. After a failure it
/// retries sooner (1 h, then 4 h, then daily) and returns to daily after a success.
package struct UpdateSchedule: Equatable, Sendable {
    /// Consecutive attempts are never closer than this, whatever else the schedule says.
    package static let minimumGap: TimeInterval = 60

    package var launchDelay: TimeInterval
    package var interval: TimeInterval
    /// Delay after the 1st, 2nd, … consecutive failure; the last value repeats.
    package var retryIntervals: [TimeInterval]

    package init(
        launchDelay: TimeInterval = 30,
        interval: TimeInterval = 24 * 60 * 60,
        retryIntervals: [TimeInterval] = [60 * 60, 4 * 60 * 60, 24 * 60 * 60]
    ) {
        self.launchDelay = launchDelay
        self.interval = interval
        self.retryIntervals = retryIntervals
    }

    /// - Parameters:
    ///   - lastAttempt: this session's last check attempt (successful or not), nil before the first.
    ///   - consecutiveFailures: failed attempts since the last success.
    ///   - notBefore: a server-requested earliest retry (Retry-After / rate-limit reset).
    package func nextCheck(
        lastAttempt: Date?,
        consecutiveFailures: Int = 0,
        notBefore: Date? = nil,
        launchedAt: Date,
        now: Date
    ) -> Date {
        guard let lastAttempt else { return launchedAt.addingTimeInterval(launchDelay) }
        let delay = consecutiveFailures > 0 && !retryIntervals.isEmpty
            ? retryIntervals[min(consecutiveFailures, retryIntervals.count) - 1]
            : interval
        var due = lastAttempt.addingTimeInterval(delay)
        if let notBefore { due = max(due, notBefore) }
        due = max(due, lastAttempt.addingTimeInterval(Self.minimumGap))
        // If the wall clock moved backwards (or a server asked for too long), don't wait longer
        // than one interval from now.
        return min(due, now.addingTimeInterval(max(interval, Self.minimumGap)))
    }
}

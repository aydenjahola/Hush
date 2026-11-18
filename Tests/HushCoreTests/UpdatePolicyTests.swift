import Foundation
import Testing
@testable import HushCore

@Suite struct UpdatePolicyTests {
    private let current = SemanticVersion("0.1.0")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func release(
        tag: String = "v0.2.0",
        draft: Bool = false,
        prerelease: Bool = false,
        assets: [GitHubRelease.Asset]? = nil
    ) -> GitHubRelease {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return GitHubRelease(
            tagName: tag,
            htmlURL: URL(string: "https://github.com/aydenjahola/Hush/releases/tag/\(tag)")!,
            draft: draft,
            prerelease: prerelease,
            assets: assets ?? [
                .init(name: "Hush.dmg", browserDownloadURL: URL(string: "https://github.com/aydenjahola/Hush/releases/download/\(tag)/Hush.dmg")!),
                .init(name: "Hush-\(version).dmg", browserDownloadURL: URL(string: "https://github.com/aydenjahola/Hush/releases/download/\(tag)/Hush-\(version).dmg")!),
            ])
    }

    // MARK: Decoding

    @Test func decodesGitHubReleaseJSON() throws {
        let json = """
        {
          "url": "https://api.github.com/repos/aydenjahola/Hush/releases/1",
          "html_url": "https://github.com/aydenjahola/Hush/releases/tag/v0.2.0",
          "tag_name": "v0.2.0",
          "name": "v0.2.0",
          "draft": false,
          "prerelease": false,
          "published_at": "2026-12-01T10:00:00Z",
          "assets": [
            { "name": "Hush-0.2.0.dmg", "size": 123,
              "browser_download_url": "https://github.com/aydenjahola/Hush/releases/download/v0.2.0/Hush-0.2.0.dmg" },
            { "name": "Hush-0.2.0.dmg.sha256",
              "browser_download_url": "https://github.com/aydenjahola/Hush/releases/download/v0.2.0/Hush-0.2.0.dmg.sha256" }
          ]
        }
        """
        let decoded = try GitHubRelease.decode(from: Data(json.utf8))
        #expect(decoded.tagName == "v0.2.0")
        #expect(decoded.htmlURL.absoluteString == "https://github.com/aydenjahola/Hush/releases/tag/v0.2.0")
        #expect(!decoded.draft && !decoded.prerelease)
        #expect(decoded.assets.map(\.name) == ["Hush-0.2.0.dmg", "Hush-0.2.0.dmg.sha256"])
    }

    @Test func decodingToleratesMissingFlagsAndAssets() throws {
        let json = #"{"tag_name": "v1.0.0", "html_url": "https://github.com/aydenjahola/Hush/releases/tag/v1.0.0"}"#
        let decoded = try GitHubRelease.decode(from: Data(json.utf8))
        #expect(!decoded.draft && !decoded.prerelease && decoded.assets.isEmpty)
    }

    @Test func decodingRejectsGarbage() {
        #expect(throws: (any Error).self) { try GitHubRelease.decode(from: Data(#"{"message": "API rate limit exceeded"}"#.utf8)) }
        #expect(throws: (any Error).self) { try GitHubRelease.decode(from: Data("<html>".utf8)) }
    }

    // MARK: Newer-version decision

    @Test func newerReleaseIsAnUpdateWithTheVersionedDMG() throws {
        let update = try #require(UpdatePolicy.availableUpdate(in: release(), current: current))
        #expect(update.version == SemanticVersion("0.2.0"))
        #expect(update.downloadURL.absoluteString == "https://github.com/aydenjahola/Hush/releases/download/v0.2.0/Hush-0.2.0.dmg")
        #expect(update.releasePageURL.absoluteString == "https://github.com/aydenjahola/Hush/releases/tag/v0.2.0")
    }

    @Test func sameOrOlderReleaseIsNotAnUpdate() {
        #expect(UpdatePolicy.availableUpdate(in: release(tag: "v0.1.0"), current: current) == nil)
        #expect(UpdatePolicy.availableUpdate(in: release(tag: "v0.0.9"), current: current) == nil)
    }

    @Test func comparesVersionsNumerically() {
        let installed = SemanticVersion("0.9.0")!
        #expect(UpdatePolicy.availableUpdate(in: release(tag: "v0.10.0"), current: installed) != nil)
    }

    @Test func draftsAndPrereleasesAreIgnored() {
        #expect(UpdatePolicy.availableUpdate(in: release(tag: "v9.0.0", draft: true), current: current) == nil)
        #expect(UpdatePolicy.availableUpdate(in: release(tag: "v9.0.0", prerelease: true), current: current) == nil)
        #expect(UpdatePolicy.availableUpdate(in: release(tag: "v9.0.0-beta.1"), current: current) == nil)
        #expect(UpdatePolicy.isIgnored(release(draft: true)))
        #expect(UpdatePolicy.isIgnored(release(prerelease: true)))
        #expect(!UpdatePolicy.isIgnored(release()))
    }

    @Test func unparseableTagIsIgnored() {
        #expect(UpdatePolicy.isIgnored(release(tag: "nightly")))
        #expect(UpdatePolicy.availableUpdate(in: release(tag: "nightly"), current: current) == nil)
    }

    @Test func missingVersionedAssetFallsBackToReleasePage() throws {
        let update = try #require(UpdatePolicy.availableUpdate(in: release(assets: []), current: current))
        #expect(update.downloadURL == update.releasePageURL)
    }

    @Test func untrustedURLsFallBackToTheReleasesPage() throws {
        let hostile = GitHubRelease(
            tagName: "v0.2.0",
            htmlURL: URL(string: "http://github.com/aydenjahola/Hush/releases/tag/v0.2.0")!,
            draft: false, prerelease: false,
            assets: [.init(name: "Hush-0.2.0.dmg", browserDownloadURL: URL(string: "https://evil.example/Hush-0.2.0.dmg")!)])
        let update = try #require(UpdatePolicy.availableUpdate(in: hostile, current: current))
        #expect(update.downloadURL == UpdatePolicy.releasesPageURL)
        #expect(update.releasePageURL == UpdatePolicy.releasesPageURL)
    }

    // MARK: URL allow-list

    @Test(arguments: [
        "https://github.com/aydenjahola/Hush/releases/latest",
        "https://github.com/aydenjahola/Hush/releases/tag/v0.2.0",
        "https://GitHub.com/AydenJahola/hush/releases/tag/v0.2.0",
        "https://github.com/aydenjahola/Hush/releases/download/v0.2.0/Hush-0.2.0.dmg",
    ])
    func trustsHushReleaseLinks(_ text: String) {
        #expect(UpdatePolicy.isTrusted(URL(string: text)!))
    }

    @Test(arguments: [
        "https://github.com/attacker/Hush/releases/latest",           // another repo
        "https://github.com/aydenjahola/HushEvil/releases/latest",    // look-alike repo
        "https://github.com/aydenjahola/Hush/issues/1",                // not a release
        "https://github.com:444/aydenjahola/Hush/releases/latest",    // port
        "https://evil@github.com/aydenjahola/Hush/releases/latest",   // user
        "https://a:b@github.com/aydenjahola/Hush/releases/latest",    // user and password
        "http://github.com/aydenjahola/Hush/releases/latest",         // not https
        "https://github.com.evil.example/aydenjahola/Hush/releases/latest",
        "https://github.com/aydenjahola/Hush/../evil/releases/latest", // traversal
        "https://github.com/aydenjahola/Hush/releases/../../../evil/x",
        "https://github.com/aydenjahola/Hush/releases/%2e%2e/%2e%2e/%2e%2e/evil",
        "file:///aydenjahola/Hush/releases/latest",
    ])
    func rejectsEverythingElse(_ text: String) {
        #expect(!UpdatePolicy.isTrusted(URL(string: text)!))
    }

    @Test func downloadsMustBeReleaseAssets() {
        let asset = URL(string: "https://github.com/aydenjahola/Hush/releases/download/v0.2.0/Hush-0.2.0.dmg")!
        let page = URL(string: "https://github.com/aydenjahola/Hush/releases/tag/v0.2.0")!
        #expect(UpdatePolicy.isTrustedDownload(asset))
        #expect(!UpdatePolicy.isTrustedDownload(page))
        #expect(!UpdatePolicy.isTrustedDownload(URL(string: "https://github.com/attacker/x/releases/download/v1/Hush-0.2.0.dmg")!))
    }

    @Test func assetOutsideReleaseDownloadsFallsBackToTheReleasePage() throws {
        let odd = GitHubRelease(
            tagName: "v0.2.0",
            htmlURL: URL(string: "https://github.com/aydenjahola/Hush/releases/tag/v0.2.0")!,
            draft: false, prerelease: false,
            assets: [.init(name: "Hush-0.2.0.dmg", browserDownloadURL: URL(string: "https://github.com/aydenjahola/Hush/releases/tag/Hush-0.2.0.dmg")!)])
        let update = try #require(UpdatePolicy.availableUpdate(in: odd, current: current))
        #expect(update.downloadURL == update.releasePageURL)
    }

    // MARK: Suppression

    private func update(_ version: String) -> AvailableUpdate {
        AvailableUpdate(version: SemanticVersion(version)!, downloadURL: UpdatePolicy.releasesPageURL, releasePageURL: UpdatePolicy.releasesPageURL)
    }

    @Test func nothingSuppressesByDefault() {
        #expect(!UpdatePolicy.isSuppressed(update("0.2.0"), settings: UpdateSettings(), now: now))
    }

    @Test func snoozeSuppressesUntilItEnds() {
        var settings = UpdateSettings()
        settings.snoozedUntil = now.addingTimeInterval(60)
        #expect(UpdatePolicy.isSuppressed(update("0.2.0"), settings: settings, now: now))
        #expect(!UpdatePolicy.isSuppressed(update("0.2.0"), settings: settings, now: now.addingTimeInterval(60)))
    }

    @Test func skipSuppressesThatVersionAndOlderOnly() {
        var settings = UpdateSettings()
        settings.skippedVersion = "0.2.0"
        #expect(UpdatePolicy.isSuppressed(update("0.2.0"), settings: settings, now: now))
        #expect(UpdatePolicy.isSuppressed(update("0.1.5"), settings: settings, now: now))
        #expect(!UpdatePolicy.isSuppressed(update("0.2.1"), settings: settings, now: now))
        #expect(!UpdatePolicy.isSuppressed(update("0.10.0"), settings: settings, now: now))
    }

    @Test func garbageSkippedVersionSuppressesNothing() {
        var settings = UpdateSettings()
        settings.skippedVersion = "banana"
        #expect(!UpdatePolicy.isSuppressed(update("0.2.0"), settings: settings, now: now))
    }

    // MARK: Schedule

    @Test func firstCheckIsThirtySecondsAfterLaunch() {
        let schedule = UpdateSchedule()
        #expect(schedule.nextCheck(lastAttempt: nil, launchedAt: now, now: now) == now.addingTimeInterval(30))
        // Still anchored to launch if computed a little later.
        #expect(schedule.nextCheck(lastAttempt: nil, launchedAt: now, now: now.addingTimeInterval(10)) == now.addingTimeInterval(30))
    }

    @Test func laterChecksAreADayAfterTheLastAttempt() {
        let schedule = UpdateSchedule()
        let attempt = now.addingTimeInterval(30)
        #expect(schedule.nextCheck(lastAttempt: attempt, launchedAt: now, now: attempt) == attempt.addingTimeInterval(86_400))
        // Overdue (e.g. the Mac slept through it): due now, not in the past's future.
        let overdue = schedule.nextCheck(lastAttempt: attempt, launchedAt: now, now: attempt.addingTimeInterval(90_000))
        #expect(overdue == attempt.addingTimeInterval(86_400))
    }

    @Test func clockMovingBackwardsNeverPushesTheCheckPastADay() {
        let schedule = UpdateSchedule()
        let futureAttempt = now.addingTimeInterval(10 * 86_400)
        #expect(schedule.nextCheck(lastAttempt: futureAttempt, launchedAt: now, now: now) == now.addingTimeInterval(86_400))
    }
}

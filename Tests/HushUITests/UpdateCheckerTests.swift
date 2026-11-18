import Foundation
import HushCore
import Testing
@testable import HushUI

struct OfflineError: Error {}

@MainActor
@Suite struct UpdateCheckerTests {
    private static let day: TimeInterval = 24 * 60 * 60

    // MARK: Finding an update

    @Test func newerReleaseIsPendingAndNotifiesOnce() async throws {
        let h = UpdateHarness()
        h.fake.response = .release(makeRelease("0.2.0"))

        await h.checker.checkAutomatically()
        let pending = try #require(h.checker.pendingUpdate)
        #expect(pending.version == SemanticVersion("0.2.0"))
        #expect(pending.downloadURL == dmgURL("0.2.0"))
        #expect(h.checker.hasPendingUpdate)
        #expect(h.notifier.posted == [SemanticVersion("0.2.0")!])
        #expect(h.persister.settings.notifiedVersion == "0.2.0")
        #expect(h.persister.settings.lastUpdateCheck == h.clock.now)

        h.clock.advance(Self.day)
        await h.checker.checkAutomatically()
        #expect(h.notifier.posted.count == 1, "one notification per version")
        #expect(h.checker.hasPendingUpdate, "the banner stays")
    }

    @Test func notificationIsNotRepeatedAfterRelaunch() async {
        let h = UpdateHarness(settings: UpdateSettings(notifiedVersion: "0.2.0"))
        h.fake.response = .release(makeRelease("0.2.0"))
        await h.checker.checkAutomatically()
        #expect(h.checker.hasPendingUpdate)
        #expect(h.notifier.posted.isEmpty)
    }

    @Test func authorizationIsRequestedOnlyOnceAnUpdateIsFound() async {
        let h = UpdateHarness()
        h.checker.start()
        h.checker.stop()
        #expect(h.notifier.authorizationRequests == 0, "not at launch")

        h.fake.response = .release(makeRelease("0.1.0"))
        await h.checker.checkAutomatically()
        #expect(h.notifier.authorizationRequests == 0, "not while up to date")

        h.fake.response = .release(makeRelease("0.2.0"))
        await h.checker.checkAutomatically()
        #expect(h.notifier.authorizationRequests == 1)
    }

    @Test func deniedNotificationsStillShowTheBanner() async {
        let h = UpdateHarness()
        h.notifier.grants = false
        h.fake.response = .release(makeRelease("0.2.0"))
        await h.checker.checkAutomatically()
        #expect(h.notifier.posted.isEmpty)
        #expect(h.checker.hasPendingUpdate)
    }

    @Test func sameOrOlderReleaseIsUpToDate() async {
        let h = UpdateHarness(current: "0.10.0")
        h.fake.response = .release(makeRelease("0.9.0"))
        await h.checker.checkNow()
        #expect(h.checker.checkStatus == .upToDate)
        #expect(!h.checker.hasPendingUpdate)
        #expect(h.notifier.posted.isEmpty)
    }

    @Test func noPublishedReleaseIsUpToDate() async {
        let h = UpdateHarness()
        h.fake.response = .release(nil)
        await h.checker.checkNow()
        #expect(h.checker.checkStatus == .upToDate)
    }

    @Test func draftsAndPrereleasesAreIgnored() async {
        let h = UpdateHarness()
        h.fake.response = .release(makeRelease("9.0.0", prerelease: true))
        await h.checker.checkNow()
        #expect(h.checker.checkStatus == .upToDate)
        #expect(!h.checker.hasPendingUpdate)

        h.fake.response = .release(makeRelease("9.0.0", draft: true))
        await h.checker.checkNow()
        #expect(!h.checker.hasPendingUpdate)
        #expect(h.notifier.authorizationRequests == 0)
    }

    @Test func installingTheUpdateClearsIt() async {
        // Pending in the old copy; the relaunched (updated) copy finds nothing newer.
        let h = UpdateHarness(current: "0.2.0", settings: UpdateSettings(notifiedVersion: "0.2.0"))
        h.fake.response = .release(makeRelease("0.2.0"))
        await h.checker.checkAutomatically()
        #expect(!h.checker.hasPendingUpdate)
    }

    // MARK: Later / Skip / Download

    @Test func laterSnoozesForADay() async {
        let h = UpdateHarness()
        h.fake.response = .release(makeRelease("0.2.0"))
        await h.checker.checkAutomatically()
        let start = h.clock.now

        h.checker.remindLater()
        #expect(!h.checker.hasPendingUpdate)
        #expect(h.persister.settings.snoozedUntil == start.addingTimeInterval(Self.day))

        h.clock.advance(Self.day - 1)
        h.checker.refresh()
        #expect(!h.checker.hasPendingUpdate)

        h.clock.advance(1)
        h.checker.refresh()
        #expect(h.checker.hasPendingUpdate)
        #expect(h.notifier.posted.count == 1, "the snooze ending doesn't re-notify")
    }

    @Test func snoozeSurvivesAChecksDuringIt() async {
        let h = UpdateHarness()
        h.fake.response = .release(makeRelease("0.2.0"))
        await h.checker.checkAutomatically()
        h.checker.remindLater()
        h.clock.advance(60)
        await h.checker.checkAutomatically()
        #expect(!h.checker.hasPendingUpdate)
    }

    @Test func skipSuppressesUntilANewerVersion() async throws {
        let h = UpdateHarness()
        h.fake.response = .release(makeRelease("0.2.0"))
        await h.checker.checkAutomatically()

        h.checker.skipThisVersion()
        #expect(!h.checker.hasPendingUpdate)
        #expect(h.persister.settings.skippedVersion == "0.2.0")

        h.clock.advance(Self.day)
        await h.checker.checkAutomatically()
        #expect(!h.checker.hasPendingUpdate, "the skipped version stays silent")

        h.fake.response = .release(makeRelease("0.3.0"))
        await h.checker.checkAutomatically()
        #expect(try #require(h.checker.pendingUpdate).version == SemanticVersion("0.3.0"))
        #expect(h.notifier.posted == [SemanticVersion("0.2.0")!, SemanticVersion("0.3.0")!])
    }

    @Test func skippedVersionDoesNotNotify() async {
        let h = UpdateHarness(settings: UpdateSettings(skippedVersion: "0.2.0"))
        h.fake.response = .release(makeRelease("0.2.0"))
        await h.checker.checkAutomatically()
        #expect(!h.checker.hasPendingUpdate)
        #expect(h.notifier.authorizationRequests == 0)
        #expect(h.notifier.posted.isEmpty)
    }

    @Test func downloadOpensTheDMGAndNeverInstalls() async {
        let h = UpdateHarness()
        h.fake.response = .release(makeRelease("0.2.0"))
        await h.checker.checkAutomatically()
        h.checker.download()
        #expect(h.opened == [dmgURL("0.2.0")])
    }

    @Test func notificationActionsDriveTheSameBehavior() async throws {
        let h = UpdateHarness()
        h.checker.start()
        h.checker.stop()
        let onAction = try #require(h.notifier.onAction)

        onAction(.download, "0.2.0", dmgURL("0.2.0"))
        onAction(.download, "0.2.0", nil)
        onAction(.download, "0.2.0", URL(string: "https://evil.example/Hush.dmg"))
        #expect(h.opened == [dmgURL("0.2.0"), UpdatePolicy.releasesPageURL, UpdatePolicy.releasesPageURL])

        onAction(.later, "0.2.0", nil)
        #expect(h.persister.settings.snoozedUntil == h.clock.now.addingTimeInterval(Self.day))

        onAction(.skip, "0.2.0", nil)
        #expect(h.persister.settings.skippedVersion == "0.2.0")
    }

    // MARK: Failures

    @Test func failureIsSilentAndKeepsTheLastState() async {
        let h = UpdateHarness()
        h.fake.response = .release(makeRelease("0.2.0"))
        await h.checker.checkAutomatically()
        let lastCheck = h.persister.settings.lastUpdateCheck

        h.clock.advance(Self.day)
        h.fake.response = .failure(OfflineError())
        await h.checker.checkAutomatically()
        #expect(h.checker.pendingUpdate?.version == SemanticVersion("0.2.0"))
        #expect(h.checker.checkStatus == .idle, "automatic failures don't surface")
        #expect(h.persister.settings.lastUpdateCheck == lastCheck)
        #expect(h.notifier.posted.count == 1)
    }

    @Test func sendsTheLastETagAndTreatsNotModifiedAsSuccess() async {
        let h = UpdateHarness()
        h.fake.response = .release(makeRelease("0.2.0"), etag: #"W/"v1""#)
        await h.checker.checkAutomatically()

        h.clock.advance(Self.day)
        h.fake.response = .notModified
        await h.checker.checkNow()
        #expect(h.fake.receivedETags == [nil, #"W/"v1""#])
        #expect(h.checker.pendingUpdate?.version == SemanticVersion("0.2.0"))
        #expect(h.checker.checkStatus == .available(SemanticVersion("0.2.0")!))
        #expect(h.persister.settings.lastUpdateCheck == h.clock.now)
        #expect(h.notifier.posted.count == 1)
    }

    @Test func notModifiedWhileUpToDateStaysUpToDate() async {
        let h = UpdateHarness()
        h.fake.response = .release(makeRelease("0.1.0"), etag: "e1")
        await h.checker.checkNow()
        h.fake.response = .notModified
        await h.checker.checkNow()
        #expect(h.checker.checkStatus == .upToDate)
    }

    @Test func rateLimitDelaysTheNextAttempt() async {
        let h = UpdateHarness()
        h.fake.response = .failure(ReleaseFetchError.rateLimited(retryAfter: 7_200))
        h.sleepLimit = 2
        h.checker.start()
        await h.checker.scheduleTask?.value
        #expect(h.sleeps == [.seconds(30), .seconds(7_200)])
    }

    @Test func rateLimitDelayIsCappedAtADay() async {
        let h = UpdateHarness()
        h.fake.response = .failure(ReleaseFetchError.rateLimited(retryAfter: 10 * Self.day))
        h.sleepLimit = 2
        h.checker.start()
        await h.checker.scheduleTask?.value
        #expect(h.sleeps == [.seconds(30), .seconds(Self.day)])
    }

    @Test func manualCheckReportsEachOutcome() async {
        let h = UpdateHarness()
        h.fake.response = .failure(OfflineError())
        await h.checker.checkNow()
        #expect(h.checker.checkStatus == .failed)

        h.fake.response = .release(makeRelease("0.1.0"))
        await h.checker.checkNow()
        #expect(h.checker.checkStatus == .upToDate)

        h.fake.response = .release(makeRelease("0.2.0"))
        await h.checker.checkNow()
        #expect(h.checker.checkStatus == .available(SemanticVersion("0.2.0")!))
    }

    @Test func manualCheckShowsCheckingWhileInFlight() async throws {
        let fetcher = GatedReleaseFetcher(release: makeRelease("0.1.0"))
        let h = UpdateHarness(fetcher: fetcher)
        let check = Task { await h.checker.checkNow() }
        while await fetcher.started == 0 { await Task.yield() }
        #expect(h.checker.checkStatus == .checking)

        // A second request joins the one in flight instead of fetching again.
        let second = Task { await h.checker.checkNow() }
        await Task.yield()
        await fetcher.open()
        await check.value
        await second.value
        #expect(await fetcher.started == 1)
        #expect(h.checker.checkStatus == .upToDate)
    }

    @Test func unversionedBuildNeverFetches() async {
        let h = UpdateHarness(current: nil)
        await h.checker.checkNow()
        #expect(h.fake.calls == 0)
        #expect(h.checker.checkStatus == .failed)
    }

    // MARK: Schedule

    @Test func checksThirtySecondsAfterLaunchThenDaily() async {
        let h = UpdateHarness()
        h.fake.response = .release(makeRelease("0.1.0"))
        h.sleepLimit = 3
        h.checker.start()
        await h.checker.scheduleTask?.value

        #expect(h.sleeps == [.seconds(30), .seconds(Self.day), .seconds(Self.day)])
        #expect(h.fake.calls == 2)
    }

    @Test func failedChecksRetryAfterOneHourThenFourThenDaily() async {
        let h = UpdateHarness()
        h.fake.response = .failure(OfflineError())
        h.sleepLimit = 6
        h.checker.start()
        await h.checker.scheduleTask?.value

        #expect(h.sleeps == [.seconds(30), .seconds(3_600), .seconds(14_400), .seconds(Self.day), .seconds(Self.day), .seconds(Self.day)])
        #expect(h.fake.calls == 5)
    }

    @Test func successAfterAFailureReturnsToTheDailyCadence() async {
        let h = UpdateHarness()
        h.fake.response = .failure(OfflineError())
        await h.checker.checkAutomatically()
        h.fake.response = .release(makeRelease("0.1.0"))
        h.sleepLimit = 3
        h.checker.start()
        await h.checker.scheduleTask?.value
        // The pending retry fires an hour after the failure, succeeds, then it's daily again.
        #expect(h.sleeps == [.seconds(3_600), .seconds(Self.day), .seconds(Self.day)])
    }

    @Test func unversionedBuildNeverSchedules() async {
        let h = UpdateHarness(current: nil)
        h.sleepLimit = 5
        h.checker.start()
        await h.checker.scheduleTask?.value
        #expect(h.checker.scheduleTask == nil)
        #expect(h.sleeps.isEmpty)
        #expect(h.fake.calls == 0)
    }

    @Test func unversionedManualCheckStillMovesTheScheduleForward() async {
        let h = UpdateHarness(current: nil)
        await h.checker.checkNow()
        await h.checker.checkNow()
        #expect(h.checker.checkStatus == .failed)
        #expect(h.fake.calls == 0)
    }

    @Test func scheduleNeverSpinsEvenWhenSleepsReturnEarly() async {
        let h = UpdateHarness()
        h.fake.response = .failure(OfflineError())
        h.sleepAdvancesClock = false
        h.sleepLimit = 6
        h.checker.start()
        await h.checker.scheduleTask?.value

        #expect(h.sleeps.count == 6)
        #expect(h.sleeps.dropFirst().allSatisfy { $0 >= .seconds(60) }, "\(h.sleeps)")
    }

    @Test func turningAutomaticChecksOffStopsTheScheduleAndPersists() async {
        let h = UpdateHarness(settings: UpdateSettings(automaticUpdateChecks: false))
        h.checker.start()
        #expect(h.checker.scheduleTask == nil)
        #expect(!h.checker.automaticChecks)

        h.sleepLimit = 2
        h.checker.automaticChecks = true
        #expect(h.persister.settings.automaticUpdateChecks)
        await h.checker.scheduleTask?.value
        #expect(h.fake.calls == 1)

        h.checker.automaticChecks = false
        #expect(h.checker.scheduleTask == nil)
        #expect(!h.persister.settings.automaticUpdateChecks)
    }

    @Test func snoozeWakesTheScheduleWhenItEndsEvenWithAutomaticChecksOff() async throws {
        let h = UpdateHarness(settings: UpdateSettings(automaticUpdateChecks: false))
        h.fake.response = .release(makeRelease("0.2.0"))
        await h.checker.checkNow()
        h.sleepLimit = 2
        h.checker.start()
        h.checker.remindLater()
        let task = try #require(h.checker.scheduleTask)
        await task.value

        #expect(h.sleeps.first == .seconds(Self.day))
        #expect(h.checker.hasPendingUpdate, "the banner returns when the snooze ends")
        #expect(h.fake.calls == 1, "no automatic fetch while automatic checks are off")
    }
}

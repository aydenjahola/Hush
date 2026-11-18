import Foundation
import HushCore
import Observation
import os

/// What the user can do about an available update, from the popover banner or the notification.
public enum UpdateAction: String, Sendable, CaseIterable {
    case download, later, skip
}

/// Fetches the latest published release. Injected so tests never touch the network.
public protocol ReleaseFetching: Sendable {
    /// The latest release, or nil when the repository has none yet.
    func latestRelease() async throws -> GitHubRelease?
}

/// Posts the "update available" notification. Injected so tests never touch UserNotifications.
@MainActor
public protocol UpdateNotifying: AnyObject {
    /// Called when the user picks one of the notification's actions: action, version, download URL.
    var onAction: (@MainActor (UpdateAction, String, URL?) -> Void)? { get set }
    /// Asks for permission to notify (prompting only the first time). Returns whether it's granted.
    func requestAuthorization() async -> Bool
    func post(_ update: AvailableUpdate) async
}

/// Notify-only update checker: asks GitHub for the latest release about 30 s after launch and then
/// once a day, and tells the user when a newer version exists. It never downloads or installs anything.
@MainActor
@Observable
public final class UpdateChecker {
    /// The inline status for Settings → "Check Now". Automatic checks never change it.
    public enum CheckStatus: Equatable, Sendable {
        case idle, checking, upToDate, failed
        case available(SemanticVersion)
    }

    private enum Outcome {
        case upToDate, failed
        case available(AvailableUpdate)
    }

    public static let snoozeInterval: TimeInterval = 24 * 60 * 60

    /// The newest release that's newer than this copy, whether or not the user silenced it.
    public private(set) var latestUpdate: AvailableUpdate?
    /// `latestUpdate` unless it's snoozed or skipped: drives the banner and the menu bar badge.
    public private(set) var pendingUpdate: AvailableUpdate?
    public private(set) var checkStatus: CheckStatus = .idle
    private var settings: UpdateSettings

    public var hasPendingUpdate: Bool { pendingUpdate != nil }
    public var lastUpdateCheck: Date? { settings.lastUpdateCheck }

    public var automaticChecks: Bool {
        get { settings.automaticUpdateChecks }
        set {
            guard newValue != settings.automaticUpdateChecks else { return }
            settings.automaticUpdateChecks = newValue
            persist()
            if isStarted { reschedule() }
        }
    }

    @ObservationIgnored private let currentVersion: SemanticVersion?
    @ObservationIgnored private let fetcher: any ReleaseFetching
    @ObservationIgnored private let notifier: any UpdateNotifying
    @ObservationIgnored private let persister: any UpdateSettingsPersisting
    @ObservationIgnored private let openURL: @MainActor (URL) -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void
    @ObservationIgnored private let schedule: UpdateSchedule
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var launchedAt: Date
    /// This session's last check attempt, successful or not; failures wait for the next cycle.
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var inFlight: Task<Outcome, Never>?
    /// The sleeping schedule loop (exposed for tests).
    @ObservationIgnored private(set) var scheduleTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: HushIdentity.bundleID, category: "updates")

    /// - Parameter currentVersion: this copy's version; nil (an unversioned dev build) disables checking.
    public init(
        currentVersion: SemanticVersion?,
        fetcher: any ReleaseFetching,
        notifier: any UpdateNotifying,
        persister: any UpdateSettingsPersisting,
        openURL: @escaping @MainActor (URL) -> Void,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        schedule: UpdateSchedule = UpdateSchedule()
    ) {
        self.currentVersion = currentVersion
        self.fetcher = fetcher
        self.notifier = notifier
        self.persister = persister
        self.openURL = openURL
        self.now = now
        self.sleep = sleep
        self.schedule = schedule
        self.settings = persister.loadUpdateSettings()
        self.launchedAt = now()
    }

    // MARK: Lifecycle

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        launchedAt = now()
        notifier.onAction = { [weak self] action, version, url in
            self?.handleNotificationAction(action, version: version, url: url)
        }
        reschedule()
    }

    public func stop() {
        isStarted = false
        scheduleTask?.cancel()
        scheduleTask = nil
    }

    // MARK: Checking

    /// Settings → "Check Now": checks immediately and reports the result in `checkStatus`.
    public func checkNow() async {
        checkStatus = .checking
        checkStatus = switch await check() {
        case .upToDate: .upToDate
        case .failed: .failed
        case .available(let update): .available(update.version)
        }
        if isStarted { reschedule() }
    }

    /// One scheduled check. Silent: failures only reach the debug log.
    func checkAutomatically() async {
        _ = await check()
    }

    /// Joins a check already in flight rather than fetching twice.
    private func check() async -> Outcome {
        if let inFlight { return await inFlight.value }
        let task = Task { await self.fetchAndApply() }
        inFlight = task
        let outcome = await task.value
        inFlight = nil
        return outcome
    }

    private func fetchAndApply() async -> Outcome {
        guard let currentVersion else {
            logger.debug("Skipping update check: this build has no version")
            return .failed
        }
        lastAttempt = now()
        let release: GitHubRelease?
        do {
            release = try await fetcher.latestRelease()
        } catch {
            logger.debug("Update check failed: \(String(describing: error), privacy: .public)")
            return .failed
        }
        settings.lastUpdateCheck = now()
        if let release, UpdatePolicy.isIgnored(release) {
            logger.debug("Ignoring release \(release.tagName, privacy: .public): draft, prerelease or unparseable tag")
        } else {
            latestUpdate = release.flatMap { UpdatePolicy.availableUpdate(in: $0, current: currentVersion) }
        }
        persist()
        refresh()
        await notifyIfNeeded()
        return latestUpdate.map(Outcome.available) ?? .upToDate
    }

    /// One macOS notification per new version. Authorization is requested only now, when there's
    /// something to say; if it's denied, the banner and badge still work.
    private func notifyIfNeeded() async {
        guard let pending = pendingUpdate, settings.notifiedVersion != pending.version.description else { return }
        settings.notifiedVersion = pending.version.description
        persist()
        guard await notifier.requestAuthorization() else {
            logger.debug("Notifications not authorized; showing the update in the popover only")
            return
        }
        await notifier.post(pending)
    }

    // MARK: User actions

    /// Opens the DMG (or the release page) in the browser. Hush never downloads or replaces itself.
    public func download() {
        guard let update = pendingUpdate ?? latestUpdate else { return }
        openURL(update.downloadURL)
    }

    /// Hides the banner, badge and notification for 24 hours.
    public func remindLater() {
        settings.snoozedUntil = now().addingTimeInterval(Self.snoozeInterval)
        persist()
        refresh()
        if isStarted { reschedule() }
    }

    /// Stays silent about this version until a newer one exists.
    public func skipThisVersion() {
        guard let update = pendingUpdate ?? latestUpdate else { return }
        skip(update.version.description)
    }

    /// Re-evaluates the snooze against the clock (call when the popover opens).
    public func refresh() {
        let current = now()
        pendingUpdate = latestUpdate.flatMap { update in
            UpdatePolicy.isSuppressed(update, settings: settings, now: current) ? nil : update
        }
    }

    private func skip(_ version: String) {
        settings.skippedVersion = version
        persist()
        refresh()
    }

    private func handleNotificationAction(_ action: UpdateAction, version: String, url: URL?) {
        switch action {
        case .download:
            openURL(url.flatMap { UpdatePolicy.isTrusted($0) ? $0 : nil } ?? UpdatePolicy.releasesPageURL)
        case .later:
            remindLater()
        case .skip:
            guard SemanticVersion(version) != nil else { return }
            skip(version)
        }
    }

    private func persist() {
        persister.saveUpdateSettings(settings)
    }

    // MARK: Schedule

    /// One sleeping task: wakes for the next due check or when a snooze ends, whichever is first.
    /// `Task.sleep` doesn't wake the Mac; after sleep, an overdue wake-up runs promptly.
    private func reschedule() {
        scheduleTask?.cancel()
        scheduleTask = nil
        guard isStarted, nextWake() != nil else { return }
        scheduleTask = Task { [weak self] in await self?.runSchedule() }
    }

    private func nextWake() -> (wake: Date, due: Date)? {
        let current = now()
        let due = schedule.nextCheck(lastAttempt: lastAttempt, launchedAt: launchedAt, now: current)
        var wake: Date? = settings.automaticUpdateChecks ? due : nil
        if let snoozedUntil = settings.snoozedUntil, snoozedUntil > current {
            wake = min(wake ?? snoozedUntil, snoozedUntil)
        }
        return wake.map { ($0, due) }
    }

    private func runSchedule() async {
        while !Task.isCancelled, let next = nextWake() {
            let delay = max(0, next.wake.timeIntervalSince(now()))
            do {
                try await sleep(.seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            refresh()
            if settings.automaticUpdateChecks, now() >= next.due.addingTimeInterval(-1) {
                await checkAutomatically()
            }
        }
    }
}

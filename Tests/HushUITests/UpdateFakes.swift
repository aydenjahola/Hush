import Foundation
import HushCore
import Synchronization
@testable import HushUI

func makeRelease(_ version: String, draft: Bool = false, prerelease: Bool = false) -> GitHubRelease {
    GitHubRelease(
        tagName: "v\(version)",
        htmlURL: URL(string: "https://github.com/aydenjahola/Hush/releases/tag/v\(version)")!,
        draft: draft,
        prerelease: prerelease,
        assets: [.init(
            name: "Hush-\(version).dmg",
            browserDownloadURL: URL(string: "https://github.com/aydenjahola/Hush/releases/download/v\(version)/Hush-\(version).dmg")!)])
}

func dmgURL(_ version: String) -> URL {
    URL(string: "https://github.com/aydenjahola/Hush/releases/download/v\(version)/Hush-\(version).dmg")!
}

final class FakeReleaseFetcher: ReleaseFetching {
    enum Response {
        case release(GitHubRelease?, etag: String? = nil)
        case notModified
        case failure(any Error & Sendable)
    }

    private struct State {
        var response: Response = .release(nil)
        var calls = 0
        var receivedETags: [String?] = []
    }

    private let state = Mutex(State())

    var response: Response {
        get { state.withLock { $0.response } }
        set { state.withLock { $0.response = newValue } }
    }

    var calls: Int { state.withLock { $0.calls } }
    var receivedETags: [String?] { state.withLock { $0.receivedETags } }

    func latestRelease(ifNoneMatch etag: String?) async throws -> ReleaseFetchResult {
        let response = state.withLock { state in
            state.calls += 1
            state.receivedETags.append(etag)
            return state.response
        }
        switch response {
        case .release(let release, let etag): return .release(release, etag: etag)
        case .notModified: return .notModified
        case .failure(let error): throw error
        }
    }
}

/// Holds every fetch until `open()` so tests can observe the "Checking…" state.
actor GatedReleaseFetcher: ReleaseFetching {
    private let release: GitHubRelease?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var started = 0

    init(release: GitHubRelease?) { self.release = release }

    func latestRelease(ifNoneMatch etag: String?) async throws -> ReleaseFetchResult {
        started += 1
        await withCheckedContinuation { waiters.append($0) }
        return .release(release, etag: nil)
    }

    func open() {
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

@MainActor
final class FakeNotifier: UpdateNotifying {
    var onAction: (@MainActor (UpdateAction, String, URL?) -> Void)?
    var grants = true
    private(set) var authorizationRequests = 0
    private(set) var posted: [SemanticVersion] = []

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return grants
    }

    func post(_ update: AvailableUpdate) async {
        posted.append(update.version)
    }
}

final class FakeUpdatePersister: UpdateSettingsPersisting {
    var settings: UpdateSettings
    private(set) var saves = 0

    init(settings: UpdateSettings = UpdateSettings()) { self.settings = settings }

    func loadUpdateSettings() -> UpdateSettings { settings }
    func saveUpdateSettings(_ settings: UpdateSettings) {
        self.settings = settings
        saves += 1
    }
}

@MainActor
final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
final class UpdateHarness {
    let clock = TestClock()
    let fetcher: any ReleaseFetching
    let notifier = FakeNotifier()
    let persister: FakeUpdatePersister
    private(set) var opened: [URL] = []
    private(set) var sleeps: [Duration] = []
    /// The schedule loop's sleep throws (ending the loop) once this many sleeps have happened.
    var sleepLimit = Int.max
    /// False simulates sleeps that return early (the clock doesn't move).
    var sleepAdvancesClock = true
    var checker: UpdateChecker!

    init(
        current: String? = "0.1.0",
        fetcher: any ReleaseFetching = FakeReleaseFetcher(),
        settings: UpdateSettings = UpdateSettings()
    ) {
        self.fetcher = fetcher
        self.persister = FakeUpdatePersister(settings: settings)
        let clock = clock
        checker = UpdateChecker(
            currentVersion: current.flatMap(SemanticVersion.init),
            fetcher: fetcher,
            notifier: notifier,
            persister: persister,
            openURL: { [weak self] in self?.opened.append($0) },
            now: { clock.now },
            sleep: { [weak self] duration in
                guard let self else { throw CancellationError() }
                self.sleeps.append(duration)
                if self.sleeps.count >= self.sleepLimit { throw CancellationError() }
                if self.sleepAdvancesClock { clock.advance(duration / .seconds(1)) }
            })
    }

    var fake: FakeReleaseFetcher { fetcher as! FakeReleaseFetcher }
}

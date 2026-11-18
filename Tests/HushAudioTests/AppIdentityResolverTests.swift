import AppKit
import Testing
@testable import HushAudio

@MainActor
final class FakeRunningApps: RunningAppsProviding {
    var responsible: [pid_t: pid_t] = [:]
    var apps: [pid_t: RunningAppInfo] = [:]
    var names: [pid_t: String] = [:]
    private(set) var appLookups = 0
    private(set) var regularScans = 0
    private var handler: (@MainActor (RunningAppsEvent) -> Void)?

    func responsiblePID(for pid: pid_t) -> pid_t? { responsible[pid] }

    func app(pid: pid_t) -> RunningAppInfo? {
        appLookups += 1
        return apps[pid]
    }

    func regularApps() -> [(pid: pid_t, bundleID: String)] {
        regularScans += 1
        return apps.compactMap { pid, app in
            guard app.isRegular, let bundleID = app.bundleID else { return nil }
            return (pid, bundleID)
        }
    }

    func processName(pid: pid_t) -> String? { names[pid] }
    func observe(_ handler: @escaping @MainActor (RunningAppsEvent) -> Void) { self.handler = handler }
    func stopObserving() { handler = nil }
    func emit(_ event: RunningAppsEvent) { handler?(event) }

    static func regular(_ bundleID: String, name: String? = nil) -> RunningAppInfo {
        RunningAppInfo(bundleID: bundleID, name: name ?? bundleID, executableName: nil, isRegular: true, icon: nil)
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1))) struct AppIdentityResolverTests {
    func makeResolver(_ apps: FakeRunningApps) -> (AppIdentityResolver, () -> Int) {
        let resolver = AppIdentityResolver(provider: apps)
        var invalidations = 0
        resolver.onInvalidate = { invalidations += 1 }
        resolver.startObserving()
        return (resolver, { invalidations })
    }

    @Test func helperIsAttributedToItsResponsibleApp() {
        let apps = FakeRunningApps()
        apps.apps[100] = FakeRunningApps.regular("com.browser", name: "Browser")
        apps.responsible[101] = 100
        let (resolver, _) = makeResolver(apps)

        let identity = resolver.identity(pid: 101, bundleID: "com.browser.helper")
        #expect(identity.id == "com.browser")
        #expect(identity.displayName == "Browser")
        #expect(identity.isRegularApp)
    }

    @Test func standaloneDaemonIsCachedInsteadOfRescanningEveryRefresh() {
        let apps = FakeRunningApps()
        apps.names[50] = "mediaremoted"
        let (resolver, _) = makeResolver(apps)

        let first = resolver.identity(pid: 50, bundleID: "com.apple.mediaremoted")
        let scans = apps.regularScans
        let lookups = apps.appLookups
        for _ in 0..<10 { _ = resolver.identity(pid: 50, bundleID: "com.apple.mediaremoted") }

        #expect(first.id == "com.apple.mediaremoted")
        #expect(first.displayName == "mediaremoted")
        #expect(apps.regularScans == scans, "no rescans of every running app")
        #expect(apps.appLookups == lookups)
    }

    @Test func regularAppsAreScannedOnceForManyDaemons() {
        let apps = FakeRunningApps()
        let (resolver, _) = makeResolver(apps)
        for pid in pid_t(50)..<65 { _ = resolver.identity(pid: pid, bundleID: "com.apple.daemon\(pid)") }
        #expect(apps.regularScans == 1, "one snapshot of the running apps, reused until an app launches or quits")
    }

    @Test func appLaunchReResolvesStandaloneHelpersSoTheyJoinTheirApp() {
        // The helper's process object can appear before its app is visible as a running app.
        let apps = FakeRunningApps()
        apps.responsible[201] = 200
        apps.names[201] = "Zen Helper"
        let (resolver, invalidations) = makeResolver(apps)
        #expect(resolver.identity(pid: 201, bundleID: "app.zen.helper").id == "app.zen.helper")

        apps.apps[200] = FakeRunningApps.regular("app.zen", name: "Zen")
        #expect(resolver.identity(pid: 201, bundleID: "app.zen.helper").id == "app.zen.helper", "cached until something launches")

        apps.emit(.launched(200))
        #expect(invalidations() == 1, "the monitor is told to regroup")
        #expect(resolver.identity(pid: 201, bundleID: "app.zen.helper").id == "app.zen")
    }

    @Test func appLaunchKeepsAttributedEntries() {
        let apps = FakeRunningApps()
        apps.apps[100] = FakeRunningApps.regular("com.browser")
        apps.responsible[101] = 100
        let (resolver, invalidations) = makeResolver(apps)
        _ = resolver.identity(pid: 101, bundleID: nil)
        let lookups = apps.appLookups

        apps.emit(.launched(300))
        _ = resolver.identity(pid: 101, bundleID: nil)
        #expect(apps.appLookups == lookups)
        #expect(invalidations() == 0, "nothing standalone to re-resolve")
    }

    @Test func bundlePrefixMatchUsesTheRegularAppSnapshotAndRefreshesItOnLaunch() {
        let apps = FakeRunningApps()
        let (resolver, _) = makeResolver(apps)
        #expect(resolver.identity(pid: 401, bundleID: "com.spotify.client.helper").id == "com.spotify.client.helper")

        apps.apps[400] = FakeRunningApps.regular("com.spotify.client", name: "Spotify")
        apps.emit(.launched(400))
        #expect(resolver.identity(pid: 401, bundleID: "com.spotify.client.helper").id == "com.spotify.client")
    }

    @Test func terminationDropsEntriesOwnedByTheQuitApp() {
        let apps = FakeRunningApps()
        apps.apps[100] = FakeRunningApps.regular("com.browser")
        apps.responsible[101] = 100
        let (resolver, invalidations) = makeResolver(apps)
        #expect(resolver.identity(pid: 101, bundleID: nil).id == "com.browser")

        apps.apps[100] = nil
        apps.responsible[101] = nil
        apps.names[101] = "orphan"
        apps.emit(.terminated(100))
        #expect(invalidations() == 1)
        #expect(resolver.identity(pid: 101, bundleID: nil).id == "orphan")
    }

    @Test func pidReuseWithAnotherBundleIDResolvesAgain() {
        let apps = FakeRunningApps()
        apps.names[60] = "first"
        let (resolver, _) = makeResolver(apps)
        #expect(resolver.identity(pid: 60, bundleID: "com.first").id == "com.first")

        apps.names[60] = "second"
        #expect(resolver.identity(pid: 60, bundleID: "com.second").id == "com.second")
    }

    @Test func retainOnlyForgetsDeadProcesses() {
        let apps = FakeRunningApps()
        apps.names[70] = "old"
        let (resolver, _) = makeResolver(apps)
        #expect(resolver.identity(pid: 70, bundleID: nil).id == "old")

        resolver.retainOnly(pids: [])
        apps.names[70] = "new"
        #expect(resolver.identity(pid: 70, bundleID: nil).id == "new")
    }

    @Test func stopObservingIgnoresLaterEvents() {
        let apps = FakeRunningApps()
        apps.names[80] = "daemon"
        let (resolver, invalidations) = makeResolver(apps)
        _ = resolver.identity(pid: 80, bundleID: nil)
        resolver.stopObserving()
        apps.emit(.launched(1))
        #expect(invalidations() == 0)
    }
}

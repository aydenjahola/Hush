import AppKit
import Darwin

struct AppIdentity: Equatable {
    let id: String
    let displayName: String
    let icon: NSImage?
    /// The owning app's activation policy is `.regular` (it has a Dock icon).
    let isRegularApp: Bool
}

/// Attributes an audio process (often a helper) to the app the user knows.
///
/// Every result is cached per PID, standalone ones included: resolving a daemon asks LaunchServices
/// about every running app. A cached entry is reused while its bundle ID matches, which catches PID
/// reuse. App launches and terminations invalidate what they can change (`onInvalidate` then asks
/// the monitor to regroup):
/// - a launch drops standalone entries, since a helper's app may only now be visible (a helper's
///   process object can appear before its app is listed as running);
/// - a termination drops entries attributed to the app that quit.
@MainActor
final class AppIdentityResolver {
    private struct Entry {
        let bundleID: String?
        let identity: AppIdentity
        /// The app this process was attributed to; nil for standalone results.
        let ownerPID: pid_t?
    }

    /// Called after an app launch or termination dropped cached entries.
    var onInvalidate: (@MainActor () -> Void)?

    private let provider: any RunningAppsProviding
    private var cache: [pid_t: Entry] = [:]
    /// Running regular apps, taken once per launch or termination instead of once per object.
    private var regularApps: [(pid: pid_t, bundleID: String)]?

    init(provider: any RunningAppsProviding = WorkspaceRunningApps()) {
        self.provider = provider
    }

    func startObserving() {
        provider.observe { [weak self] event in self?.handle(event) }
    }

    func stopObserving() {
        provider.stopObserving()
    }

    func identity(pid: pid_t, bundleID: String?) -> AppIdentity {
        if let cached = cache[pid], cached.bundleID == bundleID { return cached.identity }
        let entry = resolve(pid: pid, bundleID: bundleID)
        cache[pid] = entry
        return entry.identity
    }

    /// Drops cached entries for processes that no longer exist.
    func retainOnly(pids: Set<pid_t>) {
        cache = cache.filter { pids.contains($0.key) }
    }

    private func handle(_ event: RunningAppsEvent) {
        regularApps = nil
        let before = cache.count
        switch event {
        case .launched:
            cache = cache.filter { $0.value.ownerPID != nil }
        case .terminated(let pid):
            cache = cache.filter { $0.key != pid && $0.value.ownerPID != pid }
        }
        if cache.count != before { onInvalidate?() }
    }

    private func resolve(pid: pid_t, bundleID: String?) -> Entry {
        if let owner = provider.responsiblePID(for: pid),
           let app = provider.app(pid: owner),
           let identity = Self.identity(of: app) {
            return Entry(bundleID: bundleID, identity: identity, ownerPID: owner)
        }
        if let bundleID,
           let owner = regularApp(owning: bundleID),
           let app = provider.app(pid: owner),
           let identity = Self.identity(of: app) {
            return Entry(bundleID: bundleID, identity: identity, ownerPID: owner)
        }
        let running = provider.app(pid: pid)
        let name = running?.executableName ?? provider.processName(pid: pid) ?? "Process \(pid)"
        let standalone = AppIdentity(
            id: bundleID ?? name,
            displayName: name,
            icon: running?.icon,
            isRegularApp: running?.isRegular ?? false)
        return Entry(bundleID: bundleID, identity: standalone, ownerPID: nil)
    }

    private static func identity(of app: RunningAppInfo) -> AppIdentity? {
        guard let bundleID = app.bundleID else { return nil }
        return AppIdentity(
            id: bundleID,
            displayName: app.name ?? bundleID,
            icon: app.icon,
            isRegularApp: app.isRegular)
    }

    /// The running regular app whose bundle ID is `bundleID` or its longest prefix ("com.x.helper" → "com.x").
    private func regularApp(owning bundleID: String) -> pid_t? {
        let apps = regularApps ?? provider.regularApps()
        regularApps = apps
        return apps
            .filter { bundleID == $0.bundleID || bundleID.hasPrefix($0.bundleID + ".") }
            .max { $0.bundleID.count < $1.bundleID.count }?
            .pid
    }
}

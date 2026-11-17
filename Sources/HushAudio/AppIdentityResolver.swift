import AppKit
import Darwin

struct AppIdentity: Equatable {
    let id: String
    let displayName: String
    let icon: NSImage?
}

/// Attributes an audio process (often a helper) to the app the user knows.
@MainActor
final class AppIdentityResolver {
    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t

    private let responsiblePID: ResponsibleFunction?
    private var cache: [pid_t: (bundleID: String?, identity: AppIdentity)] = [:]

    init() {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        responsiblePID = dlsym(rtldDefault, "responsibility_get_pid_responsible_for_pid")
            .map { unsafeBitCast($0, to: ResponsibleFunction.self) }
    }

    func identity(pid: pid_t, bundleID: String?) -> AppIdentity {
        if let cached = cache[pid], cached.bundleID == bundleID { return cached.identity }
        cache[pid] = nil
        let (resolved, isAttributed) = resolve(pid: pid, bundleID: bundleID)
        // Standalone fallbacks are not cached: the owning app may become visible later.
        if isAttributed { cache[pid] = (bundleID, resolved) }
        return resolved
    }

    /// Drops cached entries for processes that no longer exist.
    func retainOnly(pids: Set<pid_t>) {
        cache = cache.filter { pids.contains($0.key) }
    }

    private func resolve(pid: pid_t, bundleID: String?) -> (identity: AppIdentity, isAttributed: Bool) {
        if let responsiblePID {
            let owner = responsiblePID(pid)
            if owner > 0,
               let app = NSRunningApplication(processIdentifier: owner),
               let identity = Self.identity(of: app) {
                return (identity, true)
            }
        }
        if let bundleID,
           let app = Self.runningApp(owning: bundleID),
           let identity = Self.identity(of: app) {
            return (identity, true)
        }
        let name = Self.executableName(pid: pid)
        let standalone = AppIdentity(
            id: bundleID ?? name,
            displayName: name,
            icon: NSRunningApplication(processIdentifier: pid)?.icon)
        return (standalone, false)
    }

    private static func identity(of app: NSRunningApplication) -> AppIdentity? {
        guard let bundleID = app.bundleIdentifier else { return nil }
        return AppIdentity(id: bundleID, displayName: app.localizedName ?? bundleID, icon: app.icon)
    }

    private static func runningApp(owning bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular, let candidate = app.bundleIdentifier else { return false }
                return bundleID == candidate || bundleID.hasPrefix(candidate + ".")
            }
            .max { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) }
    }

    private static func executableName(pid: pid_t) -> String {
        if let name = NSRunningApplication(processIdentifier: pid)?.executableURL?.lastPathComponent {
            return name
        }
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "Process \(pid)" }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

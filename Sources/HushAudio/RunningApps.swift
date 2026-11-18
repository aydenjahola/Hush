import AppKit
import Darwin

/// What identity resolution needs to know about one running app.
struct RunningAppInfo {
    var bundleID: String?
    var name: String?
    var executableName: String?
    /// The activation policy is `.regular` (it has a Dock icon).
    var isRegular: Bool
    var icon: NSImage?
}

enum RunningAppsEvent: Equatable {
    case launched(pid_t)
    case terminated(pid_t)
}

/// The running-app queries `AppIdentityResolver` makes, so tests can count and script them.
@MainActor
protocol RunningAppsProviding: AnyObject {
    /// The process responsible for `pid` (the app that launched a helper), if known.
    func responsiblePID(for pid: pid_t) -> pid_t?
    func app(pid: pid_t) -> RunningAppInfo?
    /// Every running regular app with a bundle ID. This asks LaunchServices about every app.
    func regularApps() -> [(pid: pid_t, bundleID: String)]
    /// The kernel's name for a process without an app.
    func processName(pid: pid_t) -> String?
    /// Reports app launches and terminations until `stopObserving()`.
    func observe(_ handler: @escaping @MainActor (RunningAppsEvent) -> Void)
    func stopObserving()
}

/// `NSWorkspace` and `NSRunningApplication`, plus the private responsibility lookup.
@MainActor
final class WorkspaceRunningApps: RunningAppsProviding {
    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t

    private let responsible: ResponsibleFunction?
    private var observers: [any NSObjectProtocol] = []

    init() {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        responsible = dlsym(rtldDefault, "responsibility_get_pid_responsible_for_pid")
            .map { unsafeBitCast($0, to: ResponsibleFunction.self) }
    }

    func responsiblePID(for pid: pid_t) -> pid_t? {
        guard let responsible else { return nil }
        let owner = responsible(pid)
        return owner > 0 ? owner : nil
    }

    func app(pid: pid_t) -> RunningAppInfo? {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        return RunningAppInfo(
            bundleID: app.bundleIdentifier,
            name: app.localizedName,
            executableName: app.executableURL?.lastPathComponent,
            isRegular: app.activationPolicy == .regular,
            icon: app.icon)
    }

    func regularApps() -> [(pid: pid_t, bundleID: String)] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let bundleID = app.bundleIdentifier else { return nil }
            return (app.processIdentifier, bundleID)
        }
    }

    func processName(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    func observe(_ handler: @escaping @MainActor (RunningAppsEvent) -> Void) {
        stopObserving()
        let center = NSWorkspace.shared.notificationCenter
        let names: [(name: Notification.Name, launched: Bool)] = [
            (NSWorkspace.didLaunchApplicationNotification, true),
            (NSWorkspace.didTerminateApplicationNotification, false),
        ]
        for (name, launched) in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let pid = app?.processIdentifier ?? 0
                MainActor.assumeIsolated { handler(launched ? .launched(pid) : .terminated(pid)) }
            })
        }
    }

    func stopObserving() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers = []
    }
}

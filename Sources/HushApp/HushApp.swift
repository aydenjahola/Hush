import AppKit
import HushAudio
import HushCore
import HushUI
import SwiftUI

@main
struct HushApp: App {
    // App.init runs once, so the store (and its audio sources) is created exactly once.
    @State private var store: MixerStore
    @State private var updates: UpdateChecker
    @State private var statusItem: StatusItemLauncher

    init() {
        // One SettingsStore for both, so level and update-state writes merge in settings.json.
        let settings = SettingsStore()
        let store = MixerStore(
            processSource: AudioProcessMonitor(),
            outputSource: DefaultOutputMonitor(),
            engineFactory: AppAudioEngineFactory(),
            permissionSource: AudioCapturePermission(),
            persister: settings)
        store.start()
        let updates = Self.makeUpdateChecker(settings: settings)
        updates.start()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { store.shutdown() }
        }
        // Permission can be granted or revoked in System Settings at any time; re-check when the
        // user comes back to Hush, as well as whenever the popover opens.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { store.refreshPermission() }
        }
        _store = State(initialValue: store)
        _updates = State(initialValue: updates)
        _statusItem = State(initialValue: StatusItemLauncher(store: store, updates: updates))
    }

    private static func makeUpdateChecker(settings: SettingsStore) -> UpdateChecker {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        // UNUserNotificationCenter needs an app bundle; the bare binary (no bundle, no version)
        // never checks for updates anyway.
        let notifier: any UpdateNotifying =
            Bundle.main.bundleIdentifier == nil
            ? NoUpdateNotifications()
            : UserNotificationUpdateNotifier()
        return UpdateChecker(
            currentVersion: version.flatMap(SemanticVersion.init),
            fetcher: GitHubReleaseFetcher(appVersion: version ?? "dev"),
            notifier: notifier,
            persister: settings,
            openURL: { NSWorkspace.shared.open($0) })
    }

    var body: some Scene {
        // The menu bar item (popover and quick menu) is AppKit; see StatusItemController.
        Settings {
            SettingsView(store: store, updates: updates)
        }
    }
}

/// Creates the menu bar item once the app has finished launching (App.init runs before that) and
/// keeps it alive for the life of the app.
@MainActor
private final class StatusItemLauncher {
    private let store: MixerStore
    private let updates: UpdateChecker
    private var controller: StatusItemController?
    private var observer: (any NSObjectProtocol)?

    init(store: MixerStore, updates: UpdateChecker) {
        self.store = store
        self.updates = updates
        // Normally App.init runs before launch finishes; if the app is already running, don't wait.
        if NSApplication.shared.isRunning {
            install()
            return
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.install() }
        }
    }

    private func install() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        guard controller == nil else { return }
        controller = StatusItemController(store: store, updates: updates)
    }
}

@MainActor
private final class NoUpdateNotifications: UpdateNotifying {
    var onAction: (@MainActor (UpdateAction, String, URL?) -> Void)?
    func requestAuthorization() async -> Bool { false }
    func post(_ update: AvailableUpdate) async {}
    func removeDelivered() {}
}

import AppKit
import HushAudio
import HushUI
import SwiftUI

@main
struct HushApp: App {
    private let store: MixerStore

    init() {
        let store = MixerStore(
            processSource: AudioProcessMonitor(),
            outputSource: DefaultOutputMonitor(),
            engineFactory: AppAudioEngineFactory(),
            permissionSource: AudioCapturePermission(),
            persister: SettingsStore())
        store.start()
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
        self.store = store
    }

    var body: some Scene {
        MenuBarExtra {
            MixerPopover(store: store)
        } label: {
            Image(systemName: store.isAnyAppAttenuated ? "speaker.wave.1.fill" : "speaker.wave.2.fill")
                .accessibilityLabel("Hush")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}

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

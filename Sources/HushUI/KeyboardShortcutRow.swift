import AppKit
import HushCore
import SwiftUI

/// Settings → General → Keyboard shortcut: a recorder for the shortcut that opens the mixer, and
/// a note under it when a combination can't be used. Reads the `GlobalShortcutController` from
/// the environment and shows nothing without one.
package struct KeyboardShortcutRow: View {
    @Environment(GlobalShortcutController.self) private var controller: GlobalShortcutController?

    package init() {}

    package var body: some View {
        if let controller {
            LabeledContent(L10n.keyboardShortcut) {
                ShortcutRecorder(controller: controller)
            }
            if let problem = controller.problem {
                Text(Self.message(for: problem))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    static func message(for problem: GlobalShortcutController.Problem) -> LocalizedStringResource {
        switch problem {
        case .inUse: L10n.shortcutInUse
        case .needsModifier: L10n.shortcutNeedsModifier
        case .standardShortcut: L10n.shortcutIsStandard
        }
    }
}

/// Click to record, press a combination to save it, Esc to cancel; the clear button removes it.
/// Key presses are read with a local event monitor that exists only while recording.
struct ShortcutRecorder: View {
    let controller: GlobalShortcutController
    @State private var monitor = KeyDownMonitor()

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if controller.isRecording { stopRecording() } else { startRecording() }
            } label: {
                Text(title)
                    .monospacedDigit()
                    .frame(minWidth: 110)
            }
            .accessibilityLabel(L10n.keyboardShortcut)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(controller.isRecording ? L10n.shortcutRecordingHint : L10n.shortcutRecordHint)

            if controller.shortcut != nil, !controller.isRecording {
                Button {
                    controller.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(L10n.clearShortcut)
                .accessibilityLabel(L10n.clearShortcut)
            }
        }
        .onDisappear { stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            stopRecording()
        }
    }

    private var title: String {
        if controller.isRecording { return String(localized: L10n.typeShortcut) }
        guard let shortcut = controller.shortcut else { return String(localized: L10n.recordShortcut) }
        return ShortcutFormatter.string(for: shortcut)
    }

    private var accessibilityValue: String {
        if controller.isRecording { return String(localized: L10n.typeShortcut) }
        guard let shortcut = controller.shortcut else { return String(localized: L10n.noShortcut) }
        return ShortcutFormatter.string(for: shortcut)
    }

    private func startRecording() {
        controller.beginRecording()
        monitor.start { event in handle(event) }
    }

    private func stopRecording() {
        monitor.stop()
        controller.endRecording()
    }

    private func handle(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let modifiers = GlobalShortcut.Modifiers(event.modifierFlags)
        if event.keyCode == GlobalShortcut.KeyCode.escape, modifiers.isEmpty {
            stopRecording()
            return
        }
        let candidate = GlobalShortcut(keyCode: event.keyCode, modifiers: modifiers)
        guard candidate.isValid else {
            controller.record(candidate)  // shows why, and keeps recording
            NSSound.beep()
            return
        }
        monitor.stop()
        controller.record(candidate)
    }
}

/// A local key-down monitor that swallows every key press while installed.
@MainActor
final class KeyDownMonitor {
    private var token: Any?

    func start(_ handler: @escaping @MainActor (NSEvent) -> Void) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handler(event) }
            return nil
        }
    }

    func stop() {
        guard let token else { return }
        NSEvent.removeMonitor(token)
        self.token = nil
    }
}

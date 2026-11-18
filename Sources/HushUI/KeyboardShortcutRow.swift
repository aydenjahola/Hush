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
                Text(problem.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        .background(WindowReader { monitor.window = $0 })
        .onDisappear { stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            stopRecording()
        }
        // VoiceOver announcements come from the controller, once per attempt.
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
        // Without the window, keys can't be limited to Settings, so don't record at all.
        guard monitor.window != nil else { return }
        controller.beginRecording()
        monitor.start(onKeyDown: { event in handle(event) }, onResignKey: { stopRecording() })
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

/// While started, takes key presses aimed at the recorder's window and swallows them. Key
/// presses in any other window (the popover, the quick menu) pass through untouched. It also
/// reports when that window stops being the key window.
@MainActor
final class KeyDownMonitor {
    /// The window the recorder is in, set by `WindowReader`.
    weak var window: NSWindow?
    private var token: Any?
    private var resignObserver: (any NSObjectProtocol)?

    func start(onKeyDown: @escaping @MainActor (NSEvent) -> Void, onResignKey: @escaping @MainActor () -> Void) {
        stop()
        guard let window else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
            guard let window, event.window === window else { return event }
            MainActor.assumeIsolated { onKeyDown(event) }
            return nil
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onResignKey() }
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }
}

/// Reports the window a SwiftUI view is in, and again whenever it moves to another one.
private struct WindowReader: NSViewRepresentable {
    let onChange: @MainActor (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReportingView {
        let view = ReportingView()
        view.onWindowChange = onChange
        return view
    }

    func updateNSView(_ view: ReportingView, context: Context) {
        view.onWindowChange = onChange
    }

    final class ReportingView: NSView {
        var onWindowChange: (@MainActor (NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }
}

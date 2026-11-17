import AppKit
import SwiftUI

/// Reports whether the hosting window is visible on screen (MenuBarExtra popover open/closed).
struct WindowVisibilityObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
    }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observation: (any NSObjectProtocol)?
        private var lastReported: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observation { NotificationCenter.default.removeObserver(observation) }
            observation = nil
            guard let window else {
                report(false)
                return
            }
            observation = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportCurrent() }
            }
            reportCurrent()
        }

        private func reportCurrent() {
            report(window?.occlusionState.contains(.visible) ?? false)
        }

        private func report(_ visible: Bool) {
            guard visible != lastReported else { return }
            lastReported = visible
            DispatchQueue.main.async { [weak self] in
                self?.onChange?(visible)
            }
        }
    }
}

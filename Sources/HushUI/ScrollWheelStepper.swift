import AppKit
import SwiftUI

/// Turns vertical scroll-wheel / trackpad scrolling over the view into whole steps.
/// Finger or wheel "up" is a positive step regardless of natural-scrolling settings.
struct ScrollWheelStepper: ViewModifier {
    let onSteps: (Int) -> Void

    /// A plain reference held in `@State`: it owns the NSEvent monitor token, and nothing in it is observed.
    @State private var monitor = ScrollMonitor()

    func body(content: Content) -> some View {
        // Keep the handler current so steps are computed from the latest value, not the one at hover start.
        monitor.handler = onSteps
        return content
            .onContinuousHover { phase in
                switch phase {
                case .active: monitor.install(onSteps)
                case .ended: monitor.remove()
                }
            }
            .onDisappear { monitor.remove() }
    }
}

@MainActor
final class ScrollMonitor {
    private static let pointsPerStep: CGFloat = 12
    private var token: Any?
    private var accumulated: CGFloat = 0
    var handler: ((Int) -> Void)?

    func install(_ onSteps: @escaping (Int) -> Void) {
        handler = onSteps
        guard token == nil else { return }
        accumulated = 0
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return event }
            let direction: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
            let delta = event.scrollingDeltaY * direction
            if event.hasPreciseScrollingDeltas {
                self.accumulated += delta
                let steps = Int(self.accumulated / Self.pointsPerStep)
                if steps != 0 {
                    self.accumulated -= CGFloat(steps) * Self.pointsPerStep
                    self.handler?(steps)
                }
            } else if delta != 0 {
                self.handler?(delta > 0 ? 1 : -1)
            }
            return nil
        }
    }

    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

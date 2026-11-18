import AppKit
import SwiftUI

/// Value math shared by every fader: the vertical strip fader, the classic-row slider and tiles.
struct FaderScale {
    static let step = 5
    /// Drags within this many percent of 100 snap to 100 when boost is available.
    static let snapRange = 3

    let maxValue: Int

    func fraction(_ percent: Int) -> CGFloat {
        CGFloat(percent) / CGFloat(max(maxValue, 1))
    }

    /// The percent at `position` (0 = silent end, 1 = max end), clamped, with the 100% snap.
    func percent(atPosition position: CGFloat) -> Int {
        let raw = min(max(Int((position * CGFloat(maxValue)).rounded()), 0), maxValue)
        if maxValue > 100, abs(raw - 100) <= Self.snapRange { return 100 }
        return raw
    }

    func nudged(_ value: Int, by delta: Int) -> Int {
        min(max(value + delta, 0), maxValue)
    }
}

/// Keyboard, scroll-wheel and VoiceOver behaviour shared by every fader:
/// arrow keys and scroll ±5% (Option + scroll in the list layouts), "<App> volume" slider with value "<N> percent".
struct VolumeControlBehavior: ViewModifier {
    let value: Int
    let scale: FaderScale
    let appName: String
    let onChange: (Int) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isMixerPreview) private var isPreview
    @Environment(\.mixerAppearance) private var appearance
    @Environment(\.stripHideAction) private var hideAction

    func body(content: Content) -> some View {
        content
            .focusable(isEnabled && !isPreview)
            .onKeyPress(.upArrow) {
                nudge(FaderScale.step); return .handled
            }
            .onKeyPress(.downArrow) {
                nudge(-FaderScale.step); return .handled
            }
            .onKeyPress(.rightArrow) {
                nudge(FaderScale.step); return .handled
            }
            .onKeyPress(.leftArrow) {
                nudge(-FaderScale.step); return .handled
            }
            .modifier(
                ScrollWheelStepper(requiresOption: appearance.scrollNeedsOption) { steps in
                    if isEnabled { nudge(steps * FaderScale.step) }
                }
            )
            .accessibilityElement()
            .accessibilityLabel(Text(L10n.volumeLabel(appName)))
            .accessibilityValue(Text(L10n.volumeValue(value)))
            .accessibilityAdjustableAction { direction in
                guard isEnabled else { return }
                switch direction {
                case .increment: nudge(FaderScale.step)
                case .decrement: nudge(-FaderScale.step)
                @unknown default: break
                }
            }
            .accessibilityActions {
                // The strip's "Hide <App>" context menu, which VoiceOver can't reach otherwise.
                if let hideAction, !isPreview {
                    Button(L10n.hideApp(hideAction.appName)) { hideAction.perform() }
                }
            }
    }

    private func nudge(_ delta: Int) {
        let newValue = scale.nudged(value, by: delta)
        if newValue != value { onChange(newValue) }
    }
}

extension View {
    func volumeControl(value: Int, maxValue: Int, appName: String, onChange: @escaping (Int) -> Void) -> some View {
        modifier(
            VolumeControlBehavior(
                value: value, scale: FaderScale(maxValue: maxValue), appName: appName, onChange: onChange))
    }
}

extension FaderScale {
    /// Option-click (or Option-drag) on any fader resets to 100%, like double-click.
    @MainActor static var isOptionHeld: Bool {
        NSEvent.modifierFlags.contains(.option)
    }
}

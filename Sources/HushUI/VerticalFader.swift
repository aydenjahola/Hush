import SwiftUI

/// Vertical volume fader: linear in percent, 100% tick, neutral fill to 100% then the boost accent.
/// The neutral fill is white in dark mode and near-black in light mode so it keeps at least
/// 3:1 contrast against the popover in both.
/// Drag, double-click the knob or Option-click to reset, scroll ±5%, arrow keys ±5%.
struct VerticalFader: View {
    let value: Int
    let maxValue: Int
    let appName: String
    let onChange: (Int) -> Void
    let onReset: () -> Void

    static let step = FaderScale.step
    private let knobSize = CGSize(width: 22, height: 10)

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.mixerAppearance) private var appearance

    private var scale: FaderScale { FaderScale(maxValue: maxValue) }

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let travel = max(height - knobSize.height, 1)
            let knobTop = (1 - scale.fraction(value)) * travel
            let unityCenter = (1 - scale.fraction(100)) * travel + knobSize.height / 2

            ZStack(alignment: .top) {
                track(height: height, travel: travel)
                if maxValue > 100 {
                    Rectangle()
                        .fill(Color.primary.opacity(contrast == .increased ? 0.6 : 0.35))
                        .frame(width: 14, height: 1)
                        .offset(y: unityCenter)
                }
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white)
                    .strokeBorder(knobBorder, lineWidth: contrast == .increased ? 1.5 : 1)
                    .frame(width: knobSize.width, height: knobSize.height)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.3), radius: 1.5, y: 1)
                    .offset(y: knobTop)
            }
            .frame(width: geometry.size.width, height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    guard isEnabled else { return }
                    if FaderScale.isOptionHeld {
                        if value != 100 { onReset() }
                        return
                    }
                    let position = 1 - (drag.location.y - knobSize.height / 2) / travel
                    let newValue = scale.percent(atPosition: position)
                    if newValue != value { onChange(newValue) }
                })
            .simultaneousGesture(
                SpatialTapGesture(count: 2).onEnded { tap in
                    guard isEnabled else { return }
                    if abs(tap.location.y - (knobTop + knobSize.height / 2)) <= 12 { onReset() }
                })
        }
        .frame(width: 28)
        .opacity(isEnabled ? 1 : 0.4)
        .volumeControl(value: value, maxValue: maxValue, appName: appName, onChange: onChange)
    }

    private func track(height: CGFloat, travel: CGFloat) -> some View {
        let unityFill = scale.fraction(min(value, 100)) * travel + knobSize.height / 2
        let totalFill = scale.fraction(value) * travel + knobSize.height / 2
        return ZStack(alignment: .bottom) {
            Capsule()
                .fill(Color.primary.opacity(contrast == .increased ? 0.3 : 0.12))
                .frame(width: 4, height: height)
            if value > 100 {
                Capsule().fill(Palette.boost(appearance.accent, colorScheme, contrast)).frame(width: 4, height: totalFill)
            }
            Capsule().fill(Palette.neutralFill(colorScheme, contrast)).frame(width: 4, height: unityFill)
        }
        .frame(height: height, alignment: .bottom)
    }

    /// The knob stays white; in light mode a dark edge separates it from the light background.
    private var knobBorder: Color {
        if colorScheme == .dark { return .clear }
        return contrast == .increased ? .black : .black.opacity(0.6)
    }
}

extension Palette {
    /// Fader fill up to 100%: white on dark, near-black on light (black with Increase Contrast).
    static func neutralFill(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast) -> Color {
        if scheme == .dark { return .white }
        return contrast == .increased ? .black : Color(white: 0.2)
    }
}

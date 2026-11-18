import SwiftUI

/// Horizontal volume slider for classic rows: 0…max%, a tinted boost zone past a 100% tick,
/// neutral fill to 100% then the boost accent. Same gestures as the vertical fader: drag,
/// double-click the knob or Option-click to reset, scroll and arrow keys ±5%.
struct HorizontalFader: View {
    let value: Int
    let maxValue: Int
    let appName: String
    let onChange: (Int) -> Void
    let onReset: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.mixerAppearance) private var appearance

    private var scale: FaderScale { FaderScale(maxValue: maxValue) }
    private var knob: CGFloat { appearance.isCompact ? 12 : 14 }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let travel = max(width - knob, 1)
            let knobCenter = scale.fraction(value) * travel + knob / 2
            let unityX = scale.fraction(100) * travel + knob / 2
            let boost = Palette.boost(colorScheme, contrast)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(contrast == .increased ? 0.3 : 0.12))
                    .frame(height: 4)
                if maxValue > 100 {
                    // The boost zone, faintly tinted so it reads as "past normal" before it's used.
                    Capsule()
                        .fill(boost.opacity(contrast == .increased ? 0.22 : (colorScheme == .dark ? 0.2 : 0.07)))
                        .frame(width: width - unityX, height: 4)
                        .offset(x: unityX)
                    if value > 100 {
                        Capsule().fill(boost).frame(width: knobCenter, height: 4)
                    }
                }
                Capsule()
                    .fill(Palette.level(appearance.accent, colorScheme, contrast))
                    .frame(width: min(knobCenter, unityX), height: 4)
                if maxValue > 100 {
                    Rectangle()
                        .fill(Color.primary.opacity(contrast == .increased ? 0.6 : 0.35))
                        .frame(width: 1, height: 10)
                        .offset(x: unityX - 0.5)
                }
                Circle()
                    .fill(Color.white)
                    .strokeBorder(knobBorder, lineWidth: contrast == .increased ? 1.5 : 1)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.3), radius: 1.5, y: 1)
                    .offset(x: knobCenter - knob / 2)
            }
            .frame(width: width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    guard isEnabled else { return }
                    if FaderScale.isOptionHeld {
                        if value != 100 { onReset() }
                        return
                    }
                    let newValue = scale.percent(atPosition: (drag.location.x - knob / 2) / travel)
                    if newValue != value { onChange(newValue) }
                })
            .simultaneousGesture(
                SpatialTapGesture(count: 2).onEnded { tap in
                    guard isEnabled else { return }
                    if abs(tap.location.x - knobCenter) <= 12 { onReset() }
                })
        }
        .frame(height: 18)
        .opacity(isEnabled ? 1 : 0.4)
        .volumeControl(value: value, maxValue: maxValue, appName: appName, onChange: onChange)
    }

    private var knobBorder: Color {
        if colorScheme == .dark { return .clear }
        return contrast == .increased ? .black : .black.opacity(0.6)
    }
}

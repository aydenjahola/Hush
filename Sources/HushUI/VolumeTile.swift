import HushCore
import SwiftUI

/// A row that is itself the slider: drag anywhere, the fill shows the volume and a soft green
/// glow the live level. Clicking the icon toggles mute; the trailing mute button does the same
/// for the keyboard and VoiceOver. Double-click or Option-click resets to 100%.
struct VolumeTile: View {
    let strip: MixerStore.Strip
    let meter: StripMeter
    let maxPercent: Int
    let isEnabled: Bool
    let actions: StripActions

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.mixerAppearance) private var appearance

    private var compact: Bool { appearance.isCompact }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous) }

    var body: some View {
        ZStack {
            // The slider: the whole tile surface, and the "<App> volume" accessibility element.
            TileSurface(strip: strip, meter: meter, maxPercent: maxPercent, isEnabled: isEnabled, actions: actions)
            HStack(spacing: compact ? 6 : 8) {
                StripIcon(strip: strip, size: compact ? 18 : 22)
                    .contentShape(Rectangle())
                    .onTapGesture { if isEnabled { actions.toggleMute() } }
                    .help(Text(strip.setting.isMuted ? L10n.clickToUnmute : L10n.clickToMute))
                Text(strip.displayName)
                    .font(compact ? .caption : .callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Spacer(minLength: 4)
                    .allowsHitTesting(false)
                if appearance.showPercentages || strip.setting.isMuted {
                    StripPercentLabel(strip: strip, boostInPrimary: true)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                MuteButton(isMuted: strip.setting.isMuted, appName: strip.displayName, compact: true,
                           action: actions.toggleMute)
            }
            .padding(.leading, compact ? 8 : 10)
            .padding(.trailing, compact ? 5 : 6)
        }
        .frame(height: compact ? 32 : 40)
        .clipShape(shape)
        .overlay {
            shape
                .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : 0.08))
                .allowsHitTesting(false)
        }
        .help(Text(verbatim: strip.displayName))
        .disabled(!isEnabled)
        .opacity(strip.isPlaying ? 1 : 0.45)
    }
}

/// The draggable fill behind a tile's labels.
private struct TileSurface: View {
    let strip: MixerStore.Strip
    let meter: StripMeter
    let maxPercent: Int
    let isEnabled: Bool
    let actions: StripActions

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.mixerAppearance) private var appearance

    private var scale: FaderScale { FaderScale(maxValue: maxPercent) }

    var body: some View {
        let value = strip.setting.percent
        let muted = strip.setting.isMuted
        let boost = Palette.boost(colorScheme, contrast)
        let level = Palette.systemAccentIfChosen(appearance.accent, colorScheme, contrast)
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Color.primary.opacity(contrast == .increased ? 0.12 : 0.05)
                if appearance.showMeters {
                    LevelGlow(meter: meter, isActive: strip.meterIsActive, increasedContrast: contrast == .increased)
                }
                (level.flatMap { muted ? nil : $0.opacity(contrast == .increased ? 0.4 : 0.28) }
                    ?? Color.primary.opacity(muted ? 0.06 : (contrast == .increased ? 0.24 : 0.13)))
                    .frame(width: width * scale.fraction(min(value, 100)))
                if value > 100 {
                    // Boost: the stretch past the 100% tick, in the accent colour.
                    boost.opacity(muted ? 0.12 : (contrast == .increased ? 0.5 : 0.32))
                        .frame(width: width * (scale.fraction(value) - scale.fraction(100)))
                        .offset(x: width * scale.fraction(100))
                }
                if value > 0 {
                    // The volume position: a crisp edge (at least 3:1 against the tile) so the level
                    // reads even where the fill and the meter glow are both soft.
                    Rectangle()
                        .fill(Color.primary.opacity(muted ? 0.3 : (contrast == .increased ? 0.9 : 0.65)))
                        .frame(width: 2)
                        .offset(x: max(width * scale.fraction(value) - 2, 0))
                }
                if maxPercent > 100 {
                    Rectangle()
                        .fill(Color.primary.opacity(contrast == .increased ? 0.5 : 0.22))
                        .frame(width: 1)
                        .padding(.vertical, 8)
                        .offset(x: width * scale.fraction(100) - 0.5)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    guard isEnabled else { return }
                    if FaderScale.isOptionHeld {
                        if value != 100 { actions.reset() }
                        return
                    }
                    let newValue = scale.percent(atPosition: drag.location.x / max(width, 1))
                    if newValue != value { actions.setPercent(newValue) }
                })
            .simultaneousGesture(TapGesture(count: 2).onEnded { if isEnabled { actions.reset() } })
        }
        .volumeControl(value: value, maxValue: maxPercent, appName: strip.displayName,
                       onChange: actions.setPercent)
    }
}

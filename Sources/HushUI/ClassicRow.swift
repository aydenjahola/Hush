import SwiftUI

/// Dense one-line layout, like Control Center: icon, name, horizontal slider with a thin live
/// meter under it, percent, mute button.
struct ClassicRow: View {
    let strip: MixerStore.Strip
    let meter: StripMeter
    let maxPercent: Int
    let isEnabled: Bool
    let actions: StripActions

    @Environment(\.mixerAppearance) private var appearance

    private var compact: Bool { appearance.isCompact }

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            StripIcon(strip: strip, size: compact ? 18 : 22)
            Text(strip.displayName)
                .font(compact ? .caption : .callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: compact ? 70 : 78, alignment: .leading)
                .help(Text(verbatim: strip.displayName))
            VStack(spacing: 1) {
                HorizontalFader(
                    value: strip.setting.percent,
                    maxValue: maxPercent,
                    appName: strip.displayName,
                    onChange: actions.setPercent,
                    onReset: actions.reset)
                if appearance.showMeters {
                    LevelMeter(meter: meter, axis: .horizontal, isActive: strip.meterIsActive)
                        .padding(.horizontal, compact ? 6 : 7)
                }
            }
            // Always 40 pt wide, so a row that gets muted keeps its slider where it was.
            ZStack(alignment: .trailing) {
                if appearance.showPercentages || strip.setting.isMuted {
                    StripPercentLabel(strip: strip)
                }
            }
            .frame(width: 40, alignment: .trailing)
            MuteButton(isMuted: strip.setting.isMuted, appName: strip.displayName, compact: true,
                       action: actions.toggleMute)
        }
        .padding(.vertical, compact ? 2 : 4)
        .disabled(!isEnabled)
        .opacity(strip.isPlaying ? 1 : 0.45)
    }
}

import SwiftUI

/// One app's column: percent, meter + fader, icon, name, mute button.
///
/// Holds no closures, only values, the meter object and `StripActions` (Equatable), so SwiftUI
/// can tell an unchanged strip is unchanged and skip it.
struct ChannelStrip: View {
    let strip: MixerStore.Strip
    let meter: StripMeter
    let maxPercent: Int
    let isEnabled: Bool
    let actions: StripActions

    @Environment(\.mixerAppearance) private var appearance

    private var compact: Bool { appearance.isCompact }

    var body: some View {
        let faderHeight: CGFloat = compact ? 104 : 130
        VStack(spacing: compact ? 5 : 8) {
            // The slot is always reserved, so a strip that gets muted doesn't push its fader down.
            ZStack {
                if appearance.showPercentages || strip.setting.isMuted {
                    StripPercentLabel(strip: strip)
                }
            }
            .frame(height: compact ? 14 : 16)
            HStack(alignment: .bottom, spacing: 4) {
                if appearance.showMeters {
                    LevelMeter(meter: meter, isActive: strip.meterIsActive)
                        .frame(height: faderHeight)
                }
                VerticalFader(
                    value: strip.setting.percent,
                    maxValue: maxPercent,
                    appName: strip.displayName,
                    onChange: actions.setPercent,
                    onReset: actions.reset)
                    .frame(height: faderHeight)
            }
            StripIcon(strip: strip, size: compact ? 26 : 34)
            Text(strip.displayName)
                .font(compact ? .caption2 : .caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .help(Text(verbatim: strip.displayName))
            MuteButton(isMuted: strip.setting.isMuted, appName: strip.displayName, compact: compact,
                       action: actions.toggleMute)
        }
        .frame(width: compact ? 60 : 72)
        .disabled(!isEnabled)
        .opacity(strip.isPlaying ? 1 : 0.45)
    }
}

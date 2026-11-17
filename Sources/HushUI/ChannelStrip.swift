import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One app's column: percent, meter + fader, icon, name, mute button.
struct ChannelStrip: View {
    let strip: MixerStore.Strip
    let meterLevel: Float?
    let maxPercent: Int
    let isEnabled: Bool
    let onPercentChange: (Int) -> Void
    let onReset: () -> Void
    let onToggleMute: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var isMuted: Bool { strip.setting.isMuted }

    var body: some View {
        VStack(spacing: 8) {
            percentLabel
            HStack(alignment: .bottom, spacing: 4) {
                LevelMeter(level: isMuted || !strip.isPlaying ? nil : (meterLevel ?? 0))
                    .frame(height: 130)
                VerticalFader(
                    value: strip.setting.percent,
                    maxValue: maxPercent,
                    appName: strip.displayName,
                    onChange: onPercentChange,
                    onReset: onReset)
                    .frame(height: 130)
            }
            icon
            Text(strip.displayName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .help(strip.displayName)
            MuteButton(isMuted: isMuted, appName: strip.displayName, action: onToggleMute)
        }
        .frame(width: 72)
        .disabled(!isEnabled)
        .opacity(strip.isPlaying ? 1 : 0.45)
    }

    @ViewBuilder
    private var percentLabel: some View {
        if isMuted {
            Text("Muted")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.mutedRed)
        } else {
            Text("\(strip.setting.percent)%")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(strip.setting.percent > 100 ? Palette.amber(colorScheme, contrast) : Color.primary)
        }
    }

    private var icon: some View {
        Image(nsImage: strip.icon ?? NSWorkspace.shared.icon(for: .application))
            .resizable()
            .interpolation(.high)
            .frame(width: 34, height: 34)
            .saturation(isMuted ? 0 : 1)
            .opacity(isMuted ? 0.5 : 1)
            .overlay(alignment: .topTrailing) {
                if let error = strip.engineError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 11))
                        .offset(x: 4, y: -4)
                        .help(error)
                        .accessibilityLabel("Warning: \(error)")
                }
            }
            .accessibilityHidden(strip.engineError == nil)
    }
}

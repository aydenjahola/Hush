import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Pieces shared by every layout, so channel strips, classic rows and tiles show the same state
/// the same way: icon with error badge and muted look, percent or "Muted" label.

/// Looked up once: `NSWorkspace.icon(for:)` isn't free and the fallback never changes.
@MainActor
enum FallbackAppIcon {
    static let image: NSImage = NSWorkspace.shared.icon(for: .application)
}

struct StripIcon: View {
    let strip: MixerStore.Strip
    let size: CGFloat

    private var isMuted: Bool { strip.setting.isMuted }

    var body: some View {
        Image(nsImage: strip.icon ?? FallbackAppIcon.image)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .saturation(isMuted ? 0 : 1)
            .opacity(isMuted ? 0.5 : 1)
            .overlay(alignment: .topTrailing) {
                if let error = strip.engineError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: size > 24 ? 11 : 9))
                        .offset(x: 4, y: -4)
                        .help(error)
                        .accessibilityLabel("Warning: \(error)")
                }
            }
            .accessibilityHidden(strip.engineError == nil)
    }
}

/// "62%" (boost in the accent colour) or "Muted" in red.
struct StripPercentLabel: View {
    let strip: MixerStore.Strip
    var font: Font = .caption.weight(.semibold)

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.mixerAppearance) private var appearance

    var body: some View {
        if strip.setting.isMuted {
            Text("Muted")
                .font(font)
                .foregroundStyle(Palette.mutedRed)
        } else {
            Text("\(strip.setting.percent)%")
                .font(font)
                .monospacedDigit()
                .foregroundStyle(strip.setting.percent > 100
                    ? Palette.boost(appearance.accent, colorScheme, contrast)
                    : Color.primary)
        }
    }
}

extension MixerStore.Strip {
    /// Whether its meter should show anything: playing and not muted.
    var meterIsActive: Bool { isPlaying && !setting.isMuted }
}

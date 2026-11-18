import HushCore
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
                        .help(Text(verbatim: error))
                        .accessibilityLabel(Text(L10n.warning(error)))
                }
            }
            .accessibilityHidden(strip.engineError == nil)
    }
}

/// "62%" (boost in amber) or "Muted" in red. `boostInPrimary` keeps the text in the primary
/// colour for places where amber text would sit on an amber fill (tiles).
struct StripPercentLabel: View {
    let strip: MixerStore.Strip
    var font: Font = .caption.weight(.semibold)
    var boostInPrimary = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if strip.setting.isMuted {
            Text(L10n.muted)
                .font(font)
                .foregroundStyle(Palette.mutedRed)
        } else {
            Text(L10n.percent(strip.setting.percent))
                .font(font)
                .monospacedDigit()
                .foregroundStyle(
                    strip.setting.percent > 100 && !boostInPrimary
                        ? Palette.boost(colorScheme, contrast)
                        : Color.primary)
        }
    }
}

/// The right-click menu every layout's strip shares: "Hide <App>". Not shown in the Settings
/// preview, whose sample strips aren't real apps.
struct StripContextMenu: ViewModifier {
    let strip: MixerStore.Strip
    let actions: StripActions

    @Environment(\.isMixerPreview) private var isPreview

    func body(content: Content) -> some View {
        if isPreview {
            content
        } else {
            content.contextMenu {
                Button(L10n.hideApp(strip.displayName)) {
                    actions.hide(displayName: strip.displayName)
                }
                .help(Text(L10n.hideAppHelp(strip.displayName)))
            }
        }
    }
}

extension View {
    /// Adds the shared strip context menu (see `StripContextMenu`).
    func stripContextMenu(_ strip: MixerStore.Strip, actions: StripActions) -> some View {
        modifier(StripContextMenu(strip: strip, actions: actions))
    }
}

extension MixerStore.Strip {
    /// Whether its meter should show anything: playing and not muted.
    var meterIsActive: Bool { isPlaying && !setting.isMuted }
}

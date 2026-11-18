import SwiftUI

/// 44×26 pt pill (34×22 compact). Red with a slashed speaker when muted.
struct MuteButton: View {
    let isMuted: Bool
    let appName: String
    var compact = false
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isMixerPreview) private var isPreview

    var body: some View {
        Button(action: action) {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: compact ? 10 : 12, weight: .semibold))
                .foregroundStyle(isMuted ? Color.white : Color.primary)
                .frame(width: compact ? 34 : 44, height: compact ? 22 : 26)
                .background(
                    Capsule().fill(
                        isMuted
                            ? Palette.mutedRed
                            : Color.primary.opacity(contrast == .increased ? 0.2 : 0.08))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(!isPreview)
        .allowsHitTesting(!isPreview)
        .accessibilityLabel(Text(isMuted ? L10n.unmute(appName) : L10n.mute(appName)))
    }
}

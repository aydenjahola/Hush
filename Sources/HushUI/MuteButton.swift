import SwiftUI

/// 44×26 pt pill. Red with a slashed speaker when muted.
struct MuteButton: View {
    let isMuted: Bool
    let appName: String
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isMuted ? Color.white : Color.primary)
                .frame(width: 44, height: 26)
                .background(
                    Capsule().fill(isMuted
                        ? Palette.mutedRed
                        : Color.primary.opacity(contrast == .increased ? 0.2 : 0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMuted ? "Unmute \(appName)" : "Mute \(appName)")
    }
}

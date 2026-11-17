import AppKit
import SwiftUI

struct PermissionBanner: View {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Hush needs Audio Recording access to control app volumes.", systemImage: "lock.shield")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") {
                NSWorkspace.shared.open(Self.settingsURL)
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.amberTint.opacity(0.15)))
    }
}

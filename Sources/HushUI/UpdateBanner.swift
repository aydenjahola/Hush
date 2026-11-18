import HushCore
import SwiftUI

/// Shown at the top of the popover while an update is pending (not snoozed or skipped).
struct UpdateBanner: View {
    let version: SemanticVersion
    let onDownload: () -> Void
    let onLater: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Hush \(version.description) is available", systemImage: "arrow.down.circle.fill")
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button("Download", action: onDownload)
                    .buttonStyle(.borderedProminent)
                    .help("Open the download in your browser")
                Button("Later", action: onLater)
                    .help("Remind me tomorrow")
                Button("Skip This Version", action: onSkip)
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.12)))
        .accessibilityElement(children: .contain)
    }
}

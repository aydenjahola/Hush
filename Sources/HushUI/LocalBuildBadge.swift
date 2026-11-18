import SwiftUI

/// "DEV" next to the app name in the popover of a build that isn't a downloaded release, so a
/// contributor can tell their `make install` copy from the one they downloaded.
struct LocalBuildBadge: View {
    let commit: String?

    var body: some View {
        Text(L10n.devBadge)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.orange))
            .fixedSize()
            .help(Text(commit.map(L10n.localBuildHelp) ?? L10n.localBuildHelpNoCommit))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(L10n.localBuild))
    }
}

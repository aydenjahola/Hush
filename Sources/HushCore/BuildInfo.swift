import Foundation

/// Where the running copy of Hush came from, read from keys `make app` writes into Info.plist.
///
/// The release workflow builds with `CHANNEL=release`; every other build (a `make app` on a
/// contributor's Mac, or the bare binary from Xcode with no Info.plist at all) is a local build,
/// so the popover and Settings can mark it and nobody mistakes it for a downloaded release.
package struct BuildInfo: Equatable, Sendable {
    package enum Channel: String, Sendable {
        case release
        case local
    }

    package static let channelKey = "HushBuildChannel"
    package static let commitKey = "HushBuildCommit"

    /// `CFBundleShortVersionString`, or nil for the bare binary.
    package let version: String?
    package let channel: Channel
    /// Short git commit the build came from, with `-dirty` when it had uncommitted changes.
    package let commit: String?

    package init(version: String?, channel: Channel, commit: String?) {
        self.version = version
        self.channel = channel
        self.commit = commit
    }

    /// Anything other than an explicit `release` channel counts as local.
    package init(infoDictionary: [String: Any]?) {
        let info = infoDictionary ?? [:]
        let commit = (info[Self.commitKey] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.init(
            version: info["CFBundleShortVersionString"] as? String,
            channel: (info[Self.channelKey] as? String) == Channel.release.rawValue ? .release : .local,
            commit: commit)
    }

    package var isLocal: Bool { channel == .local }

    package static let current = BuildInfo(infoDictionary: Bundle.main.infoDictionary)
}

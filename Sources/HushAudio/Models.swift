import AppKit
import CoreAudio

/// An app currently known to Core Audio, with its helper processes grouped in.
package struct AudioApp: Identifiable, Equatable {
    /// Bundle ID, or executable name when there is no bundle ID.
    package let id: String
    package var displayName: String
    package var icon: NSImage?
    /// Core Audio process objects for the app and its helpers, sorted.
    package var processObjectIDs: [AudioObjectID]
    package var isPlaying: Bool
    /// True when the owning app is a regular (Dock) app rather than a daemon, agent or CLI tool.
    package var isRegularApp: Bool

    package init(
        id: String,
        displayName: String,
        icon: NSImage? = nil,
        processObjectIDs: [AudioObjectID],
        isPlaying: Bool,
        isRegularApp: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.icon = icon
        self.processObjectIDs = processObjectIDs
        self.isPlaying = isPlaying
        self.isRegularApp = isRegularApp
    }

    /// Icons are ignored: they don't change identity or behavior.
    package static func == (lhs: AudioApp, rhs: AudioApp) -> Bool {
        lhs.id == rhs.id
            && lhs.displayName == rhs.displayName
            && lhs.processObjectIDs == rhs.processObjectIDs
            && lhs.isPlaying == rhs.isPlaying
            && lhs.isRegularApp == rhs.isRegularApp
    }
}

package struct OutputDevice: Equatable, Sendable {
    package let id: AudioObjectID
    package let uid: String
    package let name: String

    package init(id: AudioObjectID, uid: String, name: String) {
        self.id = id
        self.uid = uid
        self.name = name
    }
}

package enum EngineMode: Sendable, Equatable {
    /// The app is muted at the source and replayed with gain applied.
    case control
    /// The app plays normally; the tap only measures its level.
    case meterOnly
}

package enum AudioCapturePermissionStatus: Sendable, Equatable {
    case authorized
    case denied
    case undetermined
}

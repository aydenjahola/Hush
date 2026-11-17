import AppKit
import CoreAudio

/// An app currently known to Core Audio, with its helper processes grouped in.
public struct AudioApp: Identifiable, Equatable {
    /// Bundle ID, or executable name when there is no bundle ID.
    public let id: String
    public var displayName: String
    public var icon: NSImage?
    /// Core Audio process objects for the app and its helpers, sorted.
    public var processObjectIDs: [AudioObjectID]
    public var isPlaying: Bool

    public init(id: String, displayName: String, icon: NSImage? = nil, processObjectIDs: [AudioObjectID], isPlaying: Bool) {
        self.id = id
        self.displayName = displayName
        self.icon = icon
        self.processObjectIDs = processObjectIDs
        self.isPlaying = isPlaying
    }

    /// Icons are ignored: they don't change identity or behavior.
    public static func == (lhs: AudioApp, rhs: AudioApp) -> Bool {
        lhs.id == rhs.id
            && lhs.displayName == rhs.displayName
            && lhs.processObjectIDs == rhs.processObjectIDs
            && lhs.isPlaying == rhs.isPlaying
    }
}

public struct OutputDevice: Equatable, Sendable {
    public let id: AudioObjectID
    public let uid: String
    public let name: String

    public init(id: AudioObjectID, uid: String, name: String) {
        self.id = id
        self.uid = uid
        self.name = name
    }
}

public enum EngineMode: Sendable, Equatable {
    /// The app is muted at the source and replayed with gain applied.
    case control
    /// The app plays normally; the tap only measures its level.
    case meterOnly
}

public enum AudioCapturePermissionStatus: Sendable, Equatable {
    case authorized
    case denied
    case undetermined
}

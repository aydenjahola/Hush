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

package struct OutputDevice: Identifiable, Equatable, Sendable {
    package let id: AudioObjectID
    package let uid: String
    package let name: String
    package let transport: OutputTransport

    package init(id: AudioObjectID, uid: String, name: String, transport: OutputTransport = .other) {
        self.id = id
        self.uid = uid
        self.name = name
        self.transport = transport
    }

    /// Whether two reports name the same physical device: equal, non-empty UIDs. Object IDs
    /// aren't stable (a device can come back under a new one); the UID is what aggregates use.
    package static func isSameDevice(_ lhs: OutputDevice, _ rhs: OutputDevice) -> Bool {
        !lhs.uid.isEmpty && lhs.uid == rhs.uid
    }
}

/// How an output device is connected (`kAudioDevicePropertyTransportType`), refined by the
/// built-in device's data source where that tells speakers from headphones.
package enum OutputTransport: CaseIterable, Sendable, Equatable {
    case builtInSpeakers
    case builtInHeadphones
    /// Built in, but the data source doesn't say which (or there isn't one).
    case builtIn
    case bluetooth
    case usb
    case hdmi
    case displayPort
    case airPlay
    case thunderbolt
    case virtual
    case aggregate
    case other
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

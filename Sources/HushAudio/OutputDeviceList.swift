import CoreAudio
import Foundation

/// The raw facts about one Core Audio device that decide whether it belongs in the output picker.
package struct OutputDeviceCandidate: Equatable, Sendable {
    package var id: AudioObjectID
    package var uid: String
    package var name: String
    /// `kAudioDevicePropertyTransportType`.
    package var transportType: UInt32
    /// Output-scope `kAudioDevicePropertyDataSource`, read only for built-in devices.
    package var dataSource: UInt32?
    /// `kAudioDevicePropertyIsHidden`.
    package var isHidden: Bool
    /// Channels across the output-scope streams (`kAudioDevicePropertyStreamConfiguration`).
    package var outputChannels: Int

    package init(
        id: AudioObjectID,
        uid: String,
        name: String,
        transportType: UInt32,
        dataSource: UInt32? = nil,
        isHidden: Bool = false,
        outputChannels: Int
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.transportType = transportType
        self.dataSource = dataSource
        self.isHidden = isHidden
        self.outputChannels = outputChannels
    }
}

/// Pure rules for the output picker: which devices to list and how each is connected.
package enum OutputDeviceList {
    /// Built-in data sources (four-char codes; not exported by the Core Audio headers).
    package static let internalSpeakerDataSource: UInt32 = 0x6973_706B  // 'ispk'
    package static let headphonesDataSource: UInt32 = 0x6864_706E  // 'hdpn'

    /// The devices to offer, sorted by name: everything with output channels that isn't hidden and
    /// isn't one of Hush's own private aggregates. User-installed virtual devices (BlackHole…) stay.
    package static func outputs(
        from candidates: [OutputDeviceCandidate],
        excludingUIDPrefix prefix: String = AppAudioEngine.privateAggregateUIDPrefix
    ) -> [OutputDevice] {
        candidates
            .filter { !$0.isHidden && $0.outputChannels > 0 && !$0.uid.hasPrefix(prefix) }
            .map { OutputDevice(id: $0.id, uid: $0.uid, name: $0.name, transport: transport(for: $0)) }
            .sorted { lhs, rhs in
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
            }
    }

    package static func transport(for candidate: OutputDeviceCandidate) -> OutputTransport {
        transport(transportType: candidate.transportType, dataSource: candidate.dataSource)
    }

    package static func transport(transportType: UInt32, dataSource: UInt32?) -> OutputTransport {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            switch dataSource {
            case internalSpeakerDataSource: .builtInSpeakers
            case headphonesDataSource: .builtInHeadphones
            default: .builtIn
            }
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: .bluetooth
        case kAudioDeviceTransportTypeUSB: .usb
        case kAudioDeviceTransportTypeHDMI: .hdmi
        case kAudioDeviceTransportTypeDisplayPort: .displayPort
        case kAudioDeviceTransportTypeAirPlay: .airPlay
        case kAudioDeviceTransportTypeThunderbolt: .thunderbolt
        case kAudioDeviceTransportTypeVirtual: .virtual
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: .aggregate
        default: .other
        }
    }
}

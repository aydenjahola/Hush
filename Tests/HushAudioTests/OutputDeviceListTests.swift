import CoreAudio
import Testing

@testable import HushAudio

@Suite struct OutputDeviceListTests {
    private func device(
        _ id: AudioObjectID,
        _ name: String,
        uid: String? = nil,
        transport: UInt32 = kAudioDeviceTransportTypeUSB,
        hidden: Bool = false,
        channels: Int = 2
    ) -> OutputDeviceCandidate {
        OutputDeviceCandidate(
            id: id, uid: uid ?? "uid-\(id)", name: name, transportType: transport, isHidden: hidden,
            outputChannels: channels)
    }

    @Test func hushsPrivateAggregatesAreExcluded() {
        let outputs = OutputDeviceList.outputs(from: [
            device(1, "Speakers", transport: kAudioDeviceTransportTypeBuiltIn),
            device(
                2, "Hush – com.apple.Music", uid: "\(AppAudioEngine.privateAggregateUIDPrefix)1234",
                transport: kAudioDeviceTransportTypeAggregate),
        ])
        #expect(outputs.map(\.id) == [1])
    }

    @Test func thePrefixIsHushsAggregateNamespace() {
        #expect(AppAudioEngine.privateAggregateUIDPrefix == "io.github.aydenjahola.Hush.aggregate.")
    }

    @Test func aUserAggregateIsKept() {
        let outputs = OutputDeviceList.outputs(from: [
            device(3, "Studio Aggregate", uid: "com.example.aggregate", transport: kAudioDeviceTransportTypeAggregate)
        ])
        #expect(outputs.map(\.transport) == [.aggregate])
    }

    @Test func hiddenDevicesAreExcluded() {
        let outputs = OutputDeviceList.outputs(from: [device(1, "Visible"), device(2, "Hidden", hidden: true)])
        #expect(outputs.map(\.name) == ["Visible"])
    }

    @Test func inputOnlyDevicesAreExcluded() {
        let outputs = OutputDeviceList.outputs(from: [
            device(1, "Headphones"), device(2, "MacBook Pro Microphone", channels: 0),
        ])
        #expect(outputs.map(\.name) == ["Headphones"])
    }

    @Test func virtualDevicesSuchAsBlackHoleAreKept() {
        let outputs = OutputDeviceList.outputs(from: [
            device(7, "BlackHole 2ch", uid: "BlackHole2ch_UID", transport: kAudioDeviceTransportTypeVirtual)
        ])
        #expect(outputs == [OutputDevice(id: 7, uid: "BlackHole2ch_UID", name: "BlackHole 2ch", transport: .virtual)])
    }

    @Test func everyDeviceIsWatchedForStreamChangesIncludingFilteredOnes() {
        let watched = OutputDeviceList.watchedProperties(for: [
            device(1, "MacBook Pro Speakers", transport: kAudioDeviceTransportTypeBuiltIn),
            device(2, "AirPods Pro", transport: kAudioDeviceTransportTypeBluetooth, channels: 0),  // still connecting
            device(3, "Hidden", hidden: true),
            device(4, "Hush – Music", uid: "\(AppAudioEngine.privateAggregateUIDPrefix)x", channels: 2),
        ])
        #expect(watched[1] == [.streamConfiguration, .name, .dataSource])
        #expect(watched[2] == [.streamConfiguration])
        #expect(watched[3] == [.streamConfiguration])
        #expect(watched[4] == nil)
    }

    @Test func aDeviceThatGainsOutputChannelsIsListedOnTheNextRefresh() {
        var airPods = device(2, "AirPods Pro", transport: kAudioDeviceTransportTypeBluetooth, channels: 0)
        #expect(OutputDeviceList.outputs(from: [airPods]).isEmpty)
        airPods.outputChannels = 2
        #expect(OutputDeviceList.outputs(from: [airPods]).map(\.id) == [2])
        #expect(OutputDeviceList.watchedProperties(for: [airPods])[2] == [.streamConfiguration, .name])
    }

    @Test func devicesAreSortedByName() {
        let outputs = OutputDeviceList.outputs(from: [
            device(1, "USB DAC"), device(2, "AirPods Pro"), device(3, "MacBook Pro Speakers"),
        ])
        #expect(outputs.map(\.name) == ["AirPods Pro", "MacBook Pro Speakers", "USB DAC"])
    }

    @Test(arguments: [
        (kAudioDeviceTransportTypeBluetooth, OutputTransport.bluetooth),
        (kAudioDeviceTransportTypeBluetoothLE, .bluetooth),
        (kAudioDeviceTransportTypeUSB, .usb),
        (kAudioDeviceTransportTypeHDMI, .hdmi),
        (kAudioDeviceTransportTypeDisplayPort, .displayPort),
        (kAudioDeviceTransportTypeAirPlay, .airPlay),
        (kAudioDeviceTransportTypeThunderbolt, .thunderbolt),
        (kAudioDeviceTransportTypeVirtual, .virtual),
        (kAudioDeviceTransportTypeAggregate, .aggregate),
        (kAudioDeviceTransportTypeAutoAggregate, .aggregate),
        (kAudioDeviceTransportTypePCI, .other),
        (0, .other),
    ])
    func transportTypeMapsToTransport(type: UInt32, expected: OutputTransport) {
        #expect(OutputDeviceList.transport(transportType: type, dataSource: nil) == expected)
    }

    @Test func builtInDataSourceTellsSpeakersFromHeadphones() {
        let builtIn = kAudioDeviceTransportTypeBuiltIn
        #expect(
            OutputDeviceList.transport(transportType: builtIn, dataSource: OutputDeviceList.internalSpeakerDataSource)
                == .builtInSpeakers)
        #expect(
            OutputDeviceList.transport(transportType: builtIn, dataSource: OutputDeviceList.headphonesDataSource)
                == .builtInHeadphones)
        #expect(OutputDeviceList.transport(transportType: builtIn, dataSource: nil) == .builtIn)
        // A data source only refines built-in devices.
        #expect(
            OutputDeviceList.transport(
                transportType: kAudioDeviceTransportTypeUSB, dataSource: OutputDeviceList.headphonesDataSource)
                == .usb)
    }
}

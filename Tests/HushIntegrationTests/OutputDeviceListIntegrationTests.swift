import CoreAudio
import HushAudio
import Testing

/// Read-only checks of the output picker's device list against the real HAL. They never create a
/// tap or change the default output device.
@MainActor
@Suite("Output device list") struct OutputDeviceListIntegrationTests {
    @Test(.enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
    func listsTheDefaultOutputAndNoHushAggregates() throws {
        let monitor = DefaultOutputMonitor()
        let devices = monitor.availableDevices()
        let current = try #require(monitor.current(), "no default output device")
        #expect(devices.contains { $0.id == current.id }, "the default output \(current.name) isn't listed")
        #expect(!devices.contains { $0.uid.hasPrefix(AppAudioEngine.privateAggregateUIDPrefix) })
        #expect(Set(devices.map(\.id)).count == devices.count)
    }

    @Test(.enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
    func observingPublishesTheListImmediately() {
        let monitor = DefaultOutputMonitor()
        var lists: [[OutputDevice]] = []
        monitor.observeDevices { lists.append($0) }
        #expect(lists.count == 1)
        #expect(lists.first == monitor.availableDevices())
    }
}

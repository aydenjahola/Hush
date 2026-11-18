import CoreAudio
import Foundation
import HushCore
import os

/// Tracks the system default output device and the devices the user can pick instead.
@MainActor
package final class DefaultOutputMonitor: OutputDeviceSource {
    private var onChange: (@MainActor (OutputDevice?) -> Void)?
    private var listener: AudioObjectPropertyListenerBlock?
    private var lastPublished: OutputDevice?
    private let logger = Logger(subsystem: HushIdentity.bundleID, category: "output")

    private var onDevicesChange: (@MainActor ([OutputDevice]) -> Void)?
    private var devicesListener: AudioObjectPropertyListenerBlock?
    private var lastDevices: [OutputDevice]?
    /// Per-device name (and built-in data source) listeners, so renames and headphone jacks show live.
    private var deviceListeners: [AudioObjectID: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)]] =
        [:]

    package init() {}

    package func start(onChange: @escaping @MainActor (OutputDevice?) -> Void) {
        self.onChange = onChange
        var propertyAddress = CoreAudioProperty.address(kAudioHardwarePropertyDefaultOutputDevice)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.publish() }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            CoreAudioProperty.systemObject, &propertyAddress, DispatchQueue.main, block)
        if status == noErr {
            listener = block
        } else {
            logger.error("Could not observe default output (OSStatus \(status))")
        }
        lastPublished = current()
        onChange(lastPublished)
    }

    package func current() -> OutputDevice? {
        guard
            let id = try? CoreAudioProperty.scalar(
                CoreAudioProperty.systemObject,
                kAudioHardwarePropertyDefaultOutputDevice,
                initial: AudioObjectID(kAudioObjectUnknown)),
            id != kAudioObjectUnknown
        else { return nil }
        let candidate = Self.candidate(id)
        return OutputDevice(
            id: id, uid: candidate.uid, name: candidate.name.isEmpty ? "Output" : candidate.name,
            transport: OutputDeviceList.transport(for: candidate))
    }

    private func publish() {
        let device = current()
        guard device != lastPublished else { return }
        lastPublished = device
        onChange?(device)
    }

    // MARK: Device list

    package func observeDevices(onChange: @escaping @MainActor ([OutputDevice]) -> Void) {
        onDevicesChange = onChange
        var propertyAddress = CoreAudioProperty.address(kAudioHardwarePropertyDevices)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshDevices() }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            CoreAudioProperty.systemObject, &propertyAddress, DispatchQueue.main, block)
        if status == noErr {
            devicesListener = block
        } else {
            logger.error("Could not observe the device list (OSStatus \(status))")
        }
        refreshDevices()
    }

    /// The pickable output devices right now.
    package func availableDevices() -> [OutputDevice] {
        let ids =
            (try? CoreAudioProperty.array(
                CoreAudioProperty.systemObject, kAudioHardwarePropertyDevices, filler: AudioObjectID(0))) ?? []
        return OutputDeviceList.outputs(from: ids.map(Self.candidate))
    }

    package func setDefaultOutput(_ id: AudioObjectID) throws {
        var propertyAddress = CoreAudioProperty.address(kAudioHardwarePropertyDefaultOutputDevice)
        var value = id
        try CoreAudioProperty.check(
            AudioObjectSetPropertyData(
                CoreAudioProperty.systemObject, &propertyAddress, 0, nil,
                UInt32(MemoryLayout<AudioObjectID>.size), &value),
            "Setting the default output device")
    }

    private func refreshDevices() {
        let devices = availableDevices()
        updateDeviceListeners(for: devices)
        guard devices != lastDevices else { return }
        lastDevices = devices
        onDevicesChange?(devices)
    }

    /// A listed device's name or data source changed: refresh the list, and the header pill if
    /// it's the default (`publish` only reports a real change, and a same-ID change never rebuilds).
    private func deviceDidChange() {
        refreshDevices()
        publish()
    }

    private func updateDeviceListeners(for devices: [OutputDevice]) {
        let wanted = Dictionary(devices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, listeners) in deviceListeners where wanted[id] == nil {
            for (address, block) in listeners {
                var address = address
                // The device may already be gone, in which case there's nothing left to remove.
                _ = AudioObjectRemovePropertyListenerBlock(id, &address, DispatchQueue.main, block)
            }
            deviceListeners[id] = nil
        }
        for (id, device) in wanted where deviceListeners[id] == nil {
            var addresses = [CoreAudioProperty.address(kAudioObjectPropertyName)]
            if [.builtIn, .builtInSpeakers, .builtInHeadphones].contains(device.transport) {
                addresses.append(
                    CoreAudioProperty.address(kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput))
            }
            var added: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
            for address in addresses {
                var address = address
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.deviceDidChange() }
                }
                if AudioObjectAddPropertyListenerBlock(id, &address, DispatchQueue.main, block) == noErr {
                    added.append((address, block))
                }
            }
            deviceListeners[id] = added
        }
    }

    /// Reads what the picker needs about one device. Unreadable properties fall back to values
    /// that exclude the device (no output channels) or describe it generically.
    private static func candidate(_ id: AudioObjectID) -> OutputDeviceCandidate {
        let transportType =
            (try? CoreAudioProperty.scalar(id, kAudioDevicePropertyTransportType, initial: UInt32(0))) ?? 0
        let dataSource: UInt32? =
            transportType == kAudioDeviceTransportTypeBuiltIn
            ? try? CoreAudioProperty.scalar(
                id, kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput, initial: UInt32(0))
            : nil
        return OutputDeviceCandidate(
            id: id,
            uid: (try? CoreAudioProperty.string(id, kAudioDevicePropertyDeviceUID)) ?? "",
            name: (try? CoreAudioProperty.string(id, kAudioObjectPropertyName)) ?? "",
            transportType: transportType,
            dataSource: dataSource,
            isHidden: ((try? CoreAudioProperty.scalar(id, kAudioDevicePropertyIsHidden, initial: UInt32(0))) ?? 0) != 0,
            outputChannels: (try? CoreAudioProperty.channelCount(id, scope: kAudioObjectPropertyScopeOutput)) ?? 0)
    }
}

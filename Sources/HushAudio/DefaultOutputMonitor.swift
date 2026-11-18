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
    /// Per-device listeners (see `OutputDeviceList.watchedProperties`), so hotplugged devices that
    /// gain streams late, renames and headphone jacks all show live.
    private var deviceListeners: [AudioObjectID: [OutputDeviceList.WatchedProperty: AudioObjectPropertyListenerBlock]] =
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
        OutputDeviceList.outputs(from: currentCandidates())
    }

    /// Every device the HAL knows about, pickable or not.
    private func currentCandidates() -> [OutputDeviceCandidate] {
        let ids =
            (try? CoreAudioProperty.array(
                CoreAudioProperty.systemObject, kAudioHardwarePropertyDevices, filler: AudioObjectID(0))) ?? []
        return ids.map(Self.candidate)
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
        let candidates = currentCandidates()
        updateDeviceListeners(OutputDeviceList.watchedProperties(for: candidates))
        let devices = OutputDeviceList.outputs(from: candidates)
        guard devices != lastDevices else { return }
        lastDevices = devices
        onDevicesChange?(devices)
    }

    /// A device's streams, name or data source changed: refresh the list, and the header pill if
    /// it's the default (`publish` only reports a real change, and a same-ID change never rebuilds).
    private func deviceDidChange() {
        refreshDevices()
        publish()
    }

    /// Adds and removes per-device listeners so exactly `wanted` is watched. Removal errors are
    /// ignored: a vanished device has nothing left to remove.
    private func updateDeviceListeners(_ wanted: [AudioObjectID: Set<OutputDeviceList.WatchedProperty>]) {
        for (id, listeners) in deviceListeners {
            let keep = wanted[id] ?? []
            for (property, block) in listeners where !keep.contains(property) {
                var address = Self.address(property)
                _ = AudioObjectRemovePropertyListenerBlock(id, &address, DispatchQueue.main, block)
                deviceListeners[id]?[property] = nil
            }
            if deviceListeners[id]?.isEmpty == true { deviceListeners[id] = nil }
        }
        for (id, properties) in wanted {
            for property in properties where deviceListeners[id]?[property] == nil {
                var address = Self.address(property)
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.deviceDidChange() }
                }
                if AudioObjectAddPropertyListenerBlock(id, &address, DispatchQueue.main, block) == noErr {
                    deviceListeners[id, default: [:]][property] = block
                }
            }
        }
    }

    private static func address(_ property: OutputDeviceList.WatchedProperty) -> AudioObjectPropertyAddress {
        switch property {
        case .streamConfiguration:
            CoreAudioProperty.address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeOutput)
        case .name:
            CoreAudioProperty.address(kAudioObjectPropertyName)
        case .dataSource:
            CoreAudioProperty.address(kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput)
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

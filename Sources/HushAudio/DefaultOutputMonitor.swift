import CoreAudio
import Foundation
import HushCore
import os

/// Tracks the system default output device.
@MainActor
public final class DefaultOutputMonitor: OutputDeviceSource {
    private var onChange: (@MainActor (OutputDevice?) -> Void)?
    private var listener: AudioObjectPropertyListenerBlock?
    private var lastPublished: OutputDevice?
    private let logger = Logger(subsystem: HushIdentity.bundleID, category: "output")

    public init() {}

    public func start(onChange: @escaping @MainActor (OutputDevice?) -> Void) {
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

    public func current() -> OutputDevice? {
        guard let id = try? CoreAudioProperty.scalar(
            CoreAudioProperty.systemObject,
            kAudioHardwarePropertyDefaultOutputDevice,
            initial: AudioObjectID(kAudioObjectUnknown)),
            id != kAudioObjectUnknown
        else { return nil }
        let uid = (try? CoreAudioProperty.string(id, kAudioDevicePropertyDeviceUID)) ?? ""
        let name = (try? CoreAudioProperty.string(id, kAudioObjectPropertyName)) ?? "Output"
        return OutputDevice(id: id, uid: uid, name: name)
    }

    private func publish() {
        let device = current()
        guard device != lastPublished else { return }
        lastPublished = device
        onChange?(device)
    }
}

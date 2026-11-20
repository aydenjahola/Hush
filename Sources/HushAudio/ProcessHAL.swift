import CoreAudio
import Foundation

/// A registered property listener, for `ProcessHAL.removeListener`.
struct HALListener {
    let object: AudioObjectID
    let selector: AudioObjectPropertySelector
    let block: AudioObjectPropertyListenerBlock?
}

/// The Core Audio reads and listeners `AudioProcessMonitor` uses, so tests can script and count them.
/// Every call is a synchronous round trip to coreaudiod (53–204 µs measured), so callers read as little as they can.
@MainActor
protocol ProcessHAL: AnyObject {
    func processObjects() throws -> [AudioObjectID]
    func pid(of object: AudioObjectID) -> pid_t?
    /// Nil when the process has no bundle ID; throws when the read itself failed.
    func bundleID(of object: AudioObjectID) throws -> String?
    func isRunningOutput(_ object: AudioObjectID) -> Bool
    /// Whether the process is capturing audio input (a microphone). No extra permission needed.
    func isRunningInput(_ object: AudioObjectID) -> Bool
    /// Calls `handler` on the main queue whenever `selector` changes on `object`. Nil if the HAL refused.
    func addListener(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ handler: @escaping @MainActor () -> Void
    ) -> HALListener?
    func removeListener(_ listener: HALListener)
}

@MainActor
final class CoreAudioProcessHAL: ProcessHAL {
    func processObjects() throws -> [AudioObjectID] {
        try CoreAudioProperty.array(
            CoreAudioProperty.systemObject,
            kAudioHardwarePropertyProcessObjectList,
            filler: AudioObjectID(kAudioObjectUnknown))
    }

    func pid(of object: AudioObjectID) -> pid_t? {
        try? CoreAudioProperty.scalar(object, kAudioProcessPropertyPID, initial: pid_t(0))
    }

    func bundleID(of object: AudioObjectID) throws -> String? {
        let raw = try CoreAudioProperty.string(object, kAudioProcessPropertyBundleID)
        return raw.isEmpty ? nil : raw
    }

    func isRunningOutput(_ object: AudioObjectID) -> Bool {
        let value =
            (try? CoreAudioProperty.scalar(object, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0))) ?? 0
        return value != 0
    }

    func isRunningInput(_ object: AudioObjectID) -> Bool {
        let value =
            (try? CoreAudioProperty.scalar(object, kAudioProcessPropertyIsRunningInput, initial: UInt32(0))) ?? 0
        return value != 0
    }

    func addListener(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ handler: @escaping @MainActor () -> Void
    ) -> HALListener? {
        var propertyAddress = CoreAudioProperty.address(selector)
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { handler() }
        }
        guard AudioObjectAddPropertyListenerBlock(object, &propertyAddress, DispatchQueue.main, block) == noErr else {
            return nil
        }
        return HALListener(object: object, selector: selector, block: block)
    }

    func removeListener(_ listener: HALListener) {
        guard let block = listener.block else { return }
        var propertyAddress = CoreAudioProperty.address(listener.selector)
        AudioObjectRemovePropertyListenerBlock(listener.object, &propertyAddress, DispatchQueue.main, block)
    }
}

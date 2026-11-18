import CoreAudio
import Foundation

package struct CoreAudioError: Error, CustomStringConvertible, Sendable {
    package let operation: String
    package let status: OSStatus

    package var description: String { "\(operation) failed (OSStatus \(status))" }
}

/// Small helpers for reading Core Audio object properties. Main-thread use only, never in an IOProc.
enum CoreAudioProperty {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw CoreAudioError(operation: operation, status: status) }
    }

    static func scalar<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T) throws -> T {
        var propertyAddress = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        var value = initial
        try withUnsafeMutablePointer(to: &value) { pointer in
            try check(
                AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, pointer),
                "Reading property \(selector)")
        }
        return value
    }

    static func array<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, filler: T) throws -> [T] {
        var propertyAddress = address(selector)
        var size: UInt32 = 0
        try check(
            AudioObjectGetPropertyDataSize(object, &propertyAddress, 0, nil, &size),
            "Sizing property \(selector)")
        let count = Int(size) / MemoryLayout<T>.stride
        guard count > 0 else { return [] }
        var values = [T](repeating: filler, count: count)
        try values.withUnsafeMutableBytes { raw in
            try check(
                AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, raw.baseAddress!),
                "Reading property \(selector)")
        }
        return Array(values.prefix(Int(size) / MemoryLayout<T>.stride))
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var propertyAddress = address(selector)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        try withUnsafeMutablePointer(to: &value) { pointer in
            try check(
                AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, pointer),
                "Reading string property \(selector)")
        }
        return (value?.takeRetainedValue() as String?) ?? ""
    }

    /// Number of input streams (one IOProc buffer each) on a device. A device with no inputs gives 0.
    static func inputStreamCount(_ device: AudioObjectID) throws -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        try check(
            AudioObjectGetPropertyDataSize(device, &propertyAddress, 0, nil, &size),
            "Sizing stream configuration")
        guard size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        try check(
            AudioObjectGetPropertyData(device, &propertyAddress, 0, nil, &size, raw),
            "Reading stream configuration")
        return Int(raw.assumingMemoryBound(to: AudioBufferList.self).pointee.mNumberBuffers)
    }
}

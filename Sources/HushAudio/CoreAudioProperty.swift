import CoreAudio
import Foundation

public struct CoreAudioError: Error, CustomStringConvertible, Sendable {
    public let operation: String
    public let status: OSStatus

    public var description: String { "\(operation) failed (OSStatus \(status))" }
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
}

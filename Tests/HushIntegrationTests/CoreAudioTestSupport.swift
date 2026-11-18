import CoreAudio
import Foundation
import HushCore
@testable import HushAudio

/// Read-only Core Audio queries the integration tests need. Main thread only.
@MainActor
enum AudioDevices {
    static func allDeviceIDs() -> [AudioObjectID] {
        (try? CoreAudioProperty.array(
            CoreAudioProperty.systemObject, kAudioHardwarePropertyDevices,
            filler: AudioObjectID(kAudioObjectUnknown))) ?? []
    }

    static func uid(of device: AudioObjectID) -> String? {
        try? CoreAudioProperty.string(device, kAudioDevicePropertyDeviceUID)
    }

    static func name(of device: AudioObjectID) -> String? {
        try? CoreAudioProperty.string(device, kAudioObjectPropertyName)
    }

    /// BlackHole 2ch, found by name or by its well-known UID.
    static func blackHole() -> OutputDevice? {
        for device in allDeviceIDs() {
            let uid = uid(of: device) ?? ""
            let name = name(of: device) ?? ""
            if name.contains("BlackHole 2ch") || uid == "BlackHole2ch_UID" {
                return OutputDevice(id: device, uid: uid, name: name)
            }
        }
        return nil
    }

    static func defaultOutput() -> OutputDevice? {
        DefaultOutputMonitor().current()
    }

    /// UIDs of Hush aggregate devices visible to this process. They're private, so only the
    /// test process's own aggregates show up, never a running Hush.app's.
    static func hushAggregateUIDs() -> [String] {
        let prefix = HushIdentity.bundleID + ".aggregate"
        return allDeviceIDs().compactMap(uid(of:)).filter { $0.hasPrefix(prefix) }
    }

    /// Process taps visible to this process, or nil if the HAL won't list them.
    static func tapIDs() -> [AudioObjectID]? {
        try? CoreAudioProperty.array(
            CoreAudioProperty.systemObject, kAudioHardwarePropertyTapList,
            filler: AudioObjectID(kAudioObjectUnknown))
    }

    /// The Core Audio process object for a PID, or nil until that process has talked to the HAL.
    static func processObject(forPID pid: pid_t) -> AudioObjectID? {
        var address = CoreAudioProperty.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var qualifier = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            CoreAudioProperty.systemObject, &address,
            UInt32(MemoryLayout<pid_t>.size), &qualifier, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    static func isRunningOutput(_ processObject: AudioObjectID) -> Bool {
        ((try? CoreAudioProperty.scalar(processObject, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0))) ?? 0)
            != 0
    }

    static func nominalSampleRate(_ device: AudioObjectID) -> Double {
        (try? CoreAudioProperty.scalar(device, kAudioDevicePropertyNominalSampleRate, initial: Float64(0))) ?? 0
    }

    static func bufferFrameSize(_ device: AudioObjectID) -> Int {
        Int((try? CoreAudioProperty.scalar(device, kAudioDevicePropertyBufferFrameSize, initial: UInt32(0))) ?? 0)
    }
}

/// The output device a test plays to and points engines at: BlackHole when installed (silent),
/// otherwise the default output with the tone kept very quiet.
@MainActor
struct TestOutput {
    let device: OutputDevice
    let isBlackHole: Bool

    /// Tone level for engine-level tests: -12 dBFS into BlackHole, -60 dBFS on real speakers.
    var quietLevel: Double { isBlackHole ? -12 : -60 }

    static func resolve() throws -> TestOutput {
        if let blackHole = AudioDevices.blackHole() { return TestOutput(device: blackHole, isBlackHole: true) }
        guard let output = AudioDevices.defaultOutput() else { throw IntegrationError("No default output device") }
        return TestOutput(device: output, isBlackHole: false)
    }
}

struct IntegrationError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: Levels

func dBFS(_ linear: Float) -> Float {
    20 * log10(max(linear, 1e-12))
}

func linear(dB: Double) -> Float {
    Float(pow(10, dB / 20))
}

/// RMS of a full-scale-peak sine with the given peak level.
func sineRMS(peakDB: Double) -> Float {
    linear(dB: peakDB) / Float(2).squareRoot()
}

func median(_ values: [Float]) -> Float {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

// MARK: Waiting

/// Polls `condition` until it's true or `timeout` passes. Returns whether it became true.
/// Tests wait on conditions with a deadline instead of fixed sleeps.
@MainActor
@discardableResult
func waitUntil(
    timeout: Duration,
    interval: Duration = .milliseconds(10),
    _ condition: @MainActor () throws -> Bool
) async rethrows -> Bool {
    let deadline = ContinuousClock.now + timeout
    while true {
        if try condition() { return true }
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: interval)
    }
}

/// Samples `engine.currentPeak()` for `duration` and returns the non-zero readings.
@MainActor
func collectPeaks(_ engine: any AudioEngineHandle, for duration: Duration, every interval: Duration = .milliseconds(20))
    async -> [Float]
{
    _ = engine.currentPeak()  // drop whatever accumulated before
    var peaks: [Float] = []
    let deadline = ContinuousClock.now + duration
    while ContinuousClock.now < deadline {
        try? await Task.sleep(for: interval)
        let peak = engine.currentPeak()
        if peak > 0 { peaks.append(peak) }
    }
    return peaks
}

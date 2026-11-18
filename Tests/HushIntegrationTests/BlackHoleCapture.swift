import CoreAudio
import Foundation
import Synchronization
@testable import HushAudio

/// Records BlackHole's input side, which is a loopback of everything played to its output.
/// Keeps the left channel of the last ~40 s in a preallocated ring buffer.
@MainActor
final class BlackHoleCapture {
    let device: AudioObjectID
    let sampleRate: Double
    /// Frames per IO cycle: one buffer, the unit for "gap" checks.
    let bufferFrameSize: Int
    private let ring: CaptureRing
    private var ioProcID: AudioDeviceIOProcID?

    init(device: AudioObjectID) {
        self.device = device
        let rate = AudioDevices.nominalSampleRate(device)
        self.sampleRate = rate > 0 ? rate : 48_000
        let frames = AudioDevices.bufferFrameSize(device)
        self.bufferFrameSize = frames > 0 ? frames : 512
        self.ring = CaptureRing(capacity: 1 << 21)
    }

    func start() throws {
        guard ioProcID == nil else { return }
        try Self.requireFloat32Input(device: device)
        let ring = self.ring
        var procID: AudioDeviceIOProcID?
        try CoreAudioProperty.check(
            AudioDeviceCreateIOProcIDWithBlock(&procID, device, nil, Self.makeIOBlock(ring: ring)),
            "AudioDeviceCreateIOProcIDWithBlock (capture)")
        ioProcID = procID
        Self.disableOutputStreams(device: device, procID: procID)
        do {
            try CoreAudioProperty.check(AudioDeviceStart(device, procID), "AudioDeviceStart (capture)")
        } catch {
            stop()
            throw error
        }
    }

    /// Built outside the main actor so the block isn't main-actor isolated: it runs on the HAL thread.
    nonisolated private static func makeIOBlock(ring: CaptureRing) -> AudioDeviceIOBlock {
        return { _, inputData, _, outputData, _ in
            let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            if input.count > 0 {
                let buffer = input[0]
                let channels = max(Int(buffer.mNumberChannels), 1)
                if let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                    let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
                    ring.append(data, frames: frames, stride: channels)
                }
            }
            for buffer in UnsafeMutableAudioBufferListPointer(outputData) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
        }
    }

    func stop() {
        guard let ioProcID else { return }
        AudioDeviceStop(device, ioProcID)
        AudioDeviceDestroyIOProcID(device, ioProcID)
        self.ioProcID = nil
    }

    /// Total frames captured so far. Use as a mark, then read `samples(from:)`.
    var frameCount: Int { ring.frameCount }

    /// Exactly the frames `start..<end`. Throws if any of them aren't there: not captured yet, or
    /// already overwritten. A missing readback must never look like silence.
    func samples(from start: Int, to end: Int? = nil) throws -> [Float] {
        let end = end ?? ring.frameCount
        guard end > start else { throw IntegrationError("Empty capture range \(start)..<\(end)") }
        guard let samples = ring.samples(from: start, to: end) else {
            throw IntegrationError("Capture frames \(start)..<\(end) aren't available (captured so far: \(ring.frameCount), ring holds \(ring.capacity)): not arrived yet or overrun")
        }
        return samples
    }

    func frames(for duration: Duration) -> Int {
        Int(Double(duration.components.seconds) * sampleRate + Double(duration.components.attoseconds) * 1e-18 * sampleRate)
    }

    /// Waits until `duration` of new audio has arrived and returns it.
    func record(_ duration: Duration) async throws -> [Float] {
        let start = frameCount
        let needed = frames(for: duration)
        let arrived = await waitUntil(timeout: duration + .seconds(2)) { self.frameCount >= start + needed }
        guard arrived else { throw IntegrationError("BlackHole capture stalled (no audio arriving from its input)") }
        return try samples(from: start, to: start + needed)
    }

    /// RMS of the most recent `duration` of capture. Throws if that much hasn't been captured yet.
    func recentRMS(_ duration: Duration) throws -> Float {
        let end = frameCount
        return rms(try samples(from: end - frames(for: duration), to: end))
    }

    /// The recent level as text for failure messages.
    func recentLevel(_ duration: Duration = .milliseconds(50)) -> String {
        guard let level = try? recentRMS(duration) else { return "unavailable" }
        return "\(dBFS(level)) dBFS"
    }

    /// The IOProc reads the input as Float32; anything else would be misread, so refuse it.
    private static func requireFloat32Input(device: AudioObjectID) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        try CoreAudioProperty.check(AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size), "Sizing BlackHole input streams")
        var streams = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard let first = streams.indices.first else { throw IntegrationError("BlackHole has no input stream to capture") }
        try CoreAudioProperty.check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &streams), "Reading BlackHole input streams")
        let format = try CoreAudioProperty.scalar(streams[first], kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription())
        let isFloat32 = format.mFormatID == kAudioFormatLinearPCM
            && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
            && format.mBitsPerChannel == 32
        guard isFloat32 else {
            throw IntegrationError("BlackHole's input virtual format isn't Float32 (format \(format.mFormatID), flags \(format.mFormatFlags), \(format.mBitsPerChannel) bits); the capture can't read it")
        }
    }

    /// The capture IOProc only reads; asking the HAL not to send it output streams keeps this
    /// process from being an output client of BlackHole. Best effort: the IOProc also zeroes output.
    private static func disableOutputStreams(device: AudioObjectID, procID: AudioDeviceIOProcID?) {
        guard let procID else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIOProcStreamUsage,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioHardwareIOProcStreamUsage>.size)
        else { return }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment)
        defer { raw.deallocate() }
        let usage = raw.assumingMemoryBound(to: AudioHardwareIOProcStreamUsage.self)
        usage.pointee.mIOProc = unsafeBitCast(procID, to: UnsafeMutableRawPointer.self)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return }
        withUnsafeMutablePointer(to: &usage.pointee.mStreamIsOn) { first in
            let flags = UnsafeMutableRawPointer(first).assumingMemoryBound(to: UInt32.self)
            for index in 0..<Int(usage.pointee.mNumberStreams) { flags[index] = 0 }
        }
        AudioObjectSetPropertyData(device, &address, 0, nil, size, raw)
    }
}

/// Lock-protected ring of mono samples. The IOProc appends; the test thread reads.
/// A lock on the IO thread is acceptable here: this is test code, not Hush's realtime path.
final class CaptureRing: Sendable {
    private struct State {
        var storage: [Float]
        var written = 0
    }

    private let state: Mutex<State>
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        self.state = Mutex(State(storage: [Float](repeating: 0, count: capacity)))
    }

    var frameCount: Int { state.withLock { $0.written } }

    func append(_ data: UnsafePointer<Float>, frames: Int, stride: Int) {
        state.withLock { state in
            let capacity = self.capacity
            let base = state.written
            state.storage.withUnsafeMutableBufferPointer { storage in
                for frame in 0..<frames {
                    storage[(base + frame) % capacity] = data[frame * stride]
                }
            }
            state.written = base + frames
        }
    }

    /// The frames `start..<end`, or nil unless every one of them is still in the ring.
    func samples(from start: Int, to end: Int) -> [Float]? {
        state.withLock { state in
            guard start >= 0, end > start, end <= state.written, start >= state.written - capacity else { return nil }
            return (start..<end).map { state.storage[$0 % capacity] }
        }
    }
}

// MARK: Analysis

func rms(_ samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    var sum: Double = 0
    for sample in samples { sum += Double(sample) * Double(sample) }
    return Float((sum / Double(samples.count)).squareRoot())
}

/// RMS of consecutive non-overlapping windows.
func windowedRMS(_ samples: [Float], window: Int) -> [Float] {
    guard window > 0 else { return [] }
    return stride(from: 0, to: samples.count - window + 1, by: window).map { start in
        rms(Array(samples[start..<(start + window)]))
    }
}

/// Length of the longest run of exact digital zeros.
func longestZeroRun(_ samples: [Float]) -> Int {
    var longest = 0
    var current = 0
    for sample in samples {
        if sample == 0 {
            current += 1
            longest = max(longest, current)
        } else {
            current = 0
        }
    }
    return longest
}

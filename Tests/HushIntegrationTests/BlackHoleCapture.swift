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

    func samples(from start: Int, to end: Int? = nil) -> [Float] {
        ring.samples(from: start, to: end ?? ring.frameCount)
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
        return samples(from: start, to: start + needed)
    }

    /// RMS of the most recent `duration` of capture.
    func recentRMS(_ duration: Duration) -> Float {
        let end = frameCount
        return rms(samples(from: max(0, end - frames(for: duration)), to: end))
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
    private let capacity: Int

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

    func samples(from start: Int, to end: Int) -> [Float] {
        state.withLock { state in
            let lower = max(start, state.written - capacity, 0)
            let upper = min(end, state.written)
            guard upper > lower else { return [] }
            return (lower..<upper).map { state.storage[$0 % capacity] }
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

// HushToneGenerator: plays a continuous sine to an output device, for Hush's integration tests.
//
// It runs as its own process so Hush can tap it by its Core Audio process object, like a real app.
// Control while running: SIGUSR1 stops playback (the process stays alive), SIGUSR2 starts it again,
// SIGTERM or SIGINT quits. It also quits when its parent process goes away, so a crashed test run
// doesn't leave a tone playing.

import AudioToolbox
import CoreAudio
import Foundation

let usage = """
    Usage: HushToneGenerator [options]

      --device UID       Output device UID (default: the system default output)
      --frequency HZ     Sine frequency in Hz (default: 1000)
      --level DBFS       Peak level in dBFS (default: -12)
      --amplitude A      Peak level as a linear amplitude, 0...1 (overrides --level)
      --duration SECS    Quit after this many seconds; 0 runs until stopped (default: 0)
      --paused           Start with playback stopped; send SIGUSR2 to start it
      --list-devices     Print "UID<TAB>name" for every output device and quit
      --help             Show this help

    Signals: SIGUSR1 stops playback, SIGUSR2 starts it, SIGTERM/SIGINT quit.
    Prints PLAYING or STOPPED on stdout after each change.
    """

struct Options {
    var deviceUID: String?
    var frequency = 1000.0
    var amplitude = pow(10, -12.0 / 20)
    var duration = 0.0
    var startPaused = false
    var listDevices = false
}

func fail(_ message: String, code: Int32 = 64) -> Never {
    FileHandle.standardError.write(Data("HushToneGenerator: \(message)\n".utf8))
    exit(code)
}

func say(_ line: String) {
    print(line)
    fflush(stdout)
}

func parseOptions(_ arguments: [String]) -> Options {
    var options = Options()
    var iterator = arguments.makeIterator()
    func value(for flag: String) -> String {
        guard let value = iterator.next() else { fail("\(flag) needs a value") }
        return value
    }
    func number(for flag: String) -> Double {
        let text = value(for: flag)
        guard let number = Double(text), number.isFinite else { fail("\(flag): not a number: \(text)") }
        return number
    }
    while let argument = iterator.next() {
        switch argument {
        case "--device": options.deviceUID = value(for: argument)
        case "--frequency": options.frequency = number(for: argument)
        case "--level": options.amplitude = pow(10, number(for: argument) / 20)
        case "--amplitude": options.amplitude = number(for: argument)
        case "--duration": options.duration = number(for: argument)
        case "--paused": options.startPaused = true
        case "--list-devices": options.listDevices = true
        case "--help", "-h":
            print(usage)
            exit(0)
        default: fail("unknown option \(argument)\n\n\(usage)")
        }
    }
    guard options.frequency > 0 else { fail("--frequency must be positive") }
    guard (0...1).contains(options.amplitude) else { fail("amplitude must be between 0 and 1") }
    guard options.duration >= 0 else { fail("--duration can't be negative") }
    return options
}

// MARK: Devices

func globalAddress(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var address = globalAddress(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
    return value?.takeRetainedValue() as String?
}

func deviceID(forUID uid: String) -> AudioObjectID? {
    var address = globalAddress(kAudioHardwarePropertyTranslateUIDToDevice)
    var cfUID = uid as CFString
    var device = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = withUnsafeMutablePointer(to: &cfUID) { pointer in
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<CFString>.size), pointer, &size, &device)
    }
    return status == noErr && device != kAudioObjectUnknown ? device : nil
}

func listOutputDevices() {
    var address = globalAddress(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
        fail("couldn't list devices", code: 1)
    }
    var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else {
        fail("couldn't list devices", code: 1)
    }
    for device in devices {
        var streams = globalAddress(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var streamSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { continue }
        print("\(stringProperty(device, kAudioDevicePropertyDeviceUID) ?? "?")\t\(stringProperty(device, kAudioObjectPropertyName) ?? "?")")
    }
}

// MARK: Playback

/// Per-queue sine state. Only the queue's callback thread touches `phase`.
final class SineState {
    let amplitude: Float
    let increment: Double
    var phase = 0.0

    init(frequency: Double, amplitude: Double, sampleRate: Double) {
        self.amplitude = Float(amplitude)
        self.increment = 2 * Double.pi * frequency / sampleRate
    }

    /// Fills an interleaved stereo Float32 buffer to its capacity.
    func fill(_ buffer: AudioQueueBufferRef) {
        let frames = Int(buffer.pointee.mAudioDataBytesCapacity) / (2 * MemoryLayout<Float>.size)
        let samples = buffer.pointee.mAudioData.assumingMemoryBound(to: Float.self)
        for frame in 0..<frames {
            let value = amplitude * Float(sin(phase))
            samples[2 * frame] = value
            samples[2 * frame + 1] = value
            phase += increment
            if phase >= 2 * Double.pi { phase -= 2 * Double.pi }
        }
        buffer.pointee.mAudioDataByteSize = UInt32(frames * 2 * MemoryLayout<Float>.size)
    }
}

/// Owns at most one running AudioQueue. Used from the main thread only.
/// Stopping disposes the queue and starting builds a fresh one, so buffer ownership is never in doubt.
final class TonePlayer {
    private let options: Options
    private let sampleRate = 48_000.0
    private var queue: AudioQueueRef?
    private var state: Unmanaged<SineState>?

    init(options: Options) { self.options = options }

    var isPlaying: Bool { queue != nil }

    func start() throws {
        guard queue == nil else { return }
        var format = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        let sine = Unmanaged.passRetained(SineState(frequency: options.frequency, amplitude: options.amplitude, sampleRate: sampleRate))
        var newQueue: AudioQueueRef?
        let callback: AudioQueueOutputCallback = { context, queue, buffer in
            guard let context else { return }
            Unmanaged<SineState>.fromOpaque(context).takeUnretainedValue().fill(buffer)
            AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
        }
        try check(AudioQueueNewOutput(&format, callback, sine.toOpaque(), nil, nil, 0, &newQueue), "AudioQueueNewOutput")
        guard let newQueue else { throw ToneError(message: "AudioQueueNewOutput returned no queue") }
        do {
            if let uid = options.deviceUID {
                var cfUID = uid as CFString
                let status = withUnsafePointer(to: &cfUID) { pointer in
                    AudioQueueSetProperty(newQueue, kAudioQueueProperty_CurrentDevice, pointer, UInt32(MemoryLayout<CFString>.size))
                }
                try check(status, "setting the output device")
            }
            for _ in 0..<3 {
                var buffer: AudioQueueBufferRef?
                try check(AudioQueueAllocateBuffer(newQueue, 1024 * 8, &buffer), "AudioQueueAllocateBuffer")
                guard let buffer else { throw ToneError(message: "AudioQueueAllocateBuffer returned no buffer") }
                sine.takeUnretainedValue().fill(buffer)
                try check(AudioQueueEnqueueBuffer(newQueue, buffer, 0, nil), "AudioQueueEnqueueBuffer")
            }
            try check(AudioQueueStart(newQueue, nil), "AudioQueueStart")
        } catch {
            AudioQueueDispose(newQueue, true)
            sine.release()
            throw error
        }
        queue = newQueue
        state = sine
        say("PLAYING")
    }

    func stop() {
        guard let queue else { return }
        AudioQueueStop(queue, true)
        AudioQueueDispose(queue, true)  // synchronous: no callback runs after this returns
        self.queue = nil
        state?.release()
        state = nil
        say("STOPPED")
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw ToneError(message: "\(operation) failed (OSStatus \(status))") }
    }
}

struct ToneError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

// MARK: Main

let options = parseOptions(Array(CommandLine.arguments.dropFirst()))
if options.listDevices {
    listOutputDevices()
    exit(0)
}
if let uid = options.deviceUID, deviceID(forUID: uid) == nil {
    fail("no audio device with UID \(uid) (try --list-devices)", code: 2)
}

let player = TonePlayer(options: options)

@MainActor func startOrExit() {
    do {
        try player.start()
    } catch {
        fail("\(error)", code: 1)
    }
}

var signalSources: [any DispatchSourceSignal] = []
@MainActor func handle(_ signalNumber: Int32, _ action: @escaping @MainActor () -> Void) {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler { MainActor.assumeIsolated(action) }
    source.resume()
    signalSources.append(source)
}
handle(SIGUSR1) { player.stop() }
handle(SIGUSR2) { startOrExit() }
handle(SIGTERM) { player.stop(); exit(0) }
handle(SIGINT) { player.stop(); exit(0) }

// Quit when the parent (the test runner) dies: launchd adopts orphans.
let parentAtLaunch = getppid()
let parentWatch = DispatchSource.makeTimerSource(queue: .main)
parentWatch.schedule(deadline: .now() + 0.5, repeating: 0.5)
parentWatch.setEventHandler {
    MainActor.assumeIsolated {
        if getppid() != parentAtLaunch {
            player.stop()
            exit(0)
        }
    }
}
parentWatch.resume()

if options.duration > 0 {
    DispatchQueue.main.asyncAfter(deadline: .now() + options.duration) {
        MainActor.assumeIsolated {
            player.stop()
            exit(0)
        }
    }
}

if options.startPaused {
    say("STOPPED")
} else {
    startOrExit()
}
dispatchMain()

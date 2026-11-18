import CoreAudio
import Foundation

private final class BundleMarker {}

/// A running `HushToneGenerator` subprocess. Tests own one each and call `terminate()` in `defer`.
@MainActor
final class ToneProcess {
    let process = Process()
    private let errors = Pipe()

    /// Launches the generator. `deviceUID` nil plays to the default output.
    init(deviceUID: String?, level: Double, frequency: Double = 1000, paused: Bool = false) throws {
        process.executableURL = try Self.executableURL()
        var arguments = ["--frequency", String(frequency), "--level", String(level), "--duration", "120"]
        if let deviceUID { arguments += ["--device", deviceUID] }
        if paused { arguments.append("--paused") }
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
    }

    var pid: pid_t { process.processIdentifier }

    /// Launches a generator and waits until it plays (or, when `paused`, until it has a process
    /// object). A launch that doesn't get there within `timeout` is killed and tried once more:
    /// the owner's run once saw a first launch not playing within 3 s.
    static func launch(
        deviceUID: String?,
        level: Double,
        frequency: Double = 1000,
        paused: Bool = false,
        timeout: Duration = .seconds(8)
    ) async throws -> (tone: ToneProcess, object: AudioObjectID) {
        var lastError: (any Error)?
        for _ in 0..<2 {
            let tone = try ToneProcess(deviceUID: deviceUID, level: level, frequency: frequency, paused: paused)
            do {
                return (tone, try await tone.processObject(playing: !paused, timeout: timeout))
            } catch {
                tone.terminate()
                lastError = error
            }
        }
        throw lastError ?? IntegrationError("HushToneGenerator didn't start")
    }

    /// The built generator next to the test bundle in the products directory, or `HUSH_TONE_GENERATOR`.
    static func executableURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["HUSH_TONE_GENERATOR"] {
            return URL(fileURLWithPath: override)
        }
        let productsDirectory = Bundle(for: BundleMarker.self).bundleURL.deletingLastPathComponent()
        let url = productsDirectory.appendingPathComponent("HushToneGenerator")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw IntegrationError("HushToneGenerator isn't built at \(url.path). Run `swift build --product HushToneGenerator` (make integration-test does).")
        }
        return url
    }

    /// Waits until the generator has a Core Audio process object and, unless `playing` is false,
    /// is running output. Throws with the generator's stderr if it exits.
    func processObject(playing: Bool = true, timeout: Duration = .seconds(8)) async throws -> AudioObjectID {
        var object: AudioObjectID?
        let ready = await waitUntil(timeout: timeout) {
            guard process.isRunning else { return true }
            object = AudioDevices.processObject(forPID: pid)
            guard let object else { return false }
            return !playing || AudioDevices.isRunningOutput(object)
        }
        if !process.isRunning {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw IntegrationError("HushToneGenerator exited (\(process.terminationStatus)): \(message)")
        }
        guard ready, let object else {
            throw IntegrationError("HushToneGenerator (pid \(pid)) never \(playing ? "started playing" : "reached Core Audio") within \(timeout)")
        }
        return object
    }

    /// Stops playback; the process stays alive, so its process object usually remains.
    func stopPlayback() { kill(pid, SIGUSR1) }

    func startPlayback() { kill(pid, SIGUSR2) }

    /// Quits the generator: SIGTERM, then SIGKILL if it hasn't exited after 2 s. Safe to call twice.
    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline { usleep(10_000) }
        if process.isRunning { kill(pid, SIGKILL) }
        process.waitUntilExit()
    }
}

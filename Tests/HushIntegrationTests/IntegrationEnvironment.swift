import Foundation
import HushAudio
import Testing

/// Gates for the Core Audio integration tests. A plain `swift test` (and CI's build job) skips
/// them all; `make integration-test` sets `HUSH_INTEGRATION=1`.
enum IntegrationEnvironment {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["HUSH_INTEGRATION"] == "1"
    }

    /// True under CI (`CI` or `GITHUB_ACTIONS` set). CI never requests permission: nobody can click.
    static var isCI: Bool {
        let environment = ProcessInfo.processInfo.environment
        return !(environment["CI"] ?? "").isEmpty || !(environment["GITHUB_ACTIONS"] ?? "").isEmpty
    }

    static let disabledMessage: Comment =
        "Core Audio integration test: runs only with HUSH_INTEGRATION=1 (use `make integration-test`)"

    static let permissionMessage: Comment =
        "Audio Recording isn't granted. macOS attributes it to the app running the tests (Terminal, iTerm, VS Code…), not to the test binary. In System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only, turn that app on (click + to add it if it isn't listed), quit and reopen it, then rerun `make integration-test`."

    static let blackHoleMessage: Comment =
        "BlackHole 2ch isn't installed: run `brew install --cask blackhole-2ch` (then `sudo killall coreaudiod` or log out and in) and rerun `make integration-test`."

    /// How long a local run waits for someone to answer the Audio Recording prompt.
    static let requestTimeout: Duration = .seconds(60)

    /// Resolved once per test run, so the prompt can appear at most once.
    @MainActor private static var authorization: Task<Bool, Never>?

    /// True when tests may create process taps. Runs before any tap is created.
    ///
    /// Locally, an undetermined permission is requested once (the prompt names the terminal app);
    /// under CI it's never requested. `AudioCapturePermission` reports `.authorized` when the private
    /// TCC symbols are missing, so a missing preflight skips: there'd be no way to know.
    /// When the suite is disabled this returns true, so the per-test gate gives the skip reason.
    static func captureAuthorized() async -> Bool {
        guard isEnabled else { return true }
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW),
              dlsym(handle, "TCCAccessPreflight") != nil
        else { return false }
        return await MainActor.run {
            if let authorization { return authorization }
            let task = Task { @MainActor in
                await CapturePermissionGate.resolve(
                    AudioCapturePermission(), mayRequest: !isCI, timeout: requestTimeout)
            }
            authorization = task
            return task
        }.value
    }

    /// True when BlackHole 2ch is installed (or the suite is disabled, see `captureAuthorized`).
    static func blackHoleAvailable() async -> Bool {
        guard isEnabled else { return true }
        return await MainActor.run { AudioDevices.blackHole() != nil }
    }

    /// Records that an integration test really ran (not skipped), one line per test, in the file
    /// named by `HUSH_INTEGRATION_MARKER`. `make integration-test` fails if nothing was recorded.
    static func recordRun(group: String, test: String = #function) {
        guard let path = ProcessInfo.processInfo.environment["HUSH_INTEGRATION_MARKER"], !path.isEmpty else { return }
        let line = Data("\(group) \(test)\n".utf8)
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: line)
        }
    }
}

/// The permission decision, separated from the environment so it can be tested with a fake source.
@MainActor
enum CapturePermissionGate {
    /// Authorized: run. Denied: skip. Undetermined: request once if allowed, waiting up to
    /// `timeout` for an answer; a denial or no answer skips.
    static func resolve(_ source: any AudioCapturePermissionSource, mayRequest: Bool, timeout: Duration) async -> Bool {
        switch source.currentStatus() {
        case .authorized: return true
        case .denied: return false
        case .undetermined:
            guard mayRequest else { return false }
            return await request(source, timeout: timeout) == .authorized
        }
    }

    /// `requestAccess()` can't be cancelled, so it races a timer; whichever finishes first wins.
    private static func request(_ source: any AudioCapturePermissionSource, timeout: Duration) async -> AudioCapturePermissionStatus? {
        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            Task { @MainActor in once.resume(await source.requestAccess()) }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                once.resume(nil)
            }
        }
    }

    @MainActor
    private final class ResumeOnce {
        private var continuation: CheckedContinuation<AudioCapturePermissionStatus?, Never>?
        init(_ continuation: CheckedContinuation<AudioCapturePermissionStatus?, Never>) { self.continuation = continuation }
        func resume(_ value: AudioCapturePermissionStatus?) {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }
}

/// Every integration test lives under this suite. `.serialized` applies to the nested suites too,
/// so no two tests touch Core Audio at once.
@Suite(
    "Core Audio integration",
    .serialized,
    .enabled(IntegrationEnvironment.permissionMessage) { await IntegrationEnvironment.captureAuthorized() })
struct CoreAudioIntegration {}

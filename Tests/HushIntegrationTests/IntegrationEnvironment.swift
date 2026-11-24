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

    /// True only on GitHub Actions (`GITHUB_ACTIONS=true`), where the macOS runner is a VM with no
    /// audio hardware: BlackHole's clock and coreaudiod run under virtualisation, so Core Audio's
    /// takeover gaps and restart times are several times what real hardware shows. Only the
    /// tolerances that say so widen here; `CI=1` on a real Mac keeps every strict bound.
    static var isGitHubActions: Bool {
        ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"
    }

    /// How long a wait for audio to settle may take: as given on hardware, five times that on
    /// GitHub Actions, where the VM can stall Core Audio for over a second. Only for waits whose
    /// failure means "never got there"; latency budgets (the 300 ms mute) use `expectTiming`.
    static func settleTimeout(_ timeout: Duration) -> Duration {
        isGitHubActions ? timeout * 5 : timeout
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
        else {
            recordRun(group: "SKIP", test: "permission")
            return false
        }
        let authorized = await MainActor.run {
            if let authorization { return authorization }
            let task = Task { @MainActor in
                await CapturePermissionGate.resolve(
                    AudioCapturePermission(), mayRequest: !isCI, timeout: requestTimeout)
            }
            authorization = task
            return task
        }.value
        if !authorized { recordRun(group: "SKIP", test: "permission") }
        return authorized
    }

    /// True when BlackHole 2ch is installed (or the suite is disabled, see `captureAuthorized`).
    static func blackHoleAvailable() async -> Bool {
        guard isEnabled else { return true }
        let available = await MainActor.run { AudioDevices.blackHole() != nil }
        if !available { recordRun(group: "SKIP", test: "blackhole") }
        return available
    }

    /// Appends to the file named by `HUSH_INTEGRATION_MARKER`: `A <test>` or `B <test>` for each test
    /// that really runs (not skipped), and `SKIP <reason>` when a gate skips. `make integration-test`
    /// reads it to fail when nothing, or no BlackHole test, ran, and to print why.
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

/// A real-time check: a gap, a burst, an overlap or a latency budget. These measure scheduling as
/// much as Hush, so they're strict on hardware (`make integration-test`, the release gate for audio
/// changes) and soft on GitHub Actions, whose VM stalls coreaudiod and BlackHole's clock for
/// anywhere from a few buffers to a quarter of a second (measured: zero runs of 740–11076 frames
/// against 512 on hardware). On CI a miss is a known intermittent issue: it's printed with a
/// `[ci-timing]` prefix, counted in the job summary, and doesn't fail the run. Checks of what
/// Hush does (levels, mute holding, teardown) stay hard everywhere.
func expectTiming(
    _ condition: Bool, _ comment: @autoclosure () -> Comment, sourceLocation: SourceLocation = #_sourceLocation
) {
    guard !condition else { return }
    guard IntegrationEnvironment.isGitHubActions else {
        Issue.record(comment(), sourceLocation: sourceLocation)
        return
    }
    let comment = comment()
    print("[ci-timing] \(sourceLocation.fileName):\(sourceLocation.line): \(comment)")
    withKnownIssue(
        "Real-time check on the GitHub Actions VM: strict on hardware, soft here", isIntermittent: true,
        sourceLocation: sourceLocation
    ) {
        Issue.record(comment, sourceLocation: sourceLocation)
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
    private static func request(_ source: any AudioCapturePermissionSource, timeout: Duration) async
        -> AudioCapturePermissionStatus?
    {
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
        init(_ continuation: CheckedContinuation<AudioCapturePermissionStatus?, Never>) {
            self.continuation = continuation
        }
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

import Foundation
import HushAudio
import Testing

/// Gates for the Core Audio integration tests. A plain `swift test` (and CI's build job) skips
/// them all; `make integration-test` sets `HUSH_INTEGRATION=1`.
enum IntegrationEnvironment {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["HUSH_INTEGRATION"] == "1"
    }

    static let disabledMessage: Comment =
        "Core Audio integration test: runs only with HUSH_INTEGRATION=1 (use `make integration-test`)"

    static let permissionMessage: Comment =
        "Grant Audio Recording to the app running the tests (Terminal/VS Code) in System Settings → Privacy & Security → Screen & System Audio Recording, then rerun `make integration-test`."

    static let blackHoleMessage: Comment =
        "BlackHole 2ch isn't installed: run `brew install --cask blackhole-2ch` (then `sudo killall coreaudiod` or log out and in) and rerun `make integration-test`."

    /// True when tests may create process taps. Reads permission with the same preflight Hush uses
    /// and never requests it: creating a tap without permission can raise a TCC prompt, and these
    /// tests must never wait on one. "Undetermined" and "denied" both skip.
    ///
    /// `AudioCapturePermission` reports `.authorized` when the private TCC symbols are missing (the
    /// app then lets tap creation prompt). Tests can't allow that, so a missing preflight skips too.
    /// When the suite is disabled this returns true, so the per-test gate gives the skip reason.
    static func captureAuthorized() async -> Bool {
        guard isEnabled else { return true }
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW),
              dlsym(handle, "TCCAccessPreflight") != nil
        else { return false }
        return await MainActor.run { AudioCapturePermission().currentStatus() == .authorized }
    }

    /// True when BlackHole 2ch is installed (or the suite is disabled, see `captureAuthorized`).
    static func blackHoleAvailable() async -> Bool {
        guard isEnabled else { return true }
        return await MainActor.run { AudioDevices.blackHole() != nil }
    }
}

/// Every integration test lives under this suite. `.serialized` applies to the nested suites too,
/// so no two tests touch Core Audio at once.
@Suite(
    "Core Audio integration",
    .serialized,
    .enabled(IntegrationEnvironment.permissionMessage) { await IntegrationEnvironment.captureAuthorized() })
struct CoreAudioIntegration {}

import Foundation

/// Audio capture (process tap) permission, read through the private TCC framework.
///
/// There is no public API for this TCC service. The symbols are resolved at runtime;
/// if they're missing we report `.authorized` and let tap creation trigger the system prompt.
@MainActor
public final class AudioCapturePermission: AudioCapturePermissionSource {
    private typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int32
    private typealias RequestFunction = @convention(c) (CFString, CFDictionary?, @convention(block) (Bool) -> Void) -> Void

    private let preflight: PreflightFunction?
    private let request: RequestFunction?

    public init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
        preflight = handle.flatMap { dlsym($0, "TCCAccessPreflight") }
            .map { unsafeBitCast($0, to: PreflightFunction.self) }
        request = handle.flatMap { dlsym($0, "TCCAccessRequest") }
            .map { unsafeBitCast($0, to: RequestFunction.self) }
    }

    public func currentStatus() -> AudioCapturePermissionStatus {
        guard let preflight else { return .authorized }
        switch preflight("kTCCServiceAudioCapture" as CFString, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .undetermined
        }
    }

    public func requestAccess() async -> AudioCapturePermissionStatus {
        guard let request else { return currentStatus() }
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            request("kTCCServiceAudioCapture" as CFString, nil) { granted in
                continuation.resume(returning: granted)
            }
        }
        return granted ? .authorized : .denied
    }
}

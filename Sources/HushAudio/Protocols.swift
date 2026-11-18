import CoreAudio

/// Which process objects to poll for running-state changes the HAL may not notify.
package enum ProcessPolling: Equatable, Sendable {
    /// No polling; listeners still give best-effort updates.
    case off
    /// Only these objects (ones that don't exist are ignored).
    case objects(Set<AudioObjectID>)
    /// Every process object, including ones that appear later.
    case all
}

@MainActor
package protocol AudioProcessSource: AnyObject {
    /// Begins monitoring. Calls `onChange` immediately with the current list, then on every change.
    func start(onChange: @escaping @MainActor ([AudioApp]) -> Void)
    /// Chooses what to poll. The caller knows which running states decisions depend on.
    func setPolling(_ polling: ProcessPolling)
}

package extension AudioProcessSource {
    func setPolling(_ polling: ProcessPolling) {}
}

@MainActor
package protocol OutputDeviceSource: AnyObject {
    /// Begins monitoring. Calls `onChange` immediately with the current default output, then on every change.
    func start(onChange: @escaping @MainActor (OutputDevice?) -> Void)
    /// Begins watching the devices the user can pick as output. Calls `onChange` immediately with
    /// the current list, then whenever a device appears, disappears or changes. The default never
    /// calls it, so the list stays empty.
    func observeDevices(onChange: @escaping @MainActor ([OutputDevice]) -> Void)
    /// Makes `id` the system default output device. Every app follows, and so does `start`'s callback.
    func setDefaultOutput(_ id: AudioObjectID) throws
}

/// Thrown by `OutputDeviceSource.setDefaultOutput` for sources that can't change the output.
package struct OutputSelectionUnsupported: Error, Sendable {}

package extension OutputDeviceSource {
    func observeDevices(onChange: @escaping @MainActor ([OutputDevice]) -> Void) {}
    func setDefaultOutput(_ id: AudioObjectID) throws { throw OutputSelectionUnsupported() }
}

@MainActor
package protocol AudioEngineHandle: AnyObject {
    var mode: EngineMode { get }
    var processObjectIDs: [AudioObjectID] { get }
    func start() throws
    func stop()
    func setGain(_ gain: Float)
    /// Returns the peak level seen since the previous call, then resets it.
    func currentPeak() -> Float
    func rebuild(outputDeviceID: AudioObjectID) throws
    /// Two-phase `rebuild`, so several engines can overlap their start-up: begin all, then finish
    /// all. The default does the whole rebuild in `beginRebuild`.
    func beginRebuild(outputDeviceID: AudioObjectID) throws
    func finishRebuild() throws
    /// Retargets the running tap at a new process list in place (same tap, aggregate and IOProc),
    /// so processes already tapped stay muted throughout. Throws if the change can't be applied;
    /// the engine is then unchanged and the caller can rebuild instead.
    func updateProcesses(_ processObjectIDs: [AudioObjectID]) throws
    /// Converts the running engine between `.meterOnly` and `.control` in place. `gain` is the
    /// control gain (ignored for `.meterOnly`). Throws if the change can't be applied; the engine
    /// is then unchanged and the caller can rebuild instead.
    func switchMode(to mode: EngineMode, gain: Float) throws
}

extension AudioEngineHandle {
    package func beginRebuild(outputDeviceID: AudioObjectID) throws { try rebuild(outputDeviceID: outputDeviceID) }
    package func finishRebuild() throws {}
}

@MainActor
package protocol AudioEngineFactory: AnyObject {
    /// Creates and starts an engine. On failure, partial resources are already torn down.
    func makeEngine(
        appID: String,
        processObjectIDs: [AudioObjectID],
        mode: EngineMode,
        initialGain: Float,
        outputDeviceID: AudioObjectID
    ) throws -> any AudioEngineHandle
}

@MainActor
package protocol AudioCapturePermissionSource: AnyObject {
    func currentStatus() -> AudioCapturePermissionStatus
    func requestAccess() async -> AudioCapturePermissionStatus
}

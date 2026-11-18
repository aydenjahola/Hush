import CoreAudio

@MainActor
public protocol AudioProcessSource: AnyObject {
    /// Begins monitoring. Calls `onChange` immediately with the current list, then on every change.
    func start(onChange: @escaping @MainActor ([AudioApp]) -> Void)
    /// Polls running state more often or less often. The caller decides when fast polling is worth it.
    func setFastPolling(_ fast: Bool)
}

public extension AudioProcessSource {
    func setFastPolling(_ fast: Bool) {}
}

@MainActor
public protocol OutputDeviceSource: AnyObject {
    /// Begins monitoring. Calls `onChange` immediately with the current default output, then on every change.
    func start(onChange: @escaping @MainActor (OutputDevice?) -> Void)
}

@MainActor
public protocol AudioEngineHandle: AnyObject {
    var mode: EngineMode { get }
    var processObjectIDs: [AudioObjectID] { get }
    func start() throws
    func stop()
    func setGain(_ gain: Float)
    /// Returns the peak level seen since the previous call, then resets it.
    func currentPeak() -> Float
    func rebuild(outputDeviceID: AudioObjectID) throws
    /// Retargets the running tap at a new process list in place (same tap, aggregate and IOProc),
    /// so processes already tapped stay muted throughout. Throws if the change can't be applied;
    /// the engine is then unchanged and the caller can rebuild instead.
    func updateProcesses(_ processObjectIDs: [AudioObjectID]) throws
    /// Converts the running engine between `.meterOnly` and `.control` in place. `gain` is the
    /// control gain (ignored for `.meterOnly`). Throws if the change can't be applied; the engine
    /// is then unchanged and the caller can rebuild instead.
    func switchMode(to mode: EngineMode, gain: Float) throws
}

@MainActor
public protocol AudioEngineFactory: AnyObject {
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
public protocol AudioCapturePermissionSource: AnyObject {
    func currentStatus() -> AudioCapturePermissionStatus
    func requestAccess() async -> AudioCapturePermissionStatus
}

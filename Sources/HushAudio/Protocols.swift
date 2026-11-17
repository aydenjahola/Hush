import CoreAudio

@MainActor
public protocol AudioProcessSource: AnyObject {
    /// Begins monitoring. Calls `onChange` immediately with the current list, then on every change.
    func start(onChange: @escaping @MainActor ([AudioApp]) -> Void)
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

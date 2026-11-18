import CoreAudio
import Foundation
import HushAudio
import HushCore
@testable import HushUI

struct FakeError: Error, CustomStringConvertible {
    var description: String { "fake failure" }
}

@MainActor
final class FakeProcessSource: AudioProcessSource {
    private var onChange: (@MainActor ([AudioApp]) -> Void)?
    private(set) var apps: [AudioApp] = []

    func start(onChange: @escaping @MainActor ([AudioApp]) -> Void) {
        self.onChange = onChange
        onChange(apps)
    }

    func emit(_ apps: [AudioApp]) {
        self.apps = apps
        onChange?(apps)
    }

    private(set) var pollingCalls: [ProcessPolling] = []
    func setPolling(_ polling: ProcessPolling) { pollingCalls.append(polling) }
}

@MainActor
final class FakeOutputSource: OutputDeviceSource {
    private var onChange: (@MainActor (OutputDevice?) -> Void)?
    private(set) var device: OutputDevice? = OutputDevice(id: 1, uid: "built-in", name: "MacBook Pro Speakers")

    func start(onChange: @escaping @MainActor (OutputDevice?) -> Void) {
        self.onChange = onChange
        onChange(device)
    }

    func emit(_ device: OutputDevice?) {
        self.device = device
        onChange?(device)
    }
}

@MainActor
final class FakeEngine: AudioEngineHandle {
    let appID: String
    private(set) var mode: EngineMode
    private(set) var processObjectIDs: [AudioObjectID]
    let initialGain: Float
    private(set) var currentGain: Float
    private(set) var isStopped = false
    private(set) var rebuiltDeviceIDs: [AudioObjectID] = []
    var rebuildError: (any Error)?
    /// Thrown by `updateProcesses` / `switchMode`, to exercise the make-before-break fallback.
    var updateError: (any Error)?
    var switchError: (any Error)?
    var peak: Float = 0
    /// Shared ordered event log, set by the factory.
    var log: ((String) -> Void)?

    init(appID: String, mode: EngineMode, processObjectIDs: [AudioObjectID], initialGain: Float) {
        self.appID = appID
        self.mode = mode
        self.processObjectIDs = processObjectIDs
        self.initialGain = initialGain
        self.currentGain = initialGain
    }

    func start() throws {}
    func stop() {
        isStopped = true
        log?("stop \(appID) \(mode)")
    }
    func setGain(_ gain: Float) { currentGain = gain }
    func currentPeak() -> Float { peak }

    func rebuild(outputDeviceID: AudioObjectID) throws {
        if let rebuildError { throw rebuildError }
        rebuiltDeviceIDs.append(outputDeviceID)
    }

    /// Test hook: makes the engine's list differ from the app's without going through the store.
    func forceProcessObjectIDs(_ ids: [AudioObjectID]) { processObjectIDs = ids }

    func updateProcesses(_ processObjectIDs: [AudioObjectID]) throws {
        log?("update \(appID) \(processObjectIDs)")
        if let updateError { throw updateError }
        self.processObjectIDs = processObjectIDs
    }

    func switchMode(to mode: EngineMode, gain: Float) throws {
        log?("switch \(appID) \(mode)")
        if let switchError { throw switchError }
        self.mode = mode
        currentGain = gain
    }
}

@MainActor
final class FakeEngineFactory: AudioEngineFactory {
    private(set) var made: [FakeEngine] = []
    var error: (any Error)?
    /// Ordered "make <id> <mode>" / "stop <id> <mode>" events across all engines.
    private(set) var events: [String] = []

    func makeEngine(
        appID: String,
        processObjectIDs: [AudioObjectID],
        mode: EngineMode,
        initialGain: Float,
        outputDeviceID: AudioObjectID
    ) throws -> any AudioEngineHandle {
        events.append("make \(appID) \(mode)")
        if let error { throw error }
        let engine = FakeEngine(appID: appID, mode: mode, processObjectIDs: processObjectIDs, initialGain: initialGain)
        engine.log = { [weak self] in self?.events.append($0) }
        made.append(engine)
        return engine
    }

    /// The most recent engine for `appID` that hasn't been stopped.
    func live(_ appID: String) -> FakeEngine? {
        made.last { $0.appID == appID && !$0.isStopped }
    }
}

@MainActor
final class FakePermission: AudioCapturePermissionSource {
    var status: AudioCapturePermissionStatus = .authorized
    /// What the user answers when asked; nil leaves `status` unchanged.
    var answer: AudioCapturePermissionStatus?
    private(set) var requestCount = 0
    func currentStatus() -> AudioCapturePermissionStatus { status }
    func requestAccess() async -> AudioCapturePermissionStatus {
        requestCount += 1
        if let answer { status = answer }
        return status
    }
}

final class FakePersister: SettingsPersisting {
    var document: SettingsDocument
    private(set) var saved: [SettingsDocument] = []

    init(document: SettingsDocument) { self.document = document }
    func load() -> SettingsDocument { document }
    func update(_ change: (inout SettingsDocument) -> Void) {
        change(&document)
        saved.append(document)
    }
}

@MainActor
final class Harness {
    static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    let processes: FakeProcessSource
    let output: FakeOutputSource
    let factory: FakeEngineFactory
    let permission: FakePermission
    let persister: FakePersister
    let store: MixerStore

    init(
        document: SettingsDocument = SettingsDocument(),
        permission status: AudioCapturePermissionStatus = .authorized,
        answer: AudioCapturePermissionStatus? = nil,
        installedApp: @escaping @MainActor (String) -> InstalledAppInfo? = { _ in nil }
    ) {
        let processes = FakeProcessSource()
        let output = FakeOutputSource()
        let factory = FakeEngineFactory()
        let permission = FakePermission()
        permission.status = status
        permission.answer = answer
        let persister = FakePersister(document: document)
        self.processes = processes
        self.output = output
        self.factory = factory
        self.permission = permission
        self.persister = persister
        self.store = MixerStore(
            processSource: processes,
            outputSource: output,
            engineFactory: factory,
            permissionSource: permission,
            persister: persister,
            saveDelay: .seconds(3600),
            now: { Harness.fixedNow },
            installedApp: installedApp)
        store.start()
    }
}

func makeApp(_ id: String, playing: Bool = true, objects: [AudioObjectID] = [42], regular: Bool = true) -> AudioApp {
    AudioApp(id: id, displayName: id, processObjectIDs: objects, isPlaying: playing, isRegularApp: regular)
}

@MainActor func mutedSetting(percent: Int = 100) -> AppVolumeSetting {
    var setting = AppVolumeSetting(percent: percent, lastAdjusted: Harness.fixedNow)
    setting.isMuted = true
    return setting
}

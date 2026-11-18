import CoreAudio
import Foundation
import HushCore
import Synchronization

/// Lock-free state shared between the main thread and the realtime IOProc.
final class EngineSharedState: Sendable {
    let targetGainBits: Atomic<UInt32>
    let appliedGainBits: Atomic<UInt32>
    let peakBits = Atomic<UInt32>(0)
    /// True: replay the tap with gain (`.control`). False: only measure it (`.meterOnly`).
    let replaying: Atomic<Bool>

    /// `appliedGainBits` is the replay's current gain: a meter-only engine starts at 0, so it has
    /// nothing to fade out.
    init(gain: Float, mode: EngineMode) {
        targetGainBits = Atomic(gain.bitPattern)
        appliedGainBits = Atomic((mode == .control ? gain : 0).bitPattern)
        replaying = Atomic(mode == .control)
    }
}

/// One app's tap + private aggregate device + IOProc.
///
/// `.control`: the app is muted at the source (`.mutedWhenTapped`) and replayed with gain.
/// `.meterOnly`: the app plays normally (`.unmuted`); output buffers are zero-filled and only the level is measured.
///
/// Process-list and mode changes are applied in place by setting `kAudioTapPropertyDescription`
/// on the live tap (AudioHardware.h: "This property can be used to modify and set the description
/// of an existing tap."). Rebuilding instead would destroy a `.mutedWhenTapped` tap, which lets the
/// app through at full level until the replacement's IO is running, even with make-before-break.
@MainActor
public final class AppAudioEngine: AudioEngineHandle {
    public private(set) var mode: EngineMode
    public private(set) var processObjectIDs: [AudioObjectID]

    private let appID: String
    private let state: EngineSharedState
    private var outputDeviceID: AudioObjectID
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var tapUUID = UUID()
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    public init(appID: String, processObjectIDs: [AudioObjectID], mode: EngineMode, initialGain: Float, outputDeviceID: AudioObjectID) {
        self.appID = appID
        self.processObjectIDs = processObjectIDs
        self.mode = mode
        self.outputDeviceID = outputDeviceID
        self.state = EngineSharedState(gain: initialGain, mode: mode)
    }

    /// The live tap object, or `kAudioObjectUnknown` when stopped (for integration tests).
    var tapObjectID: AudioObjectID { tapID }

    public func start() throws {
        guard tapID == kAudioObjectUnknown else { return }
        do {
            try build()
        } catch {
            stop()
            throw error
        }
    }

    public func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        state.peakBits.store(0, ordering: .relaxed)
    }

    public func setGain(_ gain: Float) {
        state.targetGainBits.store(gain.bitPattern, ordering: .relaxed)
    }

    public func currentPeak() -> Float {
        Float(bitPattern: state.peakBits.exchange(0, ordering: .relaxed))
    }

    public func rebuild(outputDeviceID: AudioObjectID) throws {
        stop()
        self.outputDeviceID = outputDeviceID
        try start()
    }

    public func updateProcesses(_ processObjectIDs: [AudioObjectID]) throws {
        guard processObjectIDs != self.processObjectIDs else { return }
        if tapID != kAudioObjectUnknown {
            try applyTapDescription(makeDescription(processes: processObjectIDs, mode: mode))
        }
        self.processObjectIDs = processObjectIDs
    }

    public func switchMode(to newMode: EngineMode, gain: Float) throws {
        guard newMode != mode else {
            if newMode == .control { setGain(gain) }
            return
        }
        guard tapID != kAudioObjectUnknown else {
            mode = newMode
            state.targetGainBits.store(gain.bitPattern, ordering: .relaxed)
            state.appliedGainBits.store((newMode == .control ? gain : 0).bitPattern, ordering: .relaxed)
            state.replaying.store(newMode == .control, ordering: .releasing)
            return
        }
        // Both directions overlap rather than gap: the replay is on while the source's mute state
        // changes, and the IOProc crossfades its side over one buffer. A gap is digital silence
        // (a dropout); an overlap is at most source + replay, and only until coreaudiod applies the
        // new mute behaviour (the integration tests bound and log how long that is).
        switch newMode {
        case .control:
            // Replay first (ramping up from g/1000 across the first buffer), then mute the source.
            Self.beginReplay(state: state, gain: gain)
            do {
                try applyTapDescription(makeDescription(processes: processObjectIDs, mode: .control))
            } catch {
                state.replaying.store(false, ordering: .releasing)
                throw error
            }
        case .meterOnly:
            // Unmute the source first, then stop the replay (it fades out over one buffer).
            try applyTapDescription(makeDescription(processes: processObjectIDs, mode: .meterOnly))
            state.replaying.store(false, ordering: .releasing)
        }
        mode = newMode
    }

    /// Turns the replay on with a ramp from g/1000 to g across the next buffer: never from an
    /// exact 0, so the replay itself adds no digital silence next to the source's mute.
    ///
    /// Known limitation, measured on hardware: when a live tap starts muting a process that's
    /// already playing, Core Audio drops exactly one IO buffer of it (a 512-frame zero run at
    /// 512-frame buffers), whatever the order or timing of the replay and the mute. Waiting for
    /// the IOProc to render a replay buffer before muting made no difference, so Hush doesn't.
    nonisolated static func beginReplay(state: EngineSharedState, gain: Float) {
        state.targetGainBits.store(gain.bitPattern, ordering: .relaxed)
        state.appliedGainBits.store((gain / 1000).bitPattern, ordering: .relaxed)
        state.replaying.store(true, ordering: .releasing)
    }

    private func makeDescription(processes: [AudioObjectID], mode: EngineMode) -> CATapDescription {
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = tapUUID  // the aggregate's tap list refers to the tap by this UID
        description.name = "Hush – \(appID)"
        description.isPrivate = true
        description.muteBehavior = mode == .control ? .mutedWhenTapped : .unmuted
        return description
    }

    private func applyTapDescription(_ description: CATapDescription) throws {
        var propertyAddress = CoreAudioProperty.address(kAudioTapPropertyDescription)
        var settable: DarwinBoolean = false
        try CoreAudioProperty.check(
            AudioObjectIsPropertySettable(tapID, &propertyAddress, &settable),
            "Checking kAudioTapPropertyDescription")
        guard settable.boolValue else {
            throw CoreAudioError(
                operation: "Setting kAudioTapPropertyDescription (not settable)",
                status: OSStatus(kAudioHardwareUnsupportedOperationError))
        }
        var reference = Unmanaged.passUnretained(description)
        try withExtendedLifetime(description) {
            try CoreAudioProperty.check(
                AudioObjectSetPropertyData(
                    tapID, &propertyAddress, 0, nil,
                    UInt32(MemoryLayout<Unmanaged<CATapDescription>>.size), &reference),
                "Setting kAudioTapPropertyDescription")
        }
    }

    private func build() throws {
        tapUUID = UUID()
        let description = makeDescription(processes: processObjectIDs, mode: mode)
        if mode == .meterOnly { state.appliedGainBits.store(Float(0).bitPattern, ordering: .relaxed) }
        state.replaying.store(mode == .control, ordering: .releasing)

        var newTap = AudioObjectID(kAudioObjectUnknown)
        try CoreAudioProperty.check(AudioHardwareCreateProcessTap(description, &newTap), "AudioHardwareCreateProcessTap")
        tapID = newTap

        let outputUID = try CoreAudioProperty.string(outputDeviceID, kAudioDevicePropertyDeviceUID)
        let configuration: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Hush – \(appID)",
            kAudioAggregateDeviceUIDKey: "\(HushIdentity.bundleID).aggregate.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        var newAggregate = AudioObjectID(kAudioObjectUnknown)
        try CoreAudioProperty.check(
            AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &newAggregate),
            "AudioHardwareCreateAggregateDevice")
        aggregateID = newAggregate

        // The aggregate's IOProc input list is the main sub-device's input streams first, then the tap's.
        let tapBufferOffset = try CoreAudioProperty.inputStreamCount(outputDeviceID)

        var newProc: AudioDeviceIOProcID?
        try CoreAudioProperty.check(
            AudioDeviceCreateIOProcIDWithBlock(
                &newProc, newAggregate, nil,
                Self.makeIOBlock(state: state, tapBufferOffset: tapBufferOffset)),
            "AudioDeviceCreateIOProcIDWithBlock")
        ioProcID = newProc

        Self.warmUpRouting()
        try CoreAudioProperty.check(AudioDeviceStart(newAggregate, newProc), "AudioDeviceStart")
    }

    /// Runs the routing code once on the main thread so lazy runtime initialisation
    /// (metadata, witness tables, swift_once) happens here and not on the HAL thread.
    private static func warmUpRouting() {
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: 2)
        samples.initialize(repeating: 0, count: 2)
        let list = AudioBufferList.allocate(maximumBuffers: 1)
        defer {
            free(list.unsafeMutablePointer)  // allocate(maximumBuffers:) uses calloc
            samples.deallocate()
        }
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 8, mData: samples)
        _ = BufferRouting.render(input: list, output: list, startGain: 1, endGain: 1)
        _ = BufferRouting.peak(of: list)
        BufferRouting.silence(list)
    }

    /// Realtime: no allocation, locks, logging, Objective-C or async inside the returned block.
    nonisolated static func makeIOBlock(state: EngineSharedState, tapBufferOffset: Int) -> AudioDeviceIOBlock {
        return { _, inputData, _, outputData, _ in
            let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            let output = UnsafeMutableAudioBufferListPointer(outputData)
            let peak: Float
            // Read once per cycle, so a mode switch lands on a buffer boundary.
            if state.replaying.load(ordering: .acquiring) {
                let target = Float(bitPattern: state.targetGainBits.load(ordering: .relaxed))
                let applied = Float(bitPattern: state.appliedGainBits.load(ordering: .relaxed))
                peak = BufferRouting.render(input: input, output: output, startGain: applied, endGain: target, firstInputBuffer: tapBufferOffset)
                state.appliedGainBits.store(target.bitPattern, ordering: .relaxed)
            } else {
                let applied = Float(bitPattern: state.appliedGainBits.load(ordering: .relaxed))
                if applied != 0 {
                    // The replay just stopped: fade it out over this buffer instead of cutting.
                    _ = BufferRouting.render(input: input, output: output, startGain: applied, endGain: 0, firstInputBuffer: tapBufferOffset)
                    state.appliedGainBits.store(Float(0).bitPattern, ordering: .relaxed)
                } else {
                    BufferRouting.silence(output)
                }
                peak = BufferRouting.peak(of: input, firstInputBuffer: tapBufferOffset)
            }
            // Non-negative Float bit patterns order like the values, so an atomic max is a valid peak hold.
            _ = state.peakBits.max(peak.bitPattern, ordering: .relaxed)
        }
    }
}

@MainActor
public final class AppAudioEngineFactory: AudioEngineFactory {
    public init() {}

    public func makeEngine(
        appID: String,
        processObjectIDs: [AudioObjectID],
        mode: EngineMode,
        initialGain: Float,
        outputDeviceID: AudioObjectID
    ) throws -> any AudioEngineHandle {
        let engine = AppAudioEngine(
            appID: appID,
            processObjectIDs: processObjectIDs,
            mode: mode,
            initialGain: initialGain,
            outputDeviceID: outputDeviceID)
        try engine.start()
        return engine
    }
}

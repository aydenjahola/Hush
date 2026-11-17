import CoreAudio
import Foundation
import HushCore
import Synchronization

/// Lock-free state shared between the main thread and the realtime IOProc.
final class EngineSharedState: Sendable {
    let targetGainBits: Atomic<UInt32>
    let appliedGainBits: Atomic<UInt32>
    let peakBits = Atomic<UInt32>(0)

    init(gain: Float) {
        targetGainBits = Atomic(gain.bitPattern)
        appliedGainBits = Atomic(gain.bitPattern)
    }
}

/// One app's tap + private aggregate device + IOProc.
///
/// `.control`: the app is muted at the source (`.mutedWhenTapped`) and replayed with gain.
/// `.meterOnly`: the app plays normally (`.unmuted`); output buffers are zero-filled and only the level is measured.
@MainActor
public final class AppAudioEngine: AudioEngineHandle {
    public let mode: EngineMode
    public let processObjectIDs: [AudioObjectID]

    private let appID: String
    private let state: EngineSharedState
    private var outputDeviceID: AudioObjectID
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    public init(appID: String, processObjectIDs: [AudioObjectID], mode: EngineMode, initialGain: Float, outputDeviceID: AudioObjectID) {
        self.appID = appID
        self.processObjectIDs = processObjectIDs
        self.mode = mode
        self.outputDeviceID = outputDeviceID
        self.state = EngineSharedState(gain: initialGain)
    }

    public func start() throws {
        guard ioProcID == nil else { return }
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

    private func build() throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.uuid = UUID()
        description.name = "Hush – \(appID)"
        description.isPrivate = true
        description.muteBehavior = mode == .control ? .mutedWhenTapped : .unmuted

        var newTap = AudioObjectID(kAudioObjectUnknown)
        try CoreAudioProperty.check(AudioHardwareCreateProcessTap(description, &newTap), "AudioHardwareCreateProcessTap")
        tapID = newTap

        let outputUID = try CoreAudioProperty.string(outputDeviceID, kAudioDevicePropertyDeviceUID)
        let configuration: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Hush – \(appID)",
            kAudioAggregateDeviceUIDKey: "io.github.hush-mixer.aggregate.\(UUID().uuidString)",
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
                Self.makeIOBlock(state: state, mode: mode, tapBufferOffset: tapBufferOffset)),
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
            list.unsafeMutablePointer.deallocate()
            samples.deallocate()
        }
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 8, mData: samples)
        _ = BufferRouting.render(input: list, output: list, startGain: 1, endGain: 1)
        _ = BufferRouting.peak(of: list)
        BufferRouting.silence(list)
    }

    /// Realtime: no allocation, locks, logging, Objective-C or async inside the returned block.
    nonisolated private static func makeIOBlock(state: EngineSharedState, mode: EngineMode, tapBufferOffset: Int) -> AudioDeviceIOBlock {
        return { _, inputData, _, outputData, _ in
            let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            let output = UnsafeMutableAudioBufferListPointer(outputData)
            let peak: Float
            switch mode {
            case .control:
                let target = Float(bitPattern: state.targetGainBits.load(ordering: .relaxed))
                let applied = Float(bitPattern: state.appliedGainBits.load(ordering: .relaxed))
                peak = BufferRouting.render(input: input, output: output, startGain: applied, endGain: target, firstInputBuffer: tapBufferOffset)
                state.appliedGainBits.store(target.bitPattern, ordering: .relaxed)
            case .meterOnly:
                peak = BufferRouting.peak(of: input, firstInputBuffer: tapBufferOffset)
                BufferRouting.silence(output)
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

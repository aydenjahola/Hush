import CoreAudio
import Foundation
import HushCore
import Testing
@testable import HushAudio
@testable import HushUI

/// A tone playing into BlackHole, with BlackHole's input recorded. Tests point Hush's engines at
/// BlackHole too, so the capture hears exactly what Hush lets through. The system default output
/// is never changed.
@MainActor
final class LoopbackRig {
    static let toneLevel = -12.0

    let blackHole: OutputDevice
    let capture: BlackHoleCapture
    let tone: ToneProcess
    let toneObject: AudioObjectID
    /// RMS of the unprocessed tone as captured.
    private(set) var baseline: Float = 0

    init() async throws {
        guard let blackHole = AudioDevices.blackHole() else { throw IntegrationError("BlackHole 2ch disappeared") }
        self.blackHole = blackHole
        capture = BlackHoleCapture(device: blackHole.id)
        let tone = try ToneProcess(deviceUID: blackHole.uid, level: Self.toneLevel)
        self.tone = tone
        let capture = self.capture
        do {
            try capture.start()
            toneObject = try await tone.processObject()
        } catch {
            tone.terminate()
            capture.stop()
            throw error
        }
        do {
            _ = try await capture.record(.milliseconds(200))  // settle
            baseline = rms(try await capture.record(.milliseconds(300)))
        } catch {
            tearDown()
            throw error
        }
    }

    func tearDown() {
        tone.terminate()
        capture.stop()
    }

    func makeEngine(_ mode: EngineMode, gain: Float) -> AppAudioEngine {
        AppAudioEngine(appID: "tone", processObjectIDs: [toneObject], mode: mode, initialGain: gain, outputDeviceID: blackHole.id)
    }

    /// Waits until the recent capture level is within `tolerance` dB of `target`.
    func waitForLevel(_ target: Float, tolerance: Float = 1.5, timeout: Duration = .seconds(1)) async -> Bool {
        await waitUntil(timeout: timeout) { abs(dBFS(self.capture.recentRMS(.milliseconds(50))) - dBFS(target)) <= tolerance }
    }

    /// Samples from `mark` to `mark + duration`, waiting for them to arrive.
    func samples(after mark: Int, _ duration: Duration) async throws -> [Float] {
        let end = mark + capture.frames(for: duration)
        guard await waitUntil(timeout: duration + .seconds(2), { self.capture.frameCount >= end }) else {
            throw IntegrationError("BlackHole capture stalled")
        }
        return capture.samples(from: mark, to: end)
    }
}

private let silenceDB: Float = -60

extension CoreAudioIntegration {
    /// Group B: what actually reaches the output, measured through BlackHole's loopback.
    @Suite(
        "End to end (BlackHole)",
        .enabled(IntegrationEnvironment.blackHoleMessage) { await IntegrationEnvironment.blackHoleAvailable() })
    @MainActor
    struct EndToEnd {
        @Test(
            "Baseline: the tone reaches the BlackHole capture at its expected level",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func baselineReachesCapture() async throws {
            let rig = try await LoopbackRig()
            defer { rig.tearDown() }
            let expected = sineRMS(peakDB: LoopbackRig.toneLevel)
            #expect(abs(dBFS(rig.baseline) - dBFS(expected)) <= 1.5,
                    "captured \(dBFS(rig.baseline)) dBFS RMS, expected \(dBFS(expected)) dBFS ± 1.5 dB")
        }

        @Test(
            "Mute: a control engine at gain 0 silences the app within 300 ms (regression)",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func muteSilencesOutput() async throws {
            let rig = try await LoopbackRig()
            defer { rig.tearDown() }
            let engine = rig.makeEngine(.control, gain: 0)
            defer { engine.stop() }

            let startBegan = ContinuousClock.now
            try engine.start()
            let startTook = ContinuousClock.now - startBegan

            let silenced = await waitUntil(timeout: .milliseconds(300), interval: .milliseconds(5)) {
                dBFS(rig.capture.recentRMS(.milliseconds(20))) < silenceDB
            }
            #expect(silenced, "still \(dBFS(rig.capture.recentRMS(.milliseconds(20)))) dBFS 300 ms after start() returned (start() took \(startTook)); the app isn't muted")

            let held = rms(try await rig.capture.record(.milliseconds(500)))
            #expect(dBFS(held) < silenceDB, "mute didn't hold: \(dBFS(held)) dBFS over the next 500 ms")
        }

        @Test(
            "50%: the captured level drops by 12 dB",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func halfVolumeAttenuates() async throws {
            let rig = try await LoopbackRig()
            defer { rig.tearDown() }
            let engine = rig.makeEngine(.control, gain: VolumeCurve.gain(percent: 50))
            defer { engine.stop() }
            try engine.start()

            _ = await rig.waitForLevel(rig.baseline * 0.25)
            let level = rms(try await rig.capture.record(.milliseconds(300)))
            let change = dBFS(level) - dBFS(rig.baseline)
            #expect(abs(change + 12) <= 1.5, "50% changed the level by \(change) dB, expected -12 ± 1.5 dB")
        }

        @Test(
            "Make before break: meter-only → control at 50% never bursts or gaps",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func meterOnlyToControlSwap() async throws {
            let rig = try await LoopbackRig()
            defer { rig.tearDown() }
            let meter = rig.makeEngine(.meterOnly, gain: 1)
            defer { meter.stop() }
            try meter.start()
            #expect(await rig.waitForLevel(rig.baseline), "a meter-only engine changed the level")

            let mark = rig.capture.frameCount
            let control = rig.makeEngine(.control, gain: VolumeCurve.gain(percent: 50))
            defer { control.stop() }
            try control.start()  // same order as MixerStore.reconcile: new engine first, then stop the old
            meter.stop()

            let swap = try await rig.samples(after: mark, .milliseconds(600))
            let check = SwapCheck(samples: swap, baseline: rig.baseline, bufferFrames: rig.capture.bufferFrameSize, window: windowFrames(rig))
            // Full volume is expected until the control engine takes over; after that it must not come back.
            let onset = try #require(check.firstWindowBelowThreshold, "the level never dropped below baseline × 0.5 during the swap")
            #expect(check.loudestWindow(from: onset) <= check.threshold,
                    "a burst of \(check.loudestWindow(from: onset)) RMS after attenuation began (limit \(check.threshold))")
            #expect(check.longestZeroRun <= check.bufferFrames,
                    "\(check.longestZeroRun) frames of digital silence during the swap (one buffer is \(check.bufferFrames))")
            #expect(await rig.waitForLevel(rig.baseline * 0.25), "the level didn't settle at -12 dB after the swap")
        }

        @Test(
            "Make before break: control → control at 50% never bursts or gaps",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func controlToControlSwap() async throws {
            let rig = try await LoopbackRig()
            defer { rig.tearDown() }
            let gain = VolumeCurve.gain(percent: 50)
            let old = rig.makeEngine(.control, gain: gain)
            defer { old.stop() }
            try old.start()
            #expect(await rig.waitForLevel(rig.baseline * 0.25), "the first control engine didn't attenuate")

            let mark = rig.capture.frameCount
            let new = rig.makeEngine(.control, gain: gain)
            defer { new.stop() }
            try new.start()
            old.stop()

            let swap = try await rig.samples(after: mark, .milliseconds(600))
            let check = SwapCheck(samples: swap, baseline: rig.baseline, bufferFrames: rig.capture.bufferFrameSize, window: windowFrames(rig))
            #expect(check.loudestWindow(from: 0) <= check.threshold,
                    "a burst of \(check.loudestWindow(from: 0)) RMS during the swap (limit \(check.threshold))")
            #expect(check.longestZeroRun <= check.bufferFrames,
                    "\(check.longestZeroRun) frames of digital silence during the swap (one buffer is \(check.bufferFrames))")
            #expect(await rig.waitForLevel(rig.baseline * 0.25), "the level didn't stay at -12 dB after the swap")
        }

        @Test(
            "MixerStore with real sources: 50% attenuates, mute silences, 100% restores",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func mixerStoreEndToEnd() async throws {
            let rig = try await LoopbackRig()
            defer { rig.tearDown() }

            // Belt and braces: MixerStore.start() requests permission when it's undetermined,
            // which would prompt. The suite gate already skipped that case.
            let permission = AudioCapturePermission()
            try #require(permission.currentStatus() == .authorized)

            let processes = RecordingProcessSource()
            let store = MixerStore(
                processSource: processes,
                outputSource: FixedOutputSource(device: rig.blackHole),
                engineFactory: AppAudioEngineFactory(),
                permissionSource: permission,
                persister: MemoryPersister(),
                saveDelay: .seconds(3600))
            defer {
                store.shutdown()
                processes.stop()
            }
            store.start()

            var toneAppID: String?
            let found = await waitUntil(timeout: .seconds(3)) {
                toneAppID = processes.apps.first { $0.processObjectIDs.contains(rig.toneObject) && $0.isPlaying }?.id
                return toneAppID != nil
            }
            let id = try #require(toneAppID, "MixerStore's process source never listed the tone as playing (found: \(found))")
            #expect(store.engineCount == 0, "no engine should run before any level is changed")

            store.setPercent(50, for: id)
            #expect(store.engineMode(for: id) == .control)
            #expect(await rig.waitForLevel(rig.baseline * 0.25, timeout: .milliseconds(1500)),
                    "setPercent(50) didn't bring the capture to -12 dB (now \(dBFS(rig.capture.recentRMS(.milliseconds(50)))) dBFS, baseline \(dBFS(rig.baseline)))")

            store.toggleMute(for: id)
            let muted = await waitUntil(timeout: .milliseconds(300), interval: .milliseconds(5)) {
                dBFS(rig.capture.recentRMS(.milliseconds(20))) < silenceDB
            }
            #expect(muted, "toggleMute didn't silence the capture within 300 ms (now \(dBFS(rig.capture.recentRMS(.milliseconds(20)))) dBFS)")
            let held = rms(try await rig.capture.record(.milliseconds(300)))
            #expect(dBFS(held) < silenceDB, "mute didn't hold: \(dBFS(held)) dBFS")

            store.toggleMute(for: id)
            #expect(await rig.waitForLevel(rig.baseline * 0.25), "unmuting didn't return to 50%")

            store.setPercent(100, for: id)
            #expect(await rig.waitForLevel(rig.baseline, timeout: .milliseconds(1500)), "back at 100% the tone isn't at full level")
            #expect(store.engineCount == 0, "an app at 100% should have no engine")
        }
    }
}

/// ~5 ms windows: five periods of the 1 kHz tone, short enough to catch a brief burst.
@MainActor
private func windowFrames(_ rig: LoopbackRig) -> Int {
    max(Int(rig.capture.sampleRate / 200), 48)
}

/// Burst and gap analysis of the capture around an engine swap.
struct SwapCheck {
    let windows: [Float]
    let threshold: Float
    let longestZeroRun: Int
    let bufferFrames: Int

    init(samples: [Float], baseline: Float, bufferFrames: Int, window: Int) {
        windows = windowedRMS(samples, window: window)
        threshold = baseline * 0.5
        longestZeroRun = HushIntegrationTests.longestZeroRun(samples)
        self.bufferFrames = bufferFrames
    }

    var firstWindowBelowThreshold: Int? { windows.firstIndex { $0 < threshold } }

    func loudestWindow(from index: Int) -> Float {
        windows[min(index, windows.count)...].max() ?? 0
    }
}

// MARK: Real-source adapters for MixerStore

/// The real AudioProcessMonitor, remembering the last list so the test can find the tone's app ID.
@MainActor
final class RecordingProcessSource: AudioProcessSource {
    private let monitor = AudioProcessMonitor()
    private(set) var apps: [AudioApp] = []

    func start(onChange: @escaping @MainActor ([AudioApp]) -> Void) {
        monitor.start { [weak self] apps in
            self?.apps = apps
            onChange(apps)
        }
    }

    func setFastPolling(_ fast: Bool) { monitor.setFastPolling(fast) }

    func stop() { monitor.stop() }
}

/// Reports BlackHole as the output, so MixerStore's engines play there instead of the default output.
@MainActor
final class FixedOutputSource: OutputDeviceSource {
    let device: OutputDevice
    init(device: OutputDevice) { self.device = device }
    func start(onChange: @escaping @MainActor (OutputDevice?) -> Void) { onChange(device) }
}

/// Keeps settings in memory: the test must never touch ~/Library/Application Support/Hush.
final class MemoryPersister: SettingsPersisting {
    private var document = SettingsDocument()
    func load() -> SettingsDocument { document }
    func update(_ change: (inout SettingsDocument) -> Void) { change(&document) }
}

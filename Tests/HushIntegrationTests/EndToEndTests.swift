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
    static var expectedBaseline: Float { sineRMS(peakDB: toneLevel) }

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
        let (tone, toneObject) = try await ToneProcess.launch(deviceUID: blackHole.uid, level: Self.toneLevel)
        self.tone = tone
        self.toneObject = toneObject
        let capture = self.capture
        do {
            try capture.start()
        } catch {
            tone.terminate()
            capture.stop()
            throw error
        }
        do {
            _ = try await capture.record(.milliseconds(200))  // settle
            baseline = rms(try await capture.record(.milliseconds(300)))
            // Every later check is relative to this, so a silent or wrong baseline would let
            // "attenuated" and "muted" pass vacuously.
            let expected = dBFS(Self.expectedBaseline)
            guard abs(dBFS(baseline) - expected) <= 3 else {
                throw IntegrationError(
                    "The unprocessed tone captured at \(dBFS(baseline)) dBFS RMS, expected \(expected) dBFS ± 3 dB. Is BlackHole's loopback working, and is something else playing into it?"
                )
            }
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
        AppAudioEngine(
            appID: "tone", processObjectIDs: [toneObject], mode: mode, initialGain: gain, outputDeviceID: blackHole.id)
    }

    /// Waits until the recent capture level is within `tolerance` dB of `target`.
    func waitForLevel(_ target: Float, tolerance: Float = 1.5, timeout: Duration = .seconds(1)) async -> Bool {
        await waitUntil(timeout: timeout) {
            // An unavailable readback counts as "not there yet", never as a level.
            guard let level = try? self.capture.recentRMS(.milliseconds(50)) else { return false }
            return abs(dBFS(level) - dBFS(target)) <= tolerance
        }
    }

    /// Waits until the recent capture is below `silenceDB`. An unavailable readback isn't silence.
    func waitForSilence(timeout: Duration) async -> Bool {
        await waitUntil(timeout: timeout, interval: .milliseconds(5)) {
            guard let level = try? self.capture.recentRMS(.milliseconds(20)) else { return false }
            return dBFS(level) < silenceDB
        }
    }

    /// Samples from `mark` to `mark + duration`, waiting for them to arrive.
    func samples(after mark: Int, _ duration: Duration) async throws -> [Float] {
        let end = mark + capture.frames(for: duration)
        guard await waitUntil(timeout: duration + .seconds(2), { self.capture.frameCount >= end }) else {
            throw IntegrationError("BlackHole capture stalled")
        }
        return try capture.samples(from: mark, to: end)
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
            IntegrationEnvironment.recordRun(group: "B")
            let rig = try await LoopbackRig()
            defer { rig.tearDown() }
            let expected = LoopbackRig.expectedBaseline
            #expect(
                abs(dBFS(rig.baseline) - dBFS(expected)) <= 1.5,
                "captured \(dBFS(rig.baseline)) dBFS RMS, expected \(dBFS(expected)) dBFS ± 1.5 dB")
        }

        @Test(
            "Mute: a control engine at gain 0 silences the app within 300 ms (regression)",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func muteSilencesOutput() async throws {
            IntegrationEnvironment.recordRun(group: "B")
            let rig = try await LoopbackRig()
            defer { rig.tearDown() }
            let engine = rig.makeEngine(.control, gain: 0)
            defer { engine.stop() }

            // Timed from just before start(): tap and aggregate creation count against the 300 ms.
            let startBegan = ContinuousClock.now
            try engine.start()
            let startTook = ContinuousClock.now - startBegan
            #expect(startTook < .seconds(1), "start() took \(startTook)")

            let remaining = max(.milliseconds(300) - (ContinuousClock.now - startBegan), .zero)
            let silenced = await rig.waitForSilence(timeout: remaining)
            #expect(
                silenced,
                "still \(rig.capture.recentLevel(.milliseconds(20))) 300 ms after calling start() (start() took \(startTook)); the app isn't muted"
            )

            let held = rms(try await rig.capture.record(.milliseconds(500)))
            #expect(dBFS(held) < silenceDB, "mute didn't hold: \(dBFS(held)) dBFS over the next 500 ms")

            // Positive control: the silence was the engine's doing, not a dead tone or capture.
            engine.stop()
            #expect(
                await rig.waitForLevel(rig.baseline),
                "after stop() the tone didn't come back to its baseline (now \(rig.capture.recentLevel()))")
            #expect(rig.tone.process.isRunning, "the tone process died during the test")
        }

        @Test(
            "50%: the captured level drops by 12 dB",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func halfVolumeAttenuates() async throws {
            IntegrationEnvironment.recordRun(group: "B")
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
            "In place: meter-only → control at 50% never bursts or gaps",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func meterOnlyToControlSwap() async throws {
            IntegrationEnvironment.recordRun(group: "B")
            let rig = try await LoopbackRig()
            defer { rig.tearDown() }
            let gain = VolumeCurve.gain(percent: 50)
            let (engine, check) = try await switchMeteredEngineToControl(rig, gain: gain)
            defer { engine.stop() }
            // Full volume is expected until the mute lands; after that it must not come back.
            let onset = try #require(
                check.sustainedOnset,
                "the level never stayed attenuated (below baseline × 0.75, above silence) for 3 windows during the swap"
            )
            #expect(
                check.loudestWindow(from: onset) <= check.threshold,
                "a burst of \(check.loudestWindow(from: onset)) RMS after attenuation began (limit \(check.threshold))")
            #expect(
                check.loudestWindow(in: 0..<onset) <= meterToControlLimit(rig),
                "before the level dropped it reached \(check.loudestWindow(in: 0..<onset)) RMS (limit \(meterToControlLimit(rig))): the mute landed after the replay"
            )
            #expect(await rig.waitForLevel(rig.baseline * 0.25), "the level didn't settle at -12 dB after the swap")
        }

        @Test(
            "In place: meter-only → control at 99% stays within source + replay and never gaps",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func meterOnlyToControlAt99() async throws {
            // The first step of a drag down from 100%: the overlap here is the worst case (≈ 2×).
            IntegrationEnvironment.recordRun(group: "B")
            let rig = try await LoopbackRig()
            defer { rig.tearDown() }
            let gain = VolumeCurve.gain(percent: 99)
            let (engine, check) = try await switchMeteredEngineToControl(rig, gain: gain)
            defer { engine.stop() }
            #expect(
                check.loudestWindow(from: 0) <= meterToControlLimit(rig),
                "the swap reached \(check.loudestWindow(from: 0)) RMS (limit \(meterToControlLimit(rig))): the mute landed after the replay"
            )
            // Positive control: an unmuted source plus the replay would settle near +6 dB.
            #expect(
                await rig.waitForLevel(rig.baseline * gain),
                "the level didn't settle at 99% (now \(rig.capture.recentLevel()))")
        }

        @Test(
            "Takeover: first adjust with the popover closed (a new control engine on a playing app at 50%)",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func firstAdjustOfAPlayingApp() async throws {
            IntegrationEnvironment.recordRun(group: "B")
            let rig = try await LoopbackRig()
            defer { rig.tearDown() }
            let mark = rig.capture.frameCount
            // What MixerStore does on the first setPercent with no engine yet: the factory builds the
            // engine meter-only and switches it in place once its IOProc runs.
            let engine = try AppAudioEngineFactory().makeEngine(
                appID: "tone", processObjectIDs: [rig.toneObject], mode: .control,
                initialGain: VolumeCurve.gain(percent: 50), outputDeviceID: rig.blackHole.id)
            defer { engine.stop() }
            #expect(engine.mode == .control)

            let check = try await swapCheck(
                rig, after: mark, "first adjust (new control engine) at 0.25",
                zeroRunAllowance: takeoverAllowance(rig))
            #expect(
                check.loudestWindow(from: 0) <= meterToControlLimit(rig),
                "the takeover reached \(check.loudestWindow(from: 0)) RMS (limit \(meterToControlLimit(rig)))")
            #expect(
                await rig.waitForLevel(rig.baseline * 0.25),
                "the level didn't settle at -12 dB (now \(rig.capture.recentLevel()))")
        }

        @Test(
            "Output rebuild of a control engine at 50%: at most a one-buffer gap and no louder than normal",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func outputRebuildOfAControlEngineStaysWithinOneBufferAndNormalLevel() async throws {
            IntegrationEnvironment.recordRun(group: "B")
            let rig = try await LoopbackRig()
            defer { rig.tearDown() }
            let engine = rig.makeEngine(.control, gain: VolumeCurve.gain(percent: 50))
            defer { engine.stop() }
            try engine.start()
            #expect(await rig.waitForLevel(rig.baseline * 0.25), "the control engine didn't attenuate")

            // The BlackHole rig has one output device, so rebuild onto the same ID.
            // Documented limitation: while the engine moves devices its muted tap is destroyed, so
            // the source is briefly audible at normal (unattenuated) level. That blip is accepted.
            // Rejected: silence longer than one buffer + 8 frames, and anything above 1.15x the
            // normal level (source plus replay).
            let mark = rig.capture.frameCount
            try engine.rebuild(outputDeviceID: rig.blackHole.id)
            #expect(engine.mode == .control)
            let check = try await swapCheck(
                rig, after: mark, "output rebuild of a control engine", zeroRunAllowance: takeoverAllowance(rig))
            #expect(
                check.loudestWindow(from: 0) <= meterToControlLimit(rig),
                "the rebuild reached \(check.loudestWindow(from: 0)) RMS (limit \(meterToControlLimit(rig)))")
            // 1 s is plenty on hardware. On the GitHub Actions VM the rebuilt aggregate (the old one
            // destroyed and a new one started on the same device) has been seen still silent after
            // it, so CI waits longer. The wait stays bounded: an engine that never resumes still
            // fails, and the log line says whether its IOProc ever ran (slow start versus dead).
            let settleTimeout: Duration = IntegrationEnvironment.isGitHubActions ? .seconds(5) : .seconds(1)
            if IntegrationEnvironment.isGitHubActions {
                print("[ci-tolerance] output rebuild: waiting up to \(settleTimeout) (1 s on hardware) for -12 dB")
            }
            let settleBegan = ContinuousClock.now
            let settled = await rig.waitForLevel(rig.baseline * 0.25, timeout: settleTimeout)
            print(
                "[rebuild] settled: \(settled) after \(ContinuousClock.now - settleBegan) (window plus wait), IOProc has run: \(engine.ioProcHasRun), now \(rig.capture.recentLevel())"
            )
            #expect(
                settled,
                "the level didn't settle at -12 dB within \(settleTimeout) (now \(rig.capture.recentLevel()), IOProc has run: \(engine.ioProcHasRun))"
            )
        }

        @Test(
            "In place: control → meter-only (back to 100%) never gaps",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func controlToMeterOnlySwap() async throws {
            // Resetting a lowered app to 100% with the popover open.
            IntegrationEnvironment.recordRun(group: "B")
            let rig = try await LoopbackRig()
            defer { rig.tearDown() }
            let gain = VolumeCurve.gain(percent: 50)
            let engine = rig.makeEngine(.control, gain: gain)
            defer { engine.stop() }
            try engine.start()
            #expect(await rig.waitForLevel(rig.baseline * 0.25), "the control engine didn't attenuate")

            let mark = rig.capture.frameCount
            try engine.switchMode(to: .meterOnly, gain: 1)
            #expect(engine.mode == .meterOnly)
            let check = try await swapCheck(rig, after: mark, "control → meter-only")
            let overlapLimit = rig.baseline * (1 + gain) * 1.1
            #expect(
                check.loudestWindow(from: 0) <= overlapLimit,
                "the swap reached \(check.loudestWindow(from: 0)) RMS, more than source + replay (limit \(overlapLimit))"
            )
            #expect(
                await rig.waitForLevel(rig.baseline),
                "the level didn't return to full after the swap (now \(rig.capture.recentLevel()))")
            _ = engine.currentPeak()
            #expect(
                await waitUntil(timeout: .seconds(1)) { engine.currentPeak() > 0 },
                "the converted engine stopped metering")
        }

        /// Measured on hardware, the level before the takeover stayed at 1.00× baseline (the source
        /// is cut, a buffer is dropped, then the replay fades in). 1.15× leaves headroom for a
        /// partial crossfade; source plus a full-gain replay (a real bump) fails.
        private func meterToControlLimit(_ rig: LoopbackRig) -> Float { rig.baseline * 1.15 }

        /// Known limitation, accepted by the owner: when a tap starts muting a process that's already
        /// playing (meter-only → control, or a fresh control engine on a playing app), Core Audio
        /// drops exactly one IO buffer of it, whatever Hush's order or timing (measured: 513 frames
        /// at 512-frame buffers, with and without waiting for the replay first). A few frames of
        /// slack cover the samples at the gap's edges. Every other swap stays at one buffer.
        ///
        /// CI-only allowance: on the GitHub Actions VM (`GITHUB_ACTIONS=true`) the same gaps measured
        /// 1860–3720 frames at 512-frame buffers (virtualised coreaudiod and BlackHole clock), against
        /// about 512 on hardware. There the bound widens to 8 buffers in total, so silence is still
        /// bounded (a stuck engine or a dropped replay is far longer) and a `[ci-tolerance]` line
        /// says so. Real hardware, `CI=1` included, keeps one buffer + 8 frames.
        private func takeoverAllowance(_ rig: LoopbackRig) -> Int {
            let strict = 8
            guard IntegrationEnvironment.isGitHubActions else { return strict }
            let buffer = rig.capture.bufferFrameSize
            let allowance = 7 * buffer + strict
            print(
                "[ci-tolerance] GITHUB_ACTIONS=true: takeover zero-run limit \(buffer + allowance) frames (8 buffers of \(buffer)) instead of \(buffer + strict)"
            )
            return allowance
        }

        /// Starts a meter-only engine, switches it to control at `gain`, and returns it (the caller
        /// stops it) with the analysed 600 ms after the switch (zero runs already checked).
        private func switchMeteredEngineToControl(_ rig: LoopbackRig, gain: Float) async throws -> (
            AppAudioEngine, SwapCheck
        ) {
            let engine = rig.makeEngine(.meterOnly, gain: 1)
            do {
                try engine.start()
            } catch {
                engine.stop()
                throw error
            }
            #expect(await rig.waitForLevel(rig.baseline), "a meter-only engine changed the level")

            // What MixerStore.reconcile does when the user first adjusts a metered app: the same
            // tap becomes .mutedWhenTapped and the running IOProc starts replaying it.
            let mark = rig.capture.frameCount
            do {
                try engine.switchMode(to: .control, gain: gain)
            } catch {
                engine.stop()
                throw error
            }
            #expect(engine.mode == .control)
            do {
                return (
                    engine,
                    try await swapCheck(
                        rig, after: mark, "meter-only → control at \(gain)", zeroRunAllowance: takeoverAllowance(rig))
                )
            } catch {
                engine.stop()
                throw error
            }
        }

        /// Analyses the 600 ms after `mark`, checks the zero run, and logs how long the level sat
        /// above the unprocessed baseline (the source/replay overlap while the mute changes).
        private func swapCheck(_ rig: LoopbackRig, after mark: Int, _ what: String, zeroRunAllowance: Int = 0)
            async throws -> SwapCheck
        {
            let swap = try await rig.samples(after: mark, .milliseconds(600))
            let check = SwapCheck(
                samples: swap, baseline: rig.baseline, bufferFrames: rig.capture.bufferFrameSize,
                window: windowFrames(rig))
            let windowMS = Double(windowFrames(rig)) / rig.capture.sampleRate * 1000
            let above = Double(check.windowCount(above: rig.baseline * 1.05)) * windowMS
            // Silence still running at the end of the window is a stall, not a gap that closed.
            let trailingZeros = swap.reversed().prefix { $0 == 0 }.count
            print(
                "[swap] \(what): \(String(format: "%.1f", above)) ms above baseline, loudest \(String(format: "%.2f", check.loudestWindow(from: 0) / rig.baseline))× baseline, longest zero run \(check.longestZeroRun) frames (buffer \(check.bufferFrames)), \(trailingZeros) silent frames at the window's end"
            )
            #expect(
                check.longestZeroRun <= check.bufferFrames + zeroRunAllowance,
                "\(what): \(check.longestZeroRun) frames of digital silence (limit: one buffer, \(check.bufferFrames), + \(zeroRunAllowance))"
            )
            return check
        }

        @Test(
            "In place: a control engine at 50% takes in and drops a helper process without a burst or gap",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func controlToControlSwap() async throws {
            IntegrationEnvironment.recordRun(group: "B")
            let rig = try await LoopbackRig()
            defer { rig.tearDown() }
            let engine = rig.makeEngine(.control, gain: VolumeCurve.gain(percent: 50))
            defer { engine.stop() }
            try engine.start()
            #expect(await rig.waitForLevel(rig.baseline * 0.25), "the control engine didn't attenuate")

            // A helper process appears (a browser spawning one): it has a process object but isn't
            // playing yet. A different frequency keeps the two tones from interfering.
            let (helper, helperObject) = try await ToneProcess.launch(
                deviceUID: rig.blackHole.uid, level: LoopbackRig.toneLevel, frequency: 440, paused: true)
            defer { helper.terminate() }

            // What MixerStore.reconcile does for a process-list change: update the same tap.
            var mark = rig.capture.frameCount
            try engine.updateProcesses([rig.toneObject, helperObject].sorted())
            try await expectNoBurstOrGap(rig, after: mark, "adding the helper")

            // Positive control: the update really reached the tap. The helper starts playing and
            // must come out at 50% too: two tones at 0.25× each sum to 0.25 × √2 × baseline
            // (-9 dB), while an unprocessed helper would bring the level back to about 0 dB.
            helper.startPlayback()
            let playingObject = try await helper.processObject(playing: true)
            if playingObject != helperObject {  // the monitor would report the new object, and MixerStore update again
                try engine.updateProcesses([rig.toneObject, playingObject].sorted())
            }
            let bothAtHalf = rig.baseline * 0.25 * Float(2).squareRoot()
            #expect(
                await rig.waitForLevel(bothAtHalf, timeout: .milliseconds(1500)),
                "with the helper playing the capture is \(rig.capture.recentLevel()), expected \(dBFS(bothAtHalf)) dBFS: the updated tap isn't processing the helper"
            )

            // The helper exits, and its object goes with it.
            helper.terminate()
            #expect(
                await rig.waitForLevel(rig.baseline * 0.25, timeout: .milliseconds(1500)),
                "the level didn't return to -12 dB after the helper quit")
            mark = rig.capture.frameCount
            try engine.updateProcesses([rig.toneObject])
            try await expectNoBurstOrGap(rig, after: mark, "dropping the helper")
            #expect(await rig.waitForLevel(rig.baseline * 0.25), "the level didn't stay at -12 dB after the update")
        }

        /// The 600 ms after `mark` never rise above the burst limit or go digitally silent for
        /// more than one buffer.
        private func expectNoBurstOrGap(_ rig: LoopbackRig, after mark: Int, _ what: String) async throws {
            let swap = try await rig.samples(after: mark, .milliseconds(600))
            let check = SwapCheck(
                samples: swap, baseline: rig.baseline, bufferFrames: rig.capture.bufferFrameSize,
                window: windowFrames(rig))
            #expect(
                check.loudestWindow(from: 0) <= check.threshold,
                "\(what): a burst of \(check.loudestWindow(from: 0)) RMS (limit \(check.threshold))")
            #expect(
                check.longestZeroRun <= check.bufferFrames,
                "\(what): \(check.longestZeroRun) frames of digital silence (one buffer is \(check.bufferFrames))")
        }

        @Test(
            "MixerStore with real sources: 50% attenuates, mute silences, 100% restores",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func mixerStoreEndToEnd() async throws {
            IntegrationEnvironment.recordRun(group: "B")
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
            let id = try #require(
                toneAppID, "MixerStore's process source never listed the tone as playing (found: \(found))")
            #expect(store.engineCount == 0, "no engine should run before any level is changed")

            store.setPercent(50, for: id)
            #expect(store.engineMode(for: id) == .control)
            #expect(
                await rig.waitForLevel(rig.baseline * 0.25, timeout: .milliseconds(1500)),
                "setPercent(50) didn't bring the capture to -12 dB (now \(rig.capture.recentLevel()), baseline \(dBFS(rig.baseline)) dBFS)"
            )

            store.toggleMute(for: id)
            let muted = await rig.waitForSilence(timeout: .milliseconds(300))
            #expect(
                muted,
                "toggleMute didn't silence the capture within 300 ms (now \(rig.capture.recentLevel(.milliseconds(20))))"
            )
            let held = rms(try await rig.capture.record(.milliseconds(300)))
            #expect(dBFS(held) < silenceDB, "mute didn't hold: \(dBFS(held)) dBFS")

            store.toggleMute(for: id)
            #expect(await rig.waitForLevel(rig.baseline * 0.25), "unmuting didn't return to 50%")

            // The rig guarantees an audible baseline, so this can't pass at silence.
            store.setPercent(100, for: id)
            #expect(
                await rig.waitForLevel(rig.baseline, timeout: .milliseconds(1500)),
                "back at 100% the tone isn't at full level (now \(rig.capture.recentLevel()))")
            let restored = rms(try await rig.capture.record(.milliseconds(300)))
            #expect(
                abs(dBFS(restored) - dBFS(rig.baseline)) <= 1.5,
                "at 100% the capture is \(dBFS(restored)) dBFS, baseline \(dBFS(rig.baseline)) dBFS")
            #expect(store.engineCount == 0, "an app at 100% should have no engine")
            #expect(rig.tone.process.isRunning, "the tone process died during the test")
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
        // Two briefly overlapping 50% engines legitimately sum to about 0.5× baseline; a
        // full-level burst (1.0×) is what this catches.
        threshold = baseline * 0.75
        longestZeroRun = HushIntegrationTests.longestZeroRun(samples)
        self.bufferFrames = bufferFrames
    }

    /// The first window from which the level stays attenuated (below the threshold but above
    /// silence) for 3 windows. Requiring "above silence" keeps windows inside a zero-run gap from
    /// counting as the onset of attenuation.
    var sustainedOnset: Int? {
        let floor = threshold * 0.05
        let run = 3
        guard windows.count >= run else { return nil }
        return (0...(windows.count - run)).first { start in
            windows[start..<(start + run)].allSatisfy { $0 < threshold && $0 > floor }
        }
    }

    func loudestWindow(from index: Int) -> Float {
        windows[min(index, windows.count)...].max() ?? 0
    }

    func loudestWindow(in range: Range<Int>) -> Float {
        windows[range.clamped(to: 0..<windows.count)].max() ?? 0
    }

    func windowCount(above level: Float) -> Int {
        windows.filter { $0 > level }.count
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

    func setPolling(_ polling: ProcessPolling) { monitor.setPolling(polling) }

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

import CoreAudio
import Foundation
import HushCore
import Testing
@testable import HushAudio

extension CoreAudioIntegration {
    /// Group A: real taps and aggregate devices, checked through the engine's own peak meter and
    /// the HAL's object lists. Needs only Audio Recording permission. Uses BlackHole when it's
    /// installed (silent); otherwise the default output with the tone at -60 dBFS.
    @Suite("Engine level")
    @MainActor
    struct EngineLevel {
        @Test(
            "A control engine's tap receives the tone within 1 s",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func controlEngineReceivesAudio() async throws {
            IntegrationEnvironment.recordRun(group: "A")
            let output = try TestOutput.resolve()
            let tone = try ToneProcess(deviceUID: output.device.uid, level: output.quietLevel)
            defer { tone.terminate() }
            let object = try await tone.processObject()

            let engine = AppAudioEngine(
                appID: "tone", processObjectIDs: [object], mode: .control, initialGain: 1,
                outputDeviceID: output.device.id)
            defer { engine.stop() }
            try engine.start()

            let heard = await waitUntil(timeout: .seconds(1), interval: .milliseconds(20)) { engine.currentPeak() > 0 }
            #expect(heard, "currentPeak() stayed 0 for 1 s: the tap delivered no audio from the tone process")
        }

        @Test(
            "Gain 0.25 (50%) scales the engine's output peak to a quarter",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func gainScalesOutputPeak() async throws {
            IntegrationEnvironment.recordRun(group: "A")
            let output = try TestOutput.resolve()
            let tone = try ToneProcess(deviceUID: output.device.uid, level: output.quietLevel)
            defer { tone.terminate() }
            let object = try await tone.processObject()

            let engine = AppAudioEngine(
                appID: "tone", processObjectIDs: [object], mode: .control, initialGain: 1,
                outputDeviceID: output.device.id)
            defer { engine.stop() }
            try engine.start()
            #expect(await waitUntil(timeout: .seconds(1)) { engine.currentPeak() > 0 })

            let full = median(await collectPeaks(engine, for: .milliseconds(400)))
            try #require(full > 0, "no peaks at 100%")
            engine.setGain(VolumeCurve.gain(percent: 50))
            // Wait for the one-buffer gain ramp to land, then measure over a full window.
            _ = engine.currentPeak()
            let settled = await waitUntil(timeout: .seconds(1), interval: .milliseconds(20)) {
                let peak = engine.currentPeak()
                return peak > 0 && abs(peak / full - 0.25) <= 0.025
            }
            let half = median(await collectPeaks(engine, for: .milliseconds(400)))

            let ratio = half / full
            #expect(settled, "the 50% peak never came within 0.25 ± 0.025 of the 100% peak within 1 s")
            #expect(abs(ratio - 0.25) <= 0.025, "50% peak / 100% peak = \(ratio), expected 0.25 ± 0.025 (full \(full), half \(half))")
        }

        @Test(
            "200% boost keeps every output sample below full scale",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func boostStaysBelowFullScale() async throws {
            IntegrationEnvironment.recordRun(group: "A")
            let output = try TestOutput.resolve()
            // Into BlackHole a -3 dBFS tone doubled would reach +3 dBFS without the limiter.
            // On real speakers it stays at -60 dBFS, so only the 2x scaling is checked.
            let level = output.isBlackHole ? -3.0 : output.quietLevel
            let tone = try ToneProcess(deviceUID: output.device.uid, level: level)
            defer { tone.terminate() }
            let object = try await tone.processObject()

            let engine = AppAudioEngine(
                appID: "tone", processObjectIDs: [object], mode: .control,
                initialGain: VolumeCurve.gain(percent: 200), outputDeviceID: output.device.id)
            defer { engine.stop() }
            try engine.start()
            #expect(await waitUntil(timeout: .seconds(1)) { engine.currentPeak() > 0 })

            let peaks = await collectPeaks(engine, for: .milliseconds(500))
            try #require(!peaks.isEmpty, "no peaks at 200%")
            let loudest = peaks.max() ?? 0
            #expect(loudest < 1.0, "200% output peaked at \(loudest)")
            if output.isBlackHole {
                #expect(loudest > SoftLimiter.threshold, "expected the limiter's range (> \(SoftLimiter.threshold)), got \(loudest): was the boost applied?")
            } else {
                let expected = 2 * linear(dB: level)
                #expect(abs(median(peaks) - expected) <= expected * 0.1, "200% peak \(median(peaks)), expected about \(expected)")
            }
        }

        @Test(
            "A meter-only engine reports the source level and leaves it playing",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func meterOnlyLeavesSourcePlaying() async throws {
            IntegrationEnvironment.recordRun(group: "A")
            let output = try TestOutput.resolve()
            let tone = try ToneProcess(deviceUID: output.device.uid, level: output.quietLevel)
            defer { tone.terminate() }
            let object = try await tone.processObject()

            let capture = output.isBlackHole ? BlackHoleCapture(device: output.device.id) : nil
            defer { capture?.stop() }
            try capture?.start()

            let engine = AppAudioEngine(
                appID: "tone", processObjectIDs: [object], mode: .meterOnly, initialGain: 1,
                outputDeviceID: output.device.id)
            defer { engine.stop() }
            try engine.start()
            #expect(await waitUntil(timeout: .seconds(1)) { engine.currentPeak() > 0 }, "meter-only engine reported no level")

            let peak = median(await collectPeaks(engine, for: .milliseconds(400)))
            let expected = linear(dB: output.quietLevel)
            #expect(abs(peak - expected) <= expected * 0.1, "meter-only peak \(peak), expected the source's \(expected)")
            #expect(AudioDevices.isRunningOutput(object), "the tone process stopped running output under a meter-only tap")

            if let capture {
                let heard = rms(try await capture.record(.milliseconds(300)))
                let expectedRMS = sineRMS(peakDB: output.quietLevel)
                #expect(abs(dBFS(heard) - dBFS(expectedRMS)) <= 1.5,
                        "BlackHole heard \(dBFS(heard)) dBFS under a meter-only tap, expected \(dBFS(expectedRMS)) dBFS (the source must stay audible)")
            }
        }

        @Test(
            "stop() leaves no Hush aggregate device or process tap behind",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func stopTearsEverythingDown() async throws {
            IntegrationEnvironment.recordRun(group: "A")
            let output = try TestOutput.resolve()
            let tone = try ToneProcess(deviceUID: output.device.uid, level: output.quietLevel)
            defer { tone.terminate() }
            let object = try await tone.processObject()

            let aggregatesBefore = Set(AudioDevices.hushAggregateUIDs())
            let tapsBefore = AudioDevices.tapIDs().map(Set.init)

            for mode in [EngineMode.control, .meterOnly, .control] {
                let engine = AppAudioEngine(
                    appID: "tone", processObjectIDs: [object], mode: mode, initialGain: 1,
                    outputDeviceID: output.device.id)
                defer { engine.stop() }
                try engine.start()

                // Prove the lists can see what we create, or the "after" check proves nothing.
                #expect(Set(AudioDevices.hushAggregateUIDs()).subtracting(aggregatesBefore).count == 1,
                        "expected exactly one new Hush aggregate while a \(mode) engine runs")
                let tapsWhileRunning = AudioDevices.tapIDs().map(Set.init)
                let tapsVisible = tapsBefore != nil && tapsWhileRunning.map { $0.count > tapsBefore!.count } == true

                engine.stop()

                let aggregatesGone = await waitUntil(timeout: .seconds(1)) {
                    Set(AudioDevices.hushAggregateUIDs()) == aggregatesBefore
                }
                #expect(aggregatesGone, "Hush aggregate devices left after stop(): \(Set(AudioDevices.hushAggregateUIDs()).subtracting(aggregatesBefore))")
                if tapsVisible, let tapsBefore {
                    let tapsGone = await waitUntil(timeout: .seconds(1)) {
                        AudioDevices.tapIDs().map(Set.init) == tapsBefore
                    }
                    #expect(tapsGone, "process taps left after stop() of a \(mode) engine")
                }
            }
        }

        @Test(
            "AudioProcessMonitor sees the tone start, stop and resume within about 1.5 s",
            .enabled(if: IntegrationEnvironment.isEnabled, IntegrationEnvironment.disabledMessage))
        func monitorTracksPlayingState() async throws {
            IntegrationEnvironment.recordRun(group: "A")
            let output = try TestOutput.resolve()
            let monitor = AudioProcessMonitor()
            let latest = AppsBox()
            monitor.start { latest.apps = $0 }
            defer { monitor.stop() }
            monitor.setFastPolling(true)

            let tone = try ToneProcess(deviceUID: output.device.uid, level: output.quietLevel)
            defer { tone.terminate() }
            _ = try await tone.processObject()

            func toneApp() -> AudioApp? {
                // Re-resolve each time: the process object can change when playback restarts.
                guard let object = AudioDevices.processObject(forPID: tone.pid) else { return nil }
                return latest.apps.first { $0.processObjectIDs.contains(object) }
            }

            let appeared = await waitUntil(timeout: .milliseconds(1500)) { toneApp()?.isPlaying == true }
            #expect(appeared, "the tone's app didn't show as playing within 1.5 s (apps: \(latest.apps.map(\.id)))")

            tone.stopPlayback()
            let stopped = await waitUntil(timeout: .milliseconds(1500)) { toneApp().map { !$0.isPlaying } ?? true }
            #expect(stopped, "the tone's app still showed as playing 1.5 s after playback stopped")

            tone.startPlayback()
            let resumed = await waitUntil(timeout: .milliseconds(1500)) { toneApp()?.isPlaying == true }
            #expect(resumed, "resumed playback wasn't noticed within 1.5 s (the RunningStatePoller case)")
        }
    }
}

@MainActor
final class AppsBox {
    var apps: [AudioApp] = []
}

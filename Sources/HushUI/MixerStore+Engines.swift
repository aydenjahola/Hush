import CoreAudio
import Foundation
import HushAudio
import HushCore
import os

/// Engine reconciliation: makes the set of running engines match `EnginePlan`, and records failures.
extension MixerStore {
    /// Makes the set of running engines match the reconcile rule (see `EnginePlan.desiredMode`).
    func reconcile() {
        defer { updatePolling() }
        guard controlsEnabled, let device = outputDevice else {
            tearDownAllEngines()
            return
        }

        var present: [String: AudioApp] = [:]
        for app in apps { present[app.id] = app }

        // An app that's gone takes its engine and its error with it; the setting stays for its return.
        for id in engines.keys where present[id] == nil { tearDownEngine(id) }
        for id in engineErrors.keys where present[id] == nil { engineErrors[id] = nil }

        for (id, app) in present {
            let setting = settings[id] ?? AppVolumeSetting()
            let desired = EnginePlan.desiredMode(
                setting: setting,
                isPlaying: app.isPlaying,
                isPopoverVisible: isPopoverVisible,
                showLevelMeters: preferences.appearance.showLevelMeters)

            let existing = engines[id]
            if let existing, existing.mode == desired, existing.processObjectIDs == app.processObjectIDs {
                if desired == .control { existing.setGain(setting.effectiveGain) }
                continue
            }

            guard let mode = desired, engineErrors[id] == nil else {
                tearDownEngine(id)
                continue
            }
            // Change the running engine in place when possible: destroying a muted tap lets the
            // app through at full level until a replacement's IO runs, and a new aggregate starts
            // with a gap. A helper spawning (process list) or the user adjusting a metered app
            // (mode) therefore keeps the same tap, aggregate and IOProc.
            if let existing, applyInPlace(to: existing, id: id, processObjectIDs: app.processObjectIDs, mode: mode, setting: setting) {
                continue
            }
            // Fallback, make before break: the old engine keeps the app muted or processed until
            // the new one exists.
            do {
                let replacement = try engineFactory.makeEngine(
                    appID: id,
                    processObjectIDs: app.processObjectIDs,
                    mode: mode,
                    initialGain: mode == .control ? setting.effectiveGain : 1,
                    outputDeviceID: device.id)
                engines[id] = replacement
                existing?.stop()
                if existing != nil { meterLevels[id] = nil }
            } catch {
                tearDownEngine(id)  // never keep an engine in the wrong mode
                recordFailure(error, for: id, mode: mode)
            }
        }
    }

    /// Rebuilds every running engine on a new output device, dropping (and recording) any that fail.
    func rebuildEngines(onOutputDevice device: OutputDevice) {
        engineErrors = [:]
        for (id, engine) in engines {
            do {
                try engine.rebuild(outputDeviceID: device.id)
            } catch {
                tearDownEngine(id)
                recordFailure(error, for: id, mode: engine.mode)
            }
        }
    }

    /// Updates the process list first, then the mode. Returns false (after logging) if the engine
    /// refused either change, so the caller replaces it.
    private func applyInPlace(
        to engine: any AudioEngineHandle,
        id: String,
        processObjectIDs: [AudioObjectID],
        mode: EngineMode,
        setting: AppVolumeSetting
    ) -> Bool {
        do {
            if engine.processObjectIDs != processObjectIDs {
                try engine.updateProcesses(processObjectIDs)
            }
            if engine.mode != mode {
                try engine.switchMode(to: mode, gain: setting.effectiveGain)
            } else if mode == .control {
                engine.setGain(setting.effectiveGain)
            }
            return true
        } catch {
            logger.error("In-place change for \(id, privacy: .public) failed, rebuilding: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Pushes `EnginePlan.polling` to the process source when it changed.
    private func updatePolling() {
        let polling = EnginePlan.polling(
            isPopoverVisible: isPopoverVisible, controlsEnabled: controlsEnabled, apps: apps, settings: settings)
        guard polling != currentPolling else { return }
        currentPolling = polling
        processSource.setPolling(polling)
    }

    func tearDownEngine(_ id: String) {
        engines.removeValue(forKey: id)?.stop()
        meterLevels[id] = nil
    }

    func tearDownAllEngines() {
        for id in engines.keys { tearDownEngine(id) }
    }

    private func recordFailure(_ error: any Error, for id: String, mode: EngineMode) {
        let summary = switch mode {
        case .control: "Hush couldn't control this app's audio, so it's playing normally."
        case .meterOnly: "Hush couldn't read this app's level."
        }
        engineErrors[id] = "\(summary) (\(error))"
        if mode == .meterOnly { meterOnlyErrorIDs.insert(id) } else { meterOnlyErrorIDs.remove(id) }
        logger.error("Engine for \(id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
    }
}

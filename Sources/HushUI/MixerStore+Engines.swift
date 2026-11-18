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
            if let existing,
                applyInPlace(to: existing, id: id, processObjectIDs: app.processObjectIDs, mode: mode, setting: setting)
            {
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
        cancelHealthCheck()  // every engine is about to restart; a pending check is moot
        engineErrors = [:]
        rebuildEngines(Array(engines.keys), onOutputDevice: device)
    }

    /// Rebuilds the engines for `ids` on `device`, dropping (and recording) any that fail.
    private func rebuildEngines(_ ids: [String], onOutputDevice device: OutputDevice) {
        // Two phases so control engines overlap their start-up: every engine restarts first (a
        // control one meter-only), then each is switched back once its IOProc has run. In the
        // typical case the waits overlap (later engines are already running when their turn
        // comes); the worst case is serial, N x (device start + 0.2 s) on the main actor.
        var started: [(id: String, engine: any AudioEngineHandle, mode: EngineMode)] = []
        for id in ids {
            guard let engine = engines[id] else { continue }
            let mode = engine.mode
            do {
                try engine.beginRebuild(outputDeviceID: device.id)
                started.append((id, engine, mode))
            } catch {
                tearDownEngine(id)
                recordFailure(error, for: id, mode: mode)
            }
        }
        for (id, engine, mode) in started {
            do {
                try engine.finishRebuild()
            } catch {
                tearDownEngine(id)
                recordFailure(error, for: id, mode: mode)
            }
        }
    }

    // MARK: Health check

    /// After a wake, every engine should still be running: an aggregate names its output by UID,
    /// so the HAL reattaches it even if the device came back under a new object ID.
    func systemDidWake() {
        scheduleHealthCheck()
    }

    /// Notes every engine's IO cycle count, then after `healthCheckDelay` rebuilds only the
    /// engines whose count hasn't moved. A stalled control engine would leave its app muted at
    /// the source with nothing replaying it; a running one is left alone, so it never blips.
    func scheduleHealthCheck() {
        cancelHealthCheck()
        guard !engines.isEmpty else { return }
        healthCheckBaseline = engines.mapValues { (engine: $0, cycles: $0.ioCycleCount) }
        let delay = healthCheckDelay
        healthCheckTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.rebuildStalledEngines()
        }
    }

    func cancelHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
        healthCheckBaseline = [:]
    }

    /// Rebuilds, on the current output, each engine that is still the one noted at the start of
    /// the check and hasn't run an IO cycle since.
    private func rebuildStalledEngines() {
        let baseline = healthCheckBaseline
        healthCheckTask = nil
        healthCheckBaseline = [:]
        guard controlsEnabled, let device = outputDevice else { return }
        let stalled = engines.compactMap { id, engine -> String? in
            guard let noted = baseline[id], noted.engine === engine, noted.cycles == engine.ioCycleCount else {
                return nil
            }
            return id
        }
        guard !stalled.isEmpty else { return }
        logger.notice(
            "Rebuilding \(stalled.count) stalled engine(s): \(stalled.sorted().joined(separator: ", "), privacy: .public)"
        )
        rebuildEngines(stalled, onOutputDevice: device)
        reconcile()
        rebuildStrips()
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
            logger.error(
                "In-place change for \(id, privacy: .public) failed, rebuilding: \(String(describing: error), privacy: .public)"
            )
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
        cancelHealthCheck()
        for id in engines.keys { tearDownEngine(id) }
    }

    private func recordFailure(_ error: any Error, for id: String, mode: EngineMode) {
        let summary =
            switch mode {
            case .control: String(localized: L10n.controlFailed)
            case .meterOnly: String(localized: L10n.meterFailed)
            }
        engineErrors[id] = String(localized: L10n.failureDetail(summary, "\(error)"))
        if mode == .meterOnly { meterOnlyErrorIDs.insert(id) } else { meterOnlyErrorIDs.remove(id) }
        logger.error("Engine for \(id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
    }
}

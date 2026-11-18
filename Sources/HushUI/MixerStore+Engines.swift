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
        stallRetryIDs = []
        rebuildEngines(Array(engines.keys), onOutputDevice: device)
    }

    /// Rebuilds the engines for `ids` on `device`, dropping (and recording) any that fail.
    /// Returns the IDs that failed.
    @discardableResult
    private func rebuildEngines(_ ids: [String], onOutputDevice device: OutputDevice) -> [String] {
        var failed: [String] = []
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
                failed.append(id)
            }
        }
        for (id, engine, mode) in started {
            do {
                try engine.finishRebuild()
            } catch {
                tearDownEngine(id)
                recordFailure(error, for: id, mode: mode)
                failed.append(id)
            }
        }
        return failed
    }

    // MARK: Health check

    /// After a wake, every engine should still be running: an aggregate names its output by UID,
    /// so the HAL reattaches it even if the device came back under a new object ID.
    func systemDidWake() {
        scheduleHealthCheck()
    }

    /// Checks every engine in two stages and rebuilds only the ones confirmed unhealthy: no IO
    /// cycle since the previous reading, or an aggregate whose active sub-devices don't include
    /// the current output. The first check, after `healthCheckDelay`, only picks out suspects;
    /// the confirmation, `stallConfirmDelay` later, rebuilds the suspects that are still
    /// unhealthy. Devices often take more than a few hundred milliseconds to resume IO after a
    /// wake, and rebuilding an engine that would have recovered brings back the blip this check
    /// exists to avoid. An engine that is healthy at either check is never touched.
    func scheduleHealthCheck() {
        cancelHealthCheck()
        guard !engines.isEmpty else { return }
        healthReadings = readings(of: Array(engines.keys))
        let first = healthCheckDelay
        let confirm = stallConfirmDelay
        healthCheckTask = Task { [weak self] in
            try? await Task.sleep(for: first)
            guard !Task.isCancelled, self?.checkHealth(confirming: false) == true else { return }
            try? await Task.sleep(for: confirm)
            guard !Task.isCancelled else { return }
            self?.checkHealth(confirming: true)
        }
    }

    func cancelHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
        healthReadings = [:]
    }

    /// One stage of the health check (see `scheduleHealthCheck`). The first stage keeps only the
    /// suspects, with fresh readings, and returns whether there are any. The confirming stage
    /// rebuilds the suspects that are still unhealthy and ends the check.
    @discardableResult
    func checkHealth(confirming: Bool) -> Bool {
        guard controlsEnabled, let device = outputDevice else {
            cancelHealthCheck()
            return false
        }
        let suspects = engines.compactMap { id, engine -> String? in
            guard let noted = healthReadings[id], noted.engine === engine else { return nil }
            let stalled = noted.cycles == engine.ioCycleCount
            // nil means the list couldn't be read, which is no evidence either way.
            let detached = engine.isAttached(toOutputDeviceID: device.id) == false
            return stalled || detached ? id : nil
        }
        guard confirming else {
            healthReadings = readings(of: suspects)
            if suspects.isEmpty { healthCheckTask = nil }
            return !suspects.isEmpty
        }
        healthCheckTask = nil
        healthReadings = [:]
        guard !suspects.isEmpty else { return false }
        logger.notice(
            "Rebuilding \(suspects.count) stalled engine(s): \(suspects.sorted().joined(separator: ", "), privacy: .public)"
        )
        let failed = rebuildEngines(suspects, onOutputDevice: device)
        if !failed.isEmpty { scheduleStallRetry(for: failed) }
        reconcile()
        rebuildStrips()
        return false
    }

    private func readings(of ids: [String]) -> [String: EngineReading] {
        var readings: [String: EngineReading] = [:]
        for id in ids {
            guard let engine = engines[id] else { continue }
            readings[id] = EngineReading(engine: engine, cycles: engine.ioCycleCount)
        }
        return readings
    }

    /// A stall rebuild can fail because the device isn't ready yet after a wake. Unlike other
    /// failures, these don't wait for the user: they're cleared (so `reconcile` tries again) on
    /// the next output or device-list change, or once after `stallRetryDelay`, whichever is first.
    private func scheduleStallRetry(for ids: [String]) {
        stallRetryIDs.formUnion(ids)
        stallRetryTask?.cancel()
        let delay = stallRetryDelay
        stallRetryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.retryStalledEngines()
        }
    }

    /// Clears the errors left by failed stall rebuilds and reconciles, which builds those
    /// engines again. A failure this time is an ordinary one.
    func retryStalledEngines() {
        guard clearStallRetries() else { return }
        reconcile()
        rebuildStrips()
    }

    /// Clears the errors left by failed stall rebuilds, without reconciling. Returns whether
    /// there were any.
    @discardableResult
    func clearStallRetries() -> Bool {
        stallRetryTask?.cancel()
        stallRetryTask = nil
        guard !stallRetryIDs.isEmpty else { return false }
        for id in stallRetryIDs { engineErrors[id] = nil }
        stallRetryIDs = []
        return true
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
        stallRetryIDs.remove(id)  // the stall path marks its own failures retryable afterwards
        if mode == .meterOnly { meterOnlyErrorIDs.insert(id) } else { meterOnlyErrorIDs.remove(id) }
        logger.error("Engine for \(id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
    }
}

/// One engine and its IO cycle count at a health-check reading. The reference is weak, so a
/// pending check never keeps a stopped engine alive, and a replaced engine never matches.
struct EngineReading {
    weak var engine: (any AudioEngineHandle)?
    let cycles: UInt32
}

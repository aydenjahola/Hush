import Foundation
import HushAudio
import HushCore

/// Meter sampling: ballistics state, the ~30 Hz polling task and its publishing to the per-strip meters.
extension MixerStore {
    /// The live meter for a strip. Only `LevelMeter` should read its value.
    func meter(for id: String) -> StripMeter { meterBank.meter(for: id) }

    /// Advances the ballistics and publishes to the per-strip meters, which notify their views
    /// only when the displayed height changes by a step.
    func tickMeters(elapsed: Double) {
        guard !engines.isEmpty || !meterLevels.isEmpty || !meterBank.isSilent else { return }
        for id in meterLevels.keys where engines[id] == nil { meterLevels[id] = nil }
        for (id, engine) in engines {
            meterLevels[id] = MeterBallistics.next(
                displayed: meterLevels[id] ?? 0,
                peak: engine.currentPeak(),
                elapsed: elapsed)
        }
        meterBank.publish(meterLevels)
    }

    /// About 30 Hz. Engines report the peak since the last read, so no peak is missed between ticks.
    static let meterInterval: Duration = .milliseconds(33)
    /// About 10%: lets the system coalesce meter wakeups; the ballistics use the real elapsed time.
    static let meterTolerance: Duration = meterInterval / 10

    func startMeterPolling() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.meterInterval, tolerance: Self.meterTolerance)
                guard !Task.isCancelled, let self else { break }
                let current = clock.now
                let elapsed = (current - last) / .seconds(1)
                last = current
                self.tickMeters(elapsed: elapsed)
            }
        }
    }

    func stopMeterPolling() {
        meterTask?.cancel()
        meterTask = nil
    }

    /// Clears every meter (popover closed, or meters switched off).
    func clearMeterLevels() {
        meterLevels = [:]
        meterBank.publish(meterLevels)
    }
}

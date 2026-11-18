import HushCore
import Observation

/// One strip's live level, observed only by its `LevelMeter`. A meter tick writes here instead of
/// to `MixerStore`'s observed state, so it re-renders the meter and nothing else (R-C1).
@MainActor
@Observable
final class StripMeter {
    /// Meter height steps: 1/100 of full scale is 0.6 dB on the -60...0 dB meter, about a point
    /// on the tallest meter. Smaller changes aren't visible, so they aren't published.
    static let steps: Float = 100

    /// 0...1 on the -60...0 dB scale, quantized to `1 / steps`.
    private(set) var fraction: Float = 0

    init(fraction: Float = 0) {
        self.fraction = fraction
    }

    /// Publishes the level's display fraction if it moved by at least one step.
    /// Returns whether it changed (observers are notified only then).
    @discardableResult
    func update(level: Float) -> Bool {
        let quantized = (MeterBallistics.fraction(forLevel: level) * Self.steps).rounded() / Self.steps
        guard quantized != fraction else { return false }
        fraction = quantized
        return true
    }
}

/// Owns the per-strip meters. Not observable itself: views get their meter once and observe it.
@MainActor
final class MeterBank {
    private var meters: [String: StripMeter] = [:]

    func meter(for id: String) -> StripMeter {
        if let meter = meters[id] { return meter }
        let meter = StripMeter()
        meters[id] = meter
        return meter
    }

    /// Pushes the latest ballistics levels; apps without a level fall to zero.
    func publish(_ levels: [String: Float]) {
        for (id, meter) in meters {
            meter.update(level: levels[id] ?? 0)
        }
    }

    /// Drops meters for apps that no longer have a strip.
    func retain(only ids: Set<String>) {
        for id in meters.keys where !ids.contains(id) { meters[id] = nil }
    }

    var count: Int { meters.count }

    /// True when every meter shows zero, so an idle tick has nothing to publish.
    var isSilent: Bool { meters.values.allSatisfy { $0.fraction == 0 } }
}

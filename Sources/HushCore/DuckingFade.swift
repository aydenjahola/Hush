import Foundation

/// The ducking multiplier over time: 1 while nothing is ducked, `DuckingSettings.duckedGain`
/// while a call is on, and a smooth fade between them.
///
/// The fade is a smoothstep on gain (3t² − 2t³): it leaves and arrives gently, so neither end
/// clicks or lurches, and it handles a target of 0 (where a fade in equal dB steps would need an
/// arbitrary floor). Down takes `downDuration` so the call is clear quickly; up takes
/// `upDuration` so the music comes back gently. Retargeting mid-fade starts from the current
/// value, so nothing ever jumps.
///
/// Pure: the caller passes the time, so tests need no clock.
package struct DuckingFade: Equatable, Sendable {
    /// How long lowering takes.
    package static let downDuration: TimeInterval = 0.4
    /// How long restoring (or any fade upwards, such as a smaller amount) takes.
    package static let upDuration: TimeInterval = 1.0

    private var from: Float = 1
    package private(set) var target: Float = 1
    private var start: Date = .distantPast
    private var duration: TimeInterval = 0

    package init() {}

    /// The multiplier at `now`.
    package func multiplier(at now: Date) -> Float {
        guard let endTime, now < endTime else { return target }
        let elapsed = now.timeIntervalSince(start)
        if elapsed <= 0 { return from }
        let t = Float(min(elapsed / duration, 1))
        let eased = t * t * (3 - 2 * t)
        return from + (target - from) * eased
    }

    /// Starts fading from the current value to `target` (clamped to 0...1). The same target
    /// leaves a running fade alone.
    package mutating func retarget(_ target: Float, at now: Date) {
        let target = min(max(target, 0), 1)
        guard target != self.target else { return }
        let current = multiplier(at: now)
        from = current
        self.target = target
        start = now
        duration = target < current ? Self.downDuration : Self.upDuration
    }

    /// True once the fade has reached its target.
    package func isSettled(at now: Date) -> Bool {
        endTime.map { now >= $0 } ?? true
    }

    /// True when nothing is ducked or fading: settled at 1.
    package func isIdle(at now: Date) -> Bool {
        target == 1 && isSettled(at: now)
    }

    /// When the current fade reaches its target; nil if there has never been one.
    package var endTime: Date? {
        duration > 0 ? start.addingTimeInterval(duration) : nil
    }
}

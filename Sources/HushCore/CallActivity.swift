import Foundation

/// Debounces which call apps are in a call, from the apps capturing microphone input over time.
///
/// An app counts once it has captured for `startDelay`, so a momentary microphone probe never
/// ducks anything. It keeps counting for `stopDelay` after it stops, so muting and unmuting in a
/// call app (which can stop and restart input) doesn't bring the other apps back up in between.
/// Resuming within that hold counts again at once, without a new start delay.
///
/// Pure: the caller passes the time with every call, so tests need no real clock or timers.
package struct CallActivity: Equatable, Sendable {
    /// How long an app must capture before it counts as in a call.
    package static let startDelay: TimeInterval = 0.5
    /// How long an app keeps counting after it stops capturing.
    package static let stopDelay: TimeInterval = 2

    /// When each capturing app started capturing (its first report, not its latest).
    private var capturingSince: [String: Date] = [:]
    /// Apps that stopped while they counted, and until when they keep counting.
    private var heldUntil: [String: Date] = [:]

    package init() {}

    /// Records the apps capturing input at `now`. Apps missing from `capturing` have stopped.
    package mutating func update(capturing: Set<String>, at now: Date) {
        heldUntil = heldUntil.filter { $0.value > now }
        for (id, since) in capturingSince where !capturing.contains(id) {
            if counts(id, since: since, at: now) {
                heldUntil[id] = now.addingTimeInterval(Self.stopDelay)
            }
            capturingSince[id] = nil
        }
        for id in capturing where capturingSince[id] == nil {
            if let until = heldUntil[id], until > now {
                // Resuming during the hold: it already counts, so carry that over (as if it had
                // captured for the start delay) and end the hold. Keeping the hold with a fresh
                // start time would drop the app between the hold's end and the new start delay.
                capturingSince[id] = now.addingTimeInterval(-Self.startDelay)
                heldUntil[id] = nil
            } else {
                capturingSince[id] = now
            }
        }
    }

    /// The apps in a call at `now`.
    package func activeApps(at now: Date) -> Set<String> {
        var active: Set<String> = []
        for (id, since) in capturingSince where counts(id, since: since, at: now) { active.insert(id) }
        for (id, until) in heldUntil where until > now { active.insert(id) }
        return active
    }

    /// The next moment after `now` when `activeApps` can change without a new `update`: a start
    /// delay running out or a hold ending. Nil when nothing is pending.
    package func nextChange(after now: Date) -> Date? {
        let starts = capturingSince.values.map { $0.addingTimeInterval(Self.startDelay) }
        let stops = heldUntil.values
        return (starts + stops).filter { $0 > now }.min()
    }

    package mutating func reset() {
        capturingSince = [:]
        heldUntil = [:]
    }

    private func counts(_ id: String, since: Date, at now: Date) -> Bool {
        now.timeIntervalSince(since) >= Self.startDelay || (heldUntil[id].map { $0 > now } ?? false)
    }
}

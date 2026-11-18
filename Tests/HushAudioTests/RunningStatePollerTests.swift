import CoreAudio
import Synchronization
import Testing
@testable import HushAudio

@MainActor
final class FakeRunningReader {
    var values: [AudioObjectID: Bool] = [:]
    private(set) var reads: [AudioObjectID] = []
    func read(_ id: AudioObjectID) -> Bool {
        reads.append(id)
        return values[id] ?? false
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1))) struct RunningStatePollerTests {
    func makePoller(_ reader: FakeRunningReader, sleeper: FakeSleeper = FakeSleeper()) -> (
        RunningStatePoller, () -> [[AudioObjectID: Bool]]
    ) {
        var changes: [[AudioObjectID: Bool]] = []
        let poller = RunningStatePoller(
            interval: .seconds(1),
            read: { reader.read($0) },
            onChange: { changes.append($0) },
            sleep: { try await sleeper.sleep($0) })
        return (poller, { changes })
    }

    @Test func readsOnlyTheTargets() {
        let reader = FakeRunningReader()
        reader.values = [1: true, 2: false, 3: true]
        let (poller, changes) = makePoller(reader)
        poller.record([1: true, 2: false, 3: true])
        poller.setTargets([2])

        #expect(poller.poll() == false)
        #expect(reader.reads == [2], "objects nothing depends on aren't read")
        #expect(changes().isEmpty)
    }

    @Test func reportsOnlyTheValuesThatChanged() {
        // The live Zen/YouTube case: an existing process object flips 1 -> 0 -> 1 with no HAL notification.
        let reader = FakeRunningReader()
        reader.values = [7: true, 8: true]
        let (poller, changes) = makePoller(reader)
        poller.record([7: true, 8: true])
        poller.setTargets([7, 8])

        reader.values[7] = false
        #expect(poller.poll() == true)
        #expect(changes() == [[7: false]])
        #expect(poller.poll() == false, "the new reading becomes the snapshot")

        reader.values[7] = true
        #expect(poller.poll() == true)
        #expect(changes() == [[7: false], [7: true]])
    }

    @Test func recordReplacesTheSnapshot() {
        let reader = FakeRunningReader()
        reader.values = [1: false, 3: true]
        let (poller, changes) = makePoller(reader)
        poller.record([1: true])
        poller.setTargets([1, 3])

        poller.record([1: false, 3: true])  // a refresh already saw the new state
        #expect(poller.poll() == false)
        #expect(changes().isEmpty)
    }

    @Test func noTargetsReadsNothing() {
        let reader = FakeRunningReader()
        let (poller, changes) = makePoller(reader)
        poller.record([1: true])
        #expect(poller.poll() == false)
        #expect(reader.reads.isEmpty)
        #expect(changes().isEmpty)
    }

    @Test func toleranceIsATenthOfTheInterval() {
        #expect(RunningStatePoller.tolerance(for: .seconds(1)) == .milliseconds(100))
    }

    @Test func targetsStartTheLoopAndNoTargetsStopIt() async throws {
        let reader = FakeRunningReader()
        reader.values = [1: false]
        let sleeper = FakeSleeper()
        let (poller, changes) = makePoller(reader, sleeper: sleeper)
        poller.record([1: true])
        await settle()
        #expect(sleeper.requested.isEmpty, "nothing to poll, no timer")

        poller.setTargets([1])
        try await waitUntil { sleeper.waiting == [.seconds(1)] }
        sleeper.wakeAll()
        try await waitUntil { changes().count == 1 && sleeper.waiting.count == 1 }

        poller.setTargets([])
        try await waitUntil { sleeper.waiting.isEmpty }
        let readsAtStop = reader.reads.count
        reader.values[1] = true
        sleeper.wakeAll()
        await settle()
        #expect(reader.reads.count == readsAtStop, "no polling without targets")
        #expect(changes().count == 1)
    }

    @Test func changingTargetsWhileRunningKeepsOneLoop() async throws {
        let reader = FakeRunningReader()
        reader.values = [1: true, 2: true]
        let sleeper = FakeSleeper()
        let (poller, _) = makePoller(reader, sleeper: sleeper)
        poller.record([1: true, 2: true])
        poller.setTargets([1])
        try await waitUntil { sleeper.waiting == [.seconds(1)] }

        poller.setTargets([1, 2])
        await settle()
        #expect(sleeper.waiting == [.seconds(1)], "still one loop")
        sleeper.wakeAll()
        try await waitUntil { sleeper.requested.count == 2 }
        await settle()
        #expect(Set(reader.reads) == [1, 2], "the next poll reads the new targets")
        #expect(reader.reads.count == 2, "one loop, one poll per wake")
        poller.stop()
    }

    @Test func stopEndsTheLoop() async throws {
        let reader = FakeRunningReader()
        let sleeper = FakeSleeper()
        let (poller, _) = makePoller(reader, sleeper: sleeper)
        poller.setTargets([1])
        try await waitUntil { sleeper.waiting.count == 1 }
        poller.stop()
        try await waitUntil { sleeper.waiting.isEmpty }
        #expect(poller.targets.isEmpty)
    }
}

/// A sleep that suspends until the test wakes it, so poll timing is deterministic.
final class FakeSleeper: Sendable {
    private struct Waiter {
        let id: Int
        let duration: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }
    private struct State {
        var nextID = 0
        var waiters: [Waiter] = []
        var cancelled: Set<Int> = []
        var requested: [Duration] = []
    }
    private let state = Mutex(State())

    /// Every duration ever requested, in order.
    var requested: [Duration] { state.withLock { $0.requested } }
    /// Durations of sleeps currently suspended.
    var waiting: [Duration] { state.withLock { $0.waiters.map(\.duration) } }

    func sleep(_ duration: Duration) async throws {
        let id = state.withLock { s in
            s.nextID += 1
            s.requested.append(duration)
            return s.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let cancelledEarly = state.withLock { s in
                    if s.cancelled.remove(id) != nil { return true }
                    s.waiters.append(Waiter(id: id, duration: duration, continuation: continuation))
                    return false
                }
                if cancelledEarly { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let waiter = state.withLock { s -> Waiter? in
                guard let index = s.waiters.firstIndex(where: { $0.id == id }) else {
                    s.cancelled.insert(id)
                    return nil
                }
                return s.waiters.remove(at: index)
            }
            waiter?.continuation.resume(throwing: CancellationError())
        }
    }

    func wakeAll() {
        let waiters = state.withLock { s in
            defer { s.waiters = [] }
            return s.waiters
        }
        for waiter in waiters { waiter.continuation.resume() }
    }
}

struct TimedOut: Error {}

/// Yields to the scheduler until `condition` holds (generous bound, no wall-clock sleeps).
@MainActor
func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<10_000 {
        if condition() { return }
        await Task.yield()
    }
    throw TimedOut()
}

/// Gives any stray loop a chance to run before asserting that it didn't.
@MainActor
func settle() async {
    for _ in 0..<200 { await Task.yield() }
}

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
@Suite struct RunningStatePollerTests {
    func makePoller(_ reader: FakeRunningReader, sleeper: FakeSleeper = FakeSleeper()) -> (RunningStatePoller, () -> Int) {
        var changes = 0
        let poller = RunningStatePoller(
            fastInterval: .seconds(1), slowInterval: .seconds(3),
            read: { reader.read($0) },
            onChange: { changes += 1 },
            sleep: { try await sleeper.sleep($0) })
        return (poller, { changes })
    }

    @Test func unchangedReadingsDoNotFire() {
        let reader = FakeRunningReader()
        reader.values = [1: true, 2: false]
        let (poller, changes) = makePoller(reader)
        poller.record([1: true, 2: false])

        #expect(poller.poll() == false)
        #expect(poller.poll() == false)
        #expect(changes() == 0)
        #expect(Set(reader.reads) == [1, 2], "only the known objects are read")
    }

    @Test func pausedThenResumedPlaybackFiresEachTime() {
        // The live Zen/YouTube case: an existing process object flips 1 -> 0 -> 1 with no HAL notification.
        let reader = FakeRunningReader()
        reader.values = [7: true]
        let (poller, changes) = makePoller(reader)
        poller.record([7: true])

        reader.values[7] = false
        #expect(poller.poll() == true)
        #expect(changes() == 1)
        #expect(poller.poll() == false, "the new reading becomes the snapshot")

        reader.values[7] = true
        #expect(poller.poll() == true)
        #expect(changes() == 2)
    }

    @Test func recordReplacesTheSnapshot() {
        let reader = FakeRunningReader()
        reader.values = [1: false, 3: true]
        let (poller, changes) = makePoller(reader)
        poller.record([1: true])

        poller.record([1: false, 3: true])   // a full refresh already saw the new state
        #expect(poller.poll() == false)
        #expect(changes() == 0)
    }

    @Test func emptySnapshotReadsNothing() {
        let reader = FakeRunningReader()
        let (poller, changes) = makePoller(reader)
        #expect(poller.poll() == false)
        #expect(reader.reads.isEmpty)
        #expect(changes() == 0)
    }

    @Test func intervalFollowsFastPolling() {
        let (poller, _) = makePoller(FakeRunningReader())
        #expect(poller.interval == .seconds(3))
        poller.setFast(true)
        #expect(poller.interval == .seconds(1))
        poller.setFast(false)
        #expect(poller.interval == .seconds(3))
    }

    @Test func timerPollsUntilStopped() async throws {
        let reader = FakeRunningReader()
        reader.values = [1: false]
        let sleeper = FakeSleeper()
        let (poller, changes) = makePoller(reader, sleeper: sleeper)
        poller.record([1: true])
        poller.start()

        try await waitUntil { sleeper.waiting == [.seconds(3)] }
        sleeper.wakeAll()
        try await waitUntil { changes() == 1 && sleeper.waiting.count == 1 }

        poller.stop()
        try await waitUntil { sleeper.waiting.isEmpty }
        let readsAtStop = reader.reads.count
        reader.values[1] = true
        sleeper.wakeAll()
        await settle()
        #expect(reader.reads.count == readsAtStop, "no polling after stop")
        #expect(changes() == 1)
    }

    @Test func setFastWhileRunningLeavesOneLoopAtTheNewCadence() async throws {
        let reader = FakeRunningReader()
        reader.values = [1: true]
        let sleeper = FakeSleeper()
        let (poller, _) = makePoller(reader, sleeper: sleeper)
        poller.record([1: true])
        poller.start()
        try await waitUntil { sleeper.waiting == [.seconds(3)] }

        poller.setFast(true)
        try await waitUntil { sleeper.waiting == [.seconds(1)] }
        await settle()
        #expect(sleeper.waiting == [.seconds(1)], "the slow loop was cancelled, not left running")

        sleeper.wakeAll()
        try await waitUntil { sleeper.requested.count == 3 }
        await settle()
        #expect(sleeper.requested == [.seconds(3), .seconds(1), .seconds(1)])
        #expect(sleeper.waiting == [.seconds(1)])
        #expect(reader.reads.count == 1, "one loop, one poll per wake")

        poller.setFast(true)   // unchanged: no restart
        await settle()
        #expect(sleeper.requested.count == 3)
        poller.stop()
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

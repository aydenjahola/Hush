import CoreAudio
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
    func makePoller(_ reader: FakeRunningReader, fast: Duration = .seconds(1), slow: Duration = .seconds(3)) -> (RunningStatePoller, () -> Int) {
        var changes = 0
        let poller = RunningStatePoller(
            fastInterval: fast, slowInterval: slow,
            read: { reader.read($0) },
            onChange: { changes += 1 })
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
        let (poller, changes) = makePoller(reader, fast: .milliseconds(10), slow: .milliseconds(10))
        poller.record([1: true])
        poller.start()
        try await Task.sleep(for: .milliseconds(100))
        #expect(changes() == 1)

        poller.stop()
        let readsAtStop = reader.reads.count
        reader.values[1] = true
        try await Task.sleep(for: .milliseconds(60))
        #expect(reader.reads.count == readsAtStop, "no polling after stop")
        #expect(changes() == 1)
    }
}

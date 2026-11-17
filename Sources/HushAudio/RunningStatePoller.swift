import CoreAudio

/// Re-reads each known process object's running flag on a timer and reports when any differs
/// from the last snapshot. The HAL doesn't reliably notify `IsRunning`/`IsRunningOutput` changes
/// for process objects that already exist (seen with a browser pausing and resuming a video),
/// so listeners alone can miss playback starting again.
@MainActor
final class RunningStatePoller {
    typealias Reader = @MainActor (AudioObjectID) -> Bool
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    private let fastInterval: Duration
    private let slowInterval: Duration
    private let read: Reader
    private let onChange: @MainActor () -> Void
    private let sleep: Sleeper
    private var snapshot: [AudioObjectID: Bool] = [:]
    private var task: Task<Void, Never>?
    private var isFast = false

    init(
        fastInterval: Duration,
        slowInterval: Duration,
        read: @escaping Reader,
        onChange: @escaping @MainActor () -> Void,
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.sleep = sleep
        self.fastInterval = fastInterval
        self.slowInterval = slowInterval
        self.read = read
        self.onChange = onChange
    }

    var interval: Duration { isFast ? fastInterval : slowInterval }

    /// Stores the running state a full refresh just read, so the next poll compares against it.
    func record(_ snapshot: [AudioObjectID: Bool]) {
        self.snapshot = snapshot
    }

    /// Reads the known objects; calls `onChange` and returns true only if any value changed.
    @discardableResult
    func poll() -> Bool {
        var fresh: [AudioObjectID: Bool] = [:]
        fresh.reserveCapacity(snapshot.count)
        for id in snapshot.keys { fresh[id] = read(id) }
        guard fresh != snapshot else { return false }
        snapshot = fresh
        onChange()
        return true
    }

    func setFast(_ fast: Bool) {
        guard fast != isFast else { return }
        isFast = fast
        if task != nil { start() }  // apply the new interval now, not after the old sleep
    }

    func start() {
        task?.cancel()
        let sleep = self.sleep
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.interval else { return }
                try? await sleep(interval)
                guard !Task.isCancelled, let self else { return }
                self.poll()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

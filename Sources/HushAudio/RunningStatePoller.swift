import CoreAudio

/// Re-reads the running flag of the process objects something depends on, on a timer, and reports
/// the ones that differ from the last snapshot. The HAL doesn't reliably notify `IsRunningOutput`
/// changes for process objects that already exist (seen with a browser pausing and resuming a
/// video), so listeners alone can miss playback starting again.
///
/// It reads only `targets` and runs only while there are any: each read is a synchronous round
/// trip to coreaudiod, and with nothing adjusted and the popover closed no decision depends on it.
@MainActor
final class RunningStatePoller {
    typealias Reader = @MainActor (AudioObjectID) -> Bool
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    /// Lets the system coalesce the wakeup with others (and App Nap work) instead of firing exactly on time.
    nonisolated static func tolerance(for interval: Duration) -> Duration { interval / 10 }

    private(set) var targets: Set<AudioObjectID> = []
    private let interval: Duration
    private let read: Reader
    private let onChange: @MainActor ([AudioObjectID: Bool]) -> Void
    private let sleep: Sleeper
    private var snapshot: [AudioObjectID: Bool] = [:]
    private var task: Task<Void, Never>?

    init(
        interval: Duration,
        read: @escaping Reader,
        onChange: @escaping @MainActor ([AudioObjectID: Bool]) -> Void,
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0, tolerance: RunningStatePoller.tolerance(for: $0)) }
    ) {
        self.interval = interval
        self.read = read
        self.onChange = onChange
        self.sleep = sleep
    }

    /// Stores the running state a refresh just read, so the next poll compares against it.
    func record(_ snapshot: [AudioObjectID: Bool]) {
        self.snapshot = snapshot
    }

    /// Chooses what to poll. An empty set stops the timer; a non-empty one starts it if needed.
    func setTargets(_ targets: Set<AudioObjectID>) {
        guard targets != self.targets else { return }
        self.targets = targets
        if targets.isEmpty {
            task?.cancel()
            task = nil
        } else if task == nil {
            startLoop()
        }
    }

    /// Reads the targets; calls `onChange` with the changed values and returns true if any changed.
    @discardableResult
    func poll() -> Bool {
        var changed: [AudioObjectID: Bool] = [:]
        for id in targets {
            let value = read(id)
            if snapshot[id] != value {
                snapshot[id] = value
                changed[id] = value
            }
        }
        guard !changed.isEmpty else { return false }
        onChange(changed)
        return true
    }

    func stop() {
        setTargets([])
    }

    private func startLoop() {
        let sleep = self.sleep
        let interval = self.interval
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await sleep(interval)
                guard !Task.isCancelled, let self else { return }
                self.poll()
            }
        }
    }
}

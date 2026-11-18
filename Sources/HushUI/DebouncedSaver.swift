import Foundation

/// Coalesces rapid changes into one write: `schedule()` arms (or re-arms) a timer, and when it
/// fires, or on `flush()`, the pending write is performed once.
@MainActor
final class DebouncedSaver {
    private let delay: Duration
    private var task: Task<Void, Never>?
    private var hasPending = false
    /// Performs the write. Set once, right after the owner finishes initializing.
    var perform: @MainActor () -> Void = {}

    init(delay: Duration) {
        self.delay = delay
    }

    func schedule() {
        hasPending = true
        task?.cancel()
        let delay = delay
        task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Cancels the timer and writes now if anything is pending.
    func flush() {
        task?.cancel()
        task = nil
        guard hasPending else { return }
        hasPending = false
        perform()
    }
}

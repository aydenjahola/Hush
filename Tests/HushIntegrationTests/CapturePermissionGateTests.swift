import HushAudio
import Testing

@MainActor
final class FakePermissionSource: AudioCapturePermissionSource {
    var status: AudioCapturePermissionStatus
    /// What `requestAccess()` answers; nil never answers (nobody clicks).
    var answer: AudioCapturePermissionStatus?
    private(set) var requests = 0

    init(status: AudioCapturePermissionStatus, answer: AudioCapturePermissionStatus? = nil) {
        self.status = status
        self.answer = answer
    }

    func currentStatus() -> AudioCapturePermissionStatus { status }

    func requestAccess() async -> AudioCapturePermissionStatus {
        requests += 1
        guard let answer else {
            while true { try? await Task.sleep(for: .seconds(3600)) }
        }
        return answer
    }
}

/// The permission gate's decisions. Plain unit tests with a fake source: they run in every
/// `swift test` and never touch TCC.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct CapturePermissionGateTests {
    @Test func authorizedRunsWithoutRequesting() async {
        let source = FakePermissionSource(status: .authorized)
        #expect(await CapturePermissionGate.resolve(source, mayRequest: true, timeout: .seconds(1)))
        #expect(source.requests == 0)
    }

    @Test func deniedSkipsWithoutRequesting() async {
        let source = FakePermissionSource(status: .denied, answer: .authorized)
        #expect(await CapturePermissionGate.resolve(source, mayRequest: true, timeout: .seconds(1)) == false)
        #expect(source.requests == 0)
    }

    @Test func undeterminedUnderCINeverRequests() async {
        let source = FakePermissionSource(status: .undetermined, answer: .authorized)
        #expect(await CapturePermissionGate.resolve(source, mayRequest: false, timeout: .seconds(1)) == false)
        #expect(source.requests == 0, "CI must never request permission")
    }

    @Test func undeterminedLocallyRequestsOnceAndRunsWhenGranted() async {
        let source = FakePermissionSource(status: .undetermined, answer: .authorized)
        #expect(await CapturePermissionGate.resolve(source, mayRequest: true, timeout: .seconds(1)))
        #expect(source.requests == 1)
    }

    @Test func undeterminedLocallySkipsWhenDenied() async {
        let source = FakePermissionSource(status: .undetermined, answer: .denied)
        #expect(await CapturePermissionGate.resolve(source, mayRequest: true, timeout: .seconds(1)) == false)
        #expect(source.requests == 1)
    }

    @Test func unansweredPromptTimesOutAndSkips() async {
        // No wall-clock upper bound: a loaded runner can stall the whole batch. A real hang is caught
        // by the suite's `.timeLimit` trait.
        let source = FakePermissionSource(status: .undetermined, answer: nil)
        #expect(await CapturePermissionGate.resolve(source, mayRequest: true, timeout: .milliseconds(100)) == false)
        #expect(source.requests == 1)
    }
}

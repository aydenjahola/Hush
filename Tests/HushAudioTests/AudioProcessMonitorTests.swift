import CoreAudio
import Testing
@testable import HushAudio

struct FakeHALError: Error {}

@MainActor
final class FakeProcessHAL: ProcessHAL {
    struct Key: Hashable {
        let object: AudioObjectID
        let selector: AudioObjectPropertySelector
    }

    var objects: [AudioObjectID] = []
    var listError: (any Error)?
    var pids: [AudioObjectID: pid_t] = [:]
    var bundleIDs: [AudioObjectID: String] = [:]
    var running: [AudioObjectID: Bool] = [:]
    /// Remaining failures per object for the bundle-ID read and for adding a running listener.
    var bundleIDFailures: [AudioObjectID: Int] = [:]
    var listenerRefusals: [AudioObjectID: Int] = [:]
    private(set) var listReads = 0
    private(set) var pidReads: [AudioObjectID] = []
    private(set) var bundleIDReads: [AudioObjectID] = []
    private(set) var runningReads: [AudioObjectID] = []
    private(set) var listeners: [Key: @MainActor () -> Void] = [:]

    func processObjects() throws -> [AudioObjectID] {
        listReads += 1
        if let listError { throw listError }
        return objects
    }

    func pid(of object: AudioObjectID) -> pid_t? {
        pidReads.append(object)
        return pids[object]
    }

    func bundleID(of object: AudioObjectID) throws -> String? {
        bundleIDReads.append(object)
        if let remaining = bundleIDFailures[object], remaining > 0 {
            bundleIDFailures[object] = remaining - 1
            throw FakeHALError()
        }
        return bundleIDs[object]
    }

    func isRunningOutput(_ object: AudioObjectID) -> Bool {
        runningReads.append(object)
        return running[object] ?? false
    }

    var capturing: [AudioObjectID: Bool] = [:]
    private(set) var inputReads: [AudioObjectID] = []

    func isRunningInput(_ object: AudioObjectID) -> Bool {
        inputReads.append(object)
        return capturing[object] ?? false
    }

    func fireInput(_ object: AudioObjectID) { fire(object, kAudioProcessPropertyIsRunningInput) }

    /// The selectors with a listener on `object`.
    func selectors(on object: AudioObjectID) -> Set<AudioObjectPropertySelector> {
        Set(listeners.keys.filter { $0.object == object }.map(\.selector))
    }

    func addListener(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ handler: @escaping @MainActor () -> Void
    ) -> HALListener? {
        if let remaining = listenerRefusals[object], remaining > 0 {
            listenerRefusals[object] = remaining - 1
            return nil
        }
        listeners[Key(object: object, selector: selector)] = handler
        return HALListener(object: object, selector: selector, block: nil)
    }

    func removeListener(_ listener: HALListener) {
        listeners[Key(object: listener.object, selector: listener.selector)] = nil
    }

    func fire(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) {
        listeners[Key(object: object, selector: selector)]?()
    }

    func fireList() { fire(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) }
    func fireRunning(_ object: AudioObjectID) { fire(object, kAudioProcessPropertyIsRunningOutput) }

    /// Adds a process object owned by its own app (`app.<pid>`).
    func add(_ object: AudioObjectID, pid: pid_t, playing: Bool = false) {
        objects.append(object)
        pids[object] = pid
        bundleIDs[object] = "app.\(pid)"
        running[object] = playing
    }

    func resetCounts() {
        listReads = 0
        pidReads = []
        bundleIDReads = []
        runningReads = []
        inputReads = []
    }
}

/// Collects scheduled flushes; the test decides when the "next turn" happens.
@MainActor
final class ManualScheduler {
    private(set) var pending: [@MainActor () -> Void] = []
    func schedule(_ work: @escaping @MainActor () -> Void) { pending.append(work) }
    func runAll() {
        let work = pending
        pending = []
        for item in work { item() }
    }
}

@MainActor
final class MonitorHarness {
    let hal = FakeProcessHAL()
    let apps = FakeRunningApps()
    let scheduler = ManualScheduler()
    let retries = ManualScheduler()
    let sleeper = FakeSleeper()
    private(set) var published: [[AudioApp]] = []
    lazy var monitor: AudioProcessMonitor = {
        let scheduler = self.scheduler
        let retries = self.retries
        let sleeper = self.sleeper
        return AudioProcessMonitor(
            hal: hal,
            resolver: AppIdentityResolver(provider: apps),
            schedule: { scheduler.schedule($0) },
            retrySchedule: { retries.schedule($0) },
            pollerSleep: { try await sleeper.sleep($0) },
            ownPID: 1,
            ownBundleID: "io.github.aydenjahola.Hush")
    }()

    func start() {
        monitor.start { [weak self] in self?.published.append($0) }
    }

    var latest: [AudioApp] { published.last ?? [] }
    func app(_ pid: pid_t) -> AudioApp? { latest.first { $0.id == "app.\(pid)" } }
}

@MainActor
@Suite(.timeLimit(.minutes(1))) struct AudioProcessMonitorTests {
    @Test func startPublishesTheCurrentApps() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100, playing: true)
        h.hal.add(11, pid: 101)
        h.start()

        #expect(h.published.count == 1)
        #expect(h.latest.map(\.id) == ["app.100", "app.101"])
        #expect(h.app(100)?.isPlaying == true)
        #expect(h.app(101)?.isPlaying == false)
    }

    @Test func failedListReadKeepsTheLastAppsInsteadOfPublishingNone() {
        // P-I1: an empty list would tear down every engine, unmuting muted apps.
        let h = MonitorHarness()
        h.hal.add(10, pid: 100, playing: true)
        h.start()

        h.hal.listError = FakeHALError()
        h.hal.fireList()
        h.scheduler.runAll()
        #expect(h.published.count == 1, "nothing published")
        #expect(h.monitor.apps.map(\.id) == ["app.100"])

        h.hal.listError = nil
        h.hal.add(11, pid: 101)
        h.hal.fireList()
        h.scheduler.runAll()
        #expect(h.latest.map(\.id) == ["app.100", "app.101"], "the next good read applies")
    }

    @Test func failedReadAtStartPublishesEmptyAndRecoversOnTheNextChange() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.hal.listError = FakeHALError()
        h.start()
        #expect(h.latest.isEmpty)

        h.hal.listError = nil
        h.hal.fireList()
        h.scheduler.runAll()
        #expect(h.latest.map(\.id) == ["app.100"])
    }

    @Test func aBurstOfListenerCallbacksIsOneFlush() {
        // One playback start fires the list listener and the running listener back to back.
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.start()
        h.hal.resetCounts()

        h.hal.add(11, pid: 101, playing: true)
        h.hal.running[10] = true
        h.hal.fireList()
        h.hal.fireRunning(10)
        h.hal.fireRunning(10)
        #expect(h.scheduler.pending.count == 1, "coalesced into one scheduled flush")

        h.scheduler.runAll()
        #expect(h.hal.listReads == 1)
        #expect(h.published.count == 2, "one publish for the whole burst")
        #expect(h.app(100)?.isPlaying == true)
        #expect(h.app(101)?.isPlaying == true)
    }

    @Test func aRunningChangeReReadsOnlyThatObject() {
        let h = MonitorHarness()
        for object in AudioObjectID(10)...AudioObjectID(19) { h.hal.add(object, pid: pid_t(object) * 10) }
        h.start()
        h.hal.resetCounts()

        h.hal.running[13] = true
        h.hal.fireRunning(13)
        h.scheduler.runAll()
        #expect(h.hal.runningReads == [13])
        #expect(h.hal.listReads == 0, "the list didn't change")
        #expect(h.hal.pidReads.isEmpty)
        #expect(h.app(130)?.isPlaying == true)
    }

    @Test func pidAndBundleIDAreReadOncePerObject() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.start()

        h.hal.add(11, pid: 101)
        h.hal.fireList()
        h.scheduler.runAll()
        h.hal.add(12, pid: 102)
        h.hal.fireList()
        h.scheduler.runAll()

        #expect(h.hal.pidReads == [10, 11, 12], "an object's PID never changes")
        #expect(h.hal.bundleIDReads == [10, 11, 12])
        #expect(h.hal.runningReads == [10, 11, 12], "new objects only")
    }

    @Test func listensOnlyToIsRunningOutputPerObject() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.start()
        let selectors = h.hal.listeners.keys.filter { $0.object == 10 }.map(\.selector)
        #expect(selectors == [kAudioProcessPropertyIsRunningOutput])
    }

    @Test func vanishedObjectsLoseTheirListenerAndCache() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.hal.add(11, pid: 101)
        h.start()

        h.hal.objects = [10]
        h.hal.fireList()
        h.scheduler.runAll()
        #expect(h.latest.map(\.id) == ["app.100"])
        #expect(!h.hal.listeners.keys.contains { $0.object == 11 })

        h.hal.objects = [10, 11]  // the HAL reuses the ID for a new process
        h.hal.pids[11] = 111
        h.hal.bundleIDs[11] = "app.111"
        h.hal.fireList()
        h.scheduler.runAll()
        #expect(h.latest.map(\.id) == ["app.100", "app.111"])
    }

    @Test func unreadablePIDIsRetriedWithoutWaitingForAListChange() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.hal.pids[10] = nil
        h.start()
        #expect(h.latest.isEmpty)
        #expect(h.retries.pending.count == 1, "a retry is scheduled")

        h.hal.pids[10] = 100
        h.retries.runAll()
        #expect(h.latest.map(\.id) == ["app.100"])
        #expect(h.hal.listReads == 1, "the retry didn't need the list again")
        #expect(h.retries.pending.isEmpty)
    }

    @Test func processWithoutABundleIDIsListedRightAway() {
        // CLI tools (afplay, HushToneGenerator) have no bundle ID: that's a value, not a failed read.
        let h = MonitorHarness()
        h.hal.add(10, pid: 100, playing: true)
        h.hal.bundleIDs[10] = nil
        h.apps.names[100] = "afplay"
        h.start()
        #expect(h.latest.map(\.id) == ["afplay"])
        #expect(h.retries.pending.isEmpty, "nothing to retry")
    }

    @Test func failedBundleIDReadIsRetriedInsteadOfCachingNoBundle() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.hal.bundleIDFailures[10] = 1
        h.start()
        #expect(h.latest.isEmpty, "not grouped under a guessed identity")

        h.retries.runAll()
        #expect(h.latest.map(\.id) == ["app.100"])
    }

    @Test func retriesAreBounded() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.hal.pids[10] = nil
        h.start()
        for _ in 0..<20 { h.retries.runAll() }
        #expect(h.hal.pidReads.count == AudioProcessMonitor.maxRetries, "gives up after a few attempts")
        #expect(h.retries.pending.isEmpty)

        h.hal.pids[10] = 100
        h.hal.add(11, pid: 101)
        h.hal.fireList()
        h.scheduler.runAll()
        #expect(h.latest.map(\.id) == ["app.100", "app.101"], "a list change starts a fresh round")
    }

    @Test func aRefusedRunningListenerIsRetried() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.hal.listenerRefusals[10] = 2
        h.start()
        #expect(h.latest.map(\.id) == ["app.100"], "the object is still listed")
        #expect(!h.hal.listeners.keys.contains { $0.object == 10 })

        h.retries.runAll()
        h.retries.runAll()
        #expect(h.hal.listeners.keys.contains { $0.object == 10 })
        #expect(h.retries.pending.isEmpty)
    }

    @Test func startAfterStopReAddsListenersAndRepublishes() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100, playing: true)
        h.start()
        h.monitor.stop()
        #expect(h.hal.listeners.isEmpty)

        h.start()
        #expect(
            h.hal.listeners.keys.contains { $0.object == 10 }, "per-object caches were cleared, so listeners come back")
        #expect(h.published.count == 2)
        #expect(h.app(100)?.isPlaying == true)
    }

    @Test func helpersGroupUnderTheirApp() {
        let h = MonitorHarness()
        h.apps.apps[100] = FakeRunningApps.regular("com.browser")
        h.apps.responsible[101] = 100
        h.hal.add(10, pid: 100)
        h.hal.add(11, pid: 101, playing: true)
        h.hal.bundleIDs[10] = "com.browser"
        h.hal.bundleIDs[11] = "com.browser.helper"
        h.start()

        #expect(h.latest.map(\.id) == ["com.browser"])
        #expect(h.latest.first?.processObjectIDs == [10, 11])
        #expect(h.latest.first?.isPlaying == true)
    }

    @Test func ownProcessIsExcluded() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 1)
        h.hal.add(11, pid: 101)
        h.start()
        #expect(h.latest.map(\.id) == ["app.101"])
    }

    @Test func appLaunchRegroupsAHelperThatWasStandalone() {
        let h = MonitorHarness()
        h.apps.responsible[201] = 200
        h.hal.add(20, pid: 201, playing: true)
        h.hal.bundleIDs[20] = "app.zen.helper"
        h.start()
        #expect(h.latest.map(\.id) == ["app.zen.helper"])

        h.apps.apps[200] = FakeRunningApps.regular("app.zen")
        h.apps.emit(.launched(200))
        #expect(h.scheduler.pending.count == 1)
        h.scheduler.runAll()
        #expect(h.latest.map(\.id) == ["app.zen"])
        #expect(h.hal.listReads == 1, "regrouping needs no HAL reads")
    }

    // MARK: Polling

    @Test func pollingIsOffUntilSomethingNeedsIt() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.hal.add(11, pid: 101)
        h.start()
        #expect(h.monitor.pollTargets.isEmpty)
    }

    @Test func pollingTargetsFollowTheDemand() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.hal.add(11, pid: 101)
        h.start()

        h.monitor.setPolling(.objects([11, 99]))
        #expect(h.monitor.pollTargets == [11], "only objects that exist")

        h.monitor.setPolling(.all)
        #expect(h.monitor.pollTargets == [10, 11])
        h.hal.add(12, pid: 102)
        h.hal.fireList()
        h.scheduler.runAll()
        #expect(h.monitor.pollTargets == [10, 11, 12], "new objects join while polling everything")

        h.monitor.setPolling(.off)
        #expect(h.monitor.pollTargets.isEmpty)
    }

    @Test func aMissedStopIsFoundByThePoll() async throws {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100, playing: true)
        h.start()
        h.monitor.setPolling(.objects([10]))

        h.hal.running[10] = false  // a browser pause the HAL didn't notify
        try await waitUntil { h.sleeper.waiting.count == 1 }
        h.sleeper.wakeAll()
        try await waitUntil { h.scheduler.pending.count == 1 }
        h.scheduler.runAll()
        #expect(h.app(100)?.isPlaying == false)
        h.monitor.stop()
    }

    @Test func aPolledChangeIsPublished() async throws {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.start()
        h.monitor.setPolling(.objects([10]))
        h.hal.resetCounts()

        h.hal.running[10] = true  // no HAL notification
        try await waitUntil { h.sleeper.waiting.count == 1 }
        h.sleeper.wakeAll()
        try await waitUntil { h.scheduler.pending.count == 1 }
        h.scheduler.runAll()
        #expect(h.app(100)?.isPlaying == true)
        #expect(h.hal.runningReads == [10], "the poll read; the flush didn't read again")
        #expect(h.hal.listReads == 0)
        h.monitor.stop()
    }

    @Test func stopRemovesListenersAndIgnoresAPendingFlush() {
        let h = MonitorHarness()
        h.hal.add(10, pid: 100)
        h.start()
        h.monitor.setPolling(.all)
        h.hal.fireList()
        h.monitor.stop()

        #expect(h.hal.listeners.isEmpty)
        #expect(h.monitor.pollTargets.isEmpty)
        h.hal.resetCounts()
        h.scheduler.runAll()
        #expect(h.hal.listReads == 0)
        #expect(h.published.count == 1)
    }
}

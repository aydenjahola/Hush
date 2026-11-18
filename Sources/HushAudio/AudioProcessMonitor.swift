import AppKit
import CoreAudio
import HushCore
import os

/// Publishes the apps that own Core Audio process objects, with helpers grouped under their app.
///
/// Work is incremental and coalesced. Listener callbacks only mark what changed (the list, or one
/// object's running flag) and schedule a single flush, so one playback start (list change plus
/// running change) costs one flush. A flush reads the list only if it changed, reads PID and bundle
/// ID once per object (they never change for an object ID), and re-reads running state only for
/// objects that notified or are new. Polling reads only the objects `setPolling` asks for.
@MainActor
public final class AudioProcessMonitor: AudioProcessSource {
    public typealias Scheduler = @MainActor (@escaping @MainActor () -> Void) -> Void

    public private(set) var apps: [AudioApp] = []

    private struct ObjectInfo {
        let pid: pid_t
        let bundleID: String?
    }

    private let hal: any ProcessHAL
    private let resolver: AppIdentityResolver
    private let schedule: Scheduler
    private let ownPID: pid_t
    private let ownBundleID: String?
    private let logger = Logger(subsystem: HushIdentity.bundleID, category: "processes")
    private let pollerSleep: RunningStatePoller.Sleeper?

    private var onChange: (@MainActor ([AudioApp]) -> Void)?
    private var listListener: HALListener?
    private var runningListeners: [AudioObjectID: HALListener] = [:]
    private var objectIDs: [AudioObjectID] = []
    private var info: [AudioObjectID: ObjectInfo] = [:]
    private var running: [AudioObjectID: Bool] = [:]
    private var polling: ProcessPolling = .off

    private var needsListRead = false
    private var dirtyRunning: Set<AudioObjectID> = []
    private var isFlushScheduled = false

    private lazy var poller: RunningStatePoller = {
        let hal = self.hal
        let read: RunningStatePoller.Reader = { hal.isRunningOutput($0) }
        let onChange: @MainActor ([AudioObjectID: Bool]) -> Void = { [weak self] in self?.pollerDidChange($0) }
        if let pollerSleep {
            return RunningStatePoller(interval: .seconds(1), read: read, onChange: onChange, sleep: pollerSleep)
        }
        return RunningStatePoller(interval: .seconds(1), read: read, onChange: onChange)
    }()

    public convenience init() {
        self.init(
            hal: CoreAudioProcessHAL(),
            resolver: AppIdentityResolver(),
            schedule: Self.coalescing(within: .milliseconds(10)))
    }

    init(
        hal: any ProcessHAL,
        resolver: AppIdentityResolver,
        schedule: @escaping Scheduler,
        pollerSleep: RunningStatePoller.Sleeper? = nil,
        ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        ownBundleID: String? = Bundle.main.bundleIdentifier
    ) {
        self.hal = hal
        self.resolver = resolver
        self.schedule = schedule
        self.pollerSleep = pollerSleep
        self.ownPID = ownPID
        self.ownBundleID = ownBundleID
    }

    /// Runs the work once, `delay` after the first request. The HAL posts a playback start's
    /// notifications (list, running) separately but within a few milliseconds, so one short window
    /// catches them all while adding at most `delay` before a muted app's engine starts.
    public static func coalescing(within delay: Duration) -> Scheduler {
        let nanoseconds = Int(delay.components.seconds) * 1_000_000_000 + Int(delay.components.attoseconds / 1_000_000_000)
        return { work in
            DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(nanoseconds)) {
                MainActor.assumeIsolated { work() }
            }
        }
    }

    public func start(onChange: @escaping @MainActor ([AudioApp]) -> Void) {
        self.onChange = onChange
        listListener = hal.addListener(CoreAudioProperty.systemObject, kAudioHardwarePropertyProcessObjectList) { [weak self] in
            self?.listDidChange()
        }
        if listListener == nil { logger.error("Could not listen to the process list") }
        resolver.onInvalidate = { [weak self] in self?.scheduleFlush() }
        resolver.startObserving()
        needsListRead = true
        flush(publish: false)
        onChange(apps)  // exactly once, even when the list is empty
    }

    public func setPolling(_ polling: ProcessPolling) {
        self.polling = polling
        updatePollTargets()
    }

    public func stop() {
        poller.stop()
        resolver.stopObserving()
        resolver.onInvalidate = nil
        if let listListener { hal.removeListener(listListener) }
        listListener = nil
        for listener in runningListeners.values { hal.removeListener(listener) }
        runningListeners = [:]
        onChange = nil
        needsListRead = false
        dirtyRunning = []
    }

    /// The objects the poller currently reads (for tests).
    var pollTargets: Set<AudioObjectID> { poller.targets }

    // MARK: Events

    private func listDidChange() {
        needsListRead = true
        scheduleFlush()
    }

    private func runningDidChange(_ objectID: AudioObjectID) {
        dirtyRunning.insert(objectID)
        scheduleFlush()
    }

    private func pollerDidChange(_ changed: [AudioObjectID: Bool]) {
        for (objectID, value) in changed where running[objectID] != nil {
            running[objectID] = value
        }
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard onChange != nil, !isFlushScheduled else { return }
        isFlushScheduled = true
        schedule { [weak self] in self?.flush() }
    }

    // MARK: Flush

    private func flush(publish: Bool = true) {
        isFlushScheduled = false
        guard onChange != nil else { return }  // stopped: a queued flush must not re-register listeners
        if needsListRead {
            needsListRead = false
            readList()
        }
        for objectID in dirtyRunning where running[objectID] != nil {
            running[objectID] = hal.isRunningOutput(objectID)
        }
        dirtyRunning = []
        poller.record(running)
        updatePollTargets()
        regroup(publish: publish)
    }

    /// Applies a new process list. A failed read keeps the last state: publishing "no processes"
    /// would tear down every engine and unmute every muted app until the next good read.
    private func readList() {
        let fresh: [AudioObjectID]
        do {
            fresh = try hal.processObjects()
        } catch {
            logger.error("Process list unreadable, keeping the last state: \(String(describing: error), privacy: .public)")
            return
        }
        let current = Set(fresh)
        for objectID in objectIDs where !current.contains(objectID) {
            info[objectID] = nil
            running[objectID] = nil
            if let listener = runningListeners.removeValue(forKey: objectID) { hal.removeListener(listener) }
        }
        for objectID in fresh where info[objectID] == nil {
            // An unreadable PID is retried on the next list change.
            guard let pid = hal.pid(of: objectID) else { continue }
            info[objectID] = ObjectInfo(pid: pid, bundleID: hal.bundleID(of: objectID))
            running[objectID] = hal.isRunningOutput(objectID)
            // IsRunningOutput only: it's what decides `isPlaying`, and the poller reads the same flag.
            runningListeners[objectID] = hal.addListener(objectID, kAudioProcessPropertyIsRunningOutput) { [weak self] in
                self?.runningDidChange(objectID)
            }
        }
        objectIDs = fresh
    }

    private func updatePollTargets() {
        let known = Set(objectIDs.filter { info[$0] != nil })
        let targets: Set<AudioObjectID> = switch polling {
        case .off: []
        case .objects(let ids): ids.intersection(known)
        case .all: known
        }
        poller.setTargets(targets)
    }

    private func regroup(publish: Bool) {
        var groups: [String: (identity: AppIdentity, objects: [AudioObjectID], playing: Bool)] = [:]
        var livePIDs: Set<pid_t> = []
        for objectID in objectIDs {
            guard let object = info[objectID], object.pid > 0, object.pid != ownPID else { continue }
            livePIDs.insert(object.pid)
            let isRunning = running[objectID] ?? false
            let identity = resolver.identity(pid: object.pid, bundleID: object.bundleID)
            if let ownBundleID, identity.id == ownBundleID { continue }

            if var group = groups[identity.id] {
                group.objects.append(objectID)
                group.playing = group.playing || isRunning
                groups[identity.id] = group
            } else {
                groups[identity.id] = (identity, [objectID], isRunning)
            }
        }
        resolver.retainOnly(pids: livePIDs)

        let updated = groups.values
            .map { group in
                AudioApp(
                    id: group.identity.id,
                    displayName: group.identity.displayName,
                    icon: group.identity.icon,
                    processObjectIDs: group.objects.sorted(),
                    isPlaying: group.playing,
                    isRegularApp: group.identity.isRegularApp)
            }
            .sorted { $0.id < $1.id }

        guard updated != apps else { return }
        apps = updated
        if publish { onChange?(updated) }
    }
}

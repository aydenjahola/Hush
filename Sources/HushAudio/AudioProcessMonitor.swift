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
///
/// Microphone input (`IsRunningInput`) is tracked the same way, but only while
/// `setInputPolling` asks for it (ducking is on): otherwise no input is read, listened to or polled.
@MainActor
package final class AudioProcessMonitor: AudioProcessSource {
    package typealias Scheduler = @MainActor (@escaping @MainActor () -> Void) -> Void

    package private(set) var apps: [AudioApp] = []

    /// Attempts per object at reading its PID/bundle ID, or at adding its running listener, before
    /// giving up until the next list change.
    static let maxRetries = 5

    private struct ObjectInfo {
        let pid: pid_t
        let bundleID: String?
    }

    private let hal: any ProcessHAL
    private let resolver: AppIdentityResolver
    private let schedule: Scheduler
    private let retrySchedule: Scheduler
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
    /// nil while input isn't tracked (see `setInputPolling`).
    private var inputPolling: ProcessPolling?
    private var inputListeners: [AudioObjectID: HALListener] = [:]
    private var inputRunning: [AudioObjectID: Bool] = [:]
    private var dirtyInput: Set<AudioObjectID> = []
    private var inputListenerAttempts: [AudioObjectID: Int] = [:]

    private var needsListRead = false
    private var dirtyRunning: Set<AudioObjectID> = []
    private var isFlushScheduled = false
    private var isRetryScheduled = false
    /// Failed attempts so far, for objects whose info couldn't be read / whose listener was refused.
    private var infoAttempts: [AudioObjectID: Int] = [:]
    private var listenerAttempts: [AudioObjectID: Int] = [:]

    private lazy var poller: RunningStatePoller = {
        let hal = self.hal
        let read: RunningStatePoller.Reader = { hal.isRunningOutput($0) }
        let onChange: @MainActor ([AudioObjectID: Bool]) -> Void = { [weak self] in self?.pollerDidChange($0) }
        if let pollerSleep {
            return RunningStatePoller(interval: .seconds(1), read: read, onChange: onChange, sleep: pollerSleep)
        }
        return RunningStatePoller(interval: .seconds(1), read: read, onChange: onChange)
    }()

    /// Polls `IsRunningInput` for the objects `setInputPolling` asks for (call apps' processes).
    private lazy var inputPoller: RunningStatePoller = {
        let hal = self.hal
        let read: RunningStatePoller.Reader = { hal.isRunningInput($0) }
        let onChange: @MainActor ([AudioObjectID: Bool]) -> Void = { [weak self] in self?.inputPollerDidChange($0) }
        if let pollerSleep {
            return RunningStatePoller(interval: .seconds(1), read: read, onChange: onChange, sleep: pollerSleep)
        }
        return RunningStatePoller(interval: .seconds(1), read: read, onChange: onChange)
    }()

    package convenience init() {
        self.init(
            hal: CoreAudioProcessHAL(),
            resolver: AppIdentityResolver(),
            schedule: Self.coalescing(within: .milliseconds(10)),
            retrySchedule: Self.coalescing(within: .milliseconds(250)))
    }

    init(
        hal: any ProcessHAL,
        resolver: AppIdentityResolver,
        schedule: @escaping Scheduler,
        retrySchedule: @escaping Scheduler,
        pollerSleep: RunningStatePoller.Sleeper? = nil,
        ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        ownBundleID: String? = Bundle.main.bundleIdentifier
    ) {
        self.hal = hal
        self.resolver = resolver
        self.schedule = schedule
        self.retrySchedule = retrySchedule
        self.pollerSleep = pollerSleep
        self.ownPID = ownPID
        self.ownBundleID = ownBundleID
    }

    /// Runs the work once, `delay` after the first request. The HAL posts a playback start's
    /// notifications (list, running) separately but within a few milliseconds, so one short window
    /// catches them all while adding at most `delay` before a muted app's engine starts.
    package static func coalescing(within delay: Duration) -> Scheduler {
        let nanoseconds =
            Int(delay.components.seconds) * 1_000_000_000 + Int(delay.components.attoseconds / 1_000_000_000)
        return { work in
            DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(nanoseconds)) {
                MainActor.assumeIsolated { work() }
            }
        }
    }

    package func start(onChange: @escaping @MainActor ([AudioApp]) -> Void) {
        self.onChange = onChange
        listListener = hal.addListener(CoreAudioProperty.systemObject, kAudioHardwarePropertyProcessObjectList) {
            [weak self] in
            self?.listDidChange()
        }
        if listListener == nil { logger.error("Could not listen to the process list") }
        resolver.onInvalidate = { [weak self] in self?.scheduleFlush() }
        resolver.startObserving()
        needsListRead = true
        flush(publish: false)
        onChange(apps)  // exactly once, even when the list is empty
    }

    package func setPolling(_ polling: ProcessPolling) {
        self.polling = polling
        updatePollTargets()
    }

    /// Starting to track reads every known object's input and listens to it on the next flush;
    /// stopping removes those listeners and forgets the state, so every app reports no input.
    /// Either way the change is published from a scheduled flush, never from inside this call,
    /// because the caller is usually handling a published change already.
    package func setInputPolling(_ polling: ProcessPolling?) {
        let wasTracking = inputPolling != nil
        inputPolling = polling
        if polling != nil, !wasTracking {
            for objectID in objectIDs where info[objectID] != nil {
                dirtyInput.insert(objectID)
                inputListenerAttempts[objectID] = 0
            }
            scheduleFlush()
        } else if polling == nil, wasTracking {
            forgetInput()
            scheduleFlush()
        }
        updatePollTargets()
    }

    package func stop() {
        poller.stop()
        inputPoller.stop()
        resolver.stopObserving()
        resolver.onInvalidate = nil
        if let listListener { hal.removeListener(listListener) }
        listListener = nil
        for listener in runningListeners.values { hal.removeListener(listener) }
        runningListeners = [:]
        forgetInput()
        onChange = nil
        needsListRead = false
        dirtyRunning = []
        // Forget the per-object state, so a later start() reads everything and listens again.
        objectIDs = []
        info = [:]
        running = [:]
        infoAttempts = [:]
        listenerAttempts = [:]
        poller.record([:])
        apps = []
    }

    /// The objects the poller currently reads (for tests).
    var pollTargets: Set<AudioObjectID> { poller.targets }
    /// The objects the input poller currently reads (for tests).
    var inputPollTargets: Set<AudioObjectID> { inputPoller.targets }

    /// Removes the input listeners and forgets every object's input state.
    private func forgetInput() {
        for listener in inputListeners.values { hal.removeListener(listener) }
        inputListeners = [:]
        inputRunning = [:]
        dirtyInput = []
        inputListenerAttempts = [:]
        inputPoller.record([:])
    }

    // MARK: Events

    private func listDidChange() {
        needsListRead = true
        scheduleFlush()
    }

    private func runningDidChange(_ objectID: AudioObjectID) {
        dirtyRunning.insert(objectID)
        scheduleFlush()
    }

    private func inputDidChange(_ objectID: AudioObjectID) {
        dirtyInput.insert(objectID)
        scheduleFlush()
    }

    private func inputPollerDidChange(_ changed: [AudioObjectID: Bool]) {
        for (objectID, value) in changed where inputRunning[objectID] != nil {
            inputRunning[objectID] = value
        }
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
        resolvePending()
        for objectID in dirtyRunning where running[objectID] != nil {
            running[objectID] = hal.isRunningOutput(objectID)
        }
        dirtyRunning = []
        if inputPolling != nil {
            for objectID in dirtyInput where info[objectID] != nil {
                inputRunning[objectID] = hal.isRunningInput(objectID)
            }
        }
        dirtyInput = []
        poller.record(running)
        inputPoller.record(inputRunning)
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
            logger.error(
                "Process list unreadable, keeping the last state: \(String(describing: error), privacy: .public)")
            return
        }
        let current = Set(fresh)
        for objectID in objectIDs where !current.contains(objectID) {
            info[objectID] = nil
            running[objectID] = nil
            if let listener = runningListeners.removeValue(forKey: objectID) { hal.removeListener(listener) }
            infoAttempts[objectID] = nil
            listenerAttempts[objectID] = nil
            inputRunning[objectID] = nil
            if let listener = inputListeners.removeValue(forKey: objectID) { hal.removeListener(listener) }
            inputListenerAttempts[objectID] = nil
        }
        // A list change gives objects that ran out of retries a fresh round.
        for objectID in fresh where info[objectID] == nil { infoAttempts[objectID] = 0 }
        for objectID in fresh where info[objectID] != nil && runningListeners[objectID] == nil {
            listenerAttempts[objectID] = 0
        }
        if inputPolling != nil {
            for objectID in fresh where info[objectID] != nil && inputListeners[objectID] == nil {
                inputListenerAttempts[objectID] = 0
            }
        }
        objectIDs = fresh
    }

    /// Reads info for new objects and adds their running listener, retrying failures (bounded) on
    /// a later turn rather than waiting for the next list change.
    private func resolvePending() {
        for objectID in objectIDs where info[objectID] == nil {
            guard let attempts = infoAttempts[objectID], attempts < Self.maxRetries else { continue }
            // Not `try?`: it would flatten a legitimately nil bundle ID (CLI tools) into a failure.
            let bundleID: String?
            do {
                guard let pid = hal.pid(of: objectID) else { throw CoreAudioError(operation: "Reading PID", status: 0) }
                bundleID = try hal.bundleID(of: objectID)
                info[objectID] = ObjectInfo(pid: pid, bundleID: bundleID)
            } catch {
                infoAttempts[objectID] = attempts + 1
                logger.debug(
                    "Couldn't read process object \(objectID) (attempt \(attempts + 1)): \(String(describing: error), privacy: .public)"
                )
                continue
            }
            infoAttempts[objectID] = nil
            running[objectID] = hal.isRunningOutput(objectID)
            listenerAttempts[objectID] = 0
            if inputPolling != nil {
                inputRunning[objectID] = hal.isRunningInput(objectID)
                inputListenerAttempts[objectID] = 0
            }
        }
        for objectID in objectIDs where info[objectID] != nil && runningListeners[objectID] == nil {
            guard let attempts = listenerAttempts[objectID], attempts < Self.maxRetries else { continue }
            // IsRunningOutput only: it's what decides `isPlaying`, and the poller reads the same flag.
            if let listener = hal.addListener(
                objectID, kAudioProcessPropertyIsRunningOutput,
                { [weak self] in
                    self?.runningDidChange(objectID)
                })
            {
                runningListeners[objectID] = listener
                listenerAttempts[objectID] = nil
            } else {
                listenerAttempts[objectID] = attempts + 1
                logger.debug("HAL refused a running listener on object \(objectID) (attempt \(attempts + 1))")
            }
        }
        if inputPolling != nil { addInputListeners() }
        let pending =
            infoAttempts.values.contains { $0 < Self.maxRetries }
            || listenerAttempts.values.contains { $0 < Self.maxRetries }
            || inputListenerAttempts.values.contains { $0 < Self.maxRetries }
        if pending { scheduleRetry() }
    }

    /// Adds the input listener to objects that lack one, retrying refusals like the running listener.
    private func addInputListeners() {
        for objectID in objectIDs where info[objectID] != nil && inputListeners[objectID] == nil {
            guard let attempts = inputListenerAttempts[objectID], attempts < Self.maxRetries else { continue }
            if let listener = hal.addListener(
                objectID, kAudioProcessPropertyIsRunningInput,
                { [weak self] in
                    self?.inputDidChange(objectID)
                })
            {
                inputListeners[objectID] = listener
                inputListenerAttempts[objectID] = nil
            } else {
                inputListenerAttempts[objectID] = attempts + 1
                logger.debug("HAL refused an input listener on object \(objectID) (attempt \(attempts + 1))")
            }
        }
    }

    private func scheduleRetry() {
        guard onChange != nil, !isRetryScheduled else { return }
        isRetryScheduled = true
        retrySchedule { [weak self] in
            guard let self else { return }
            self.isRetryScheduled = false
            self.flush()
        }
    }

    private func updatePollTargets() {
        let known = Set(objectIDs.filter { info[$0] != nil })
        let targets: Set<AudioObjectID> =
            switch polling {
            case .off: []
            case .objects(let ids): ids.intersection(known)
            case .all: known
            }
        poller.setTargets(targets)
        let inputTargets: Set<AudioObjectID> =
            switch inputPolling {
            case nil, .off: []
            case .objects(let ids): ids.intersection(known)
            case .all: known
            }
        inputPoller.setTargets(inputTargets)
    }

    private func regroup(publish: Bool) {
        var groups: [String: (identity: AppIdentity, objects: [AudioObjectID], playing: Bool, capturing: Bool)] = [:]
        var livePIDs: Set<pid_t> = []
        for objectID in objectIDs {
            guard let object = info[objectID], object.pid > 0, object.pid != ownPID else { continue }
            livePIDs.insert(object.pid)
            let isRunning = running[objectID] ?? false
            let isCapturing = inputRunning[objectID] ?? false
            let identity = resolver.identity(pid: object.pid, bundleID: object.bundleID)
            if let ownBundleID, identity.id == ownBundleID { continue }

            if var group = groups[identity.id] {
                group.objects.append(objectID)
                group.playing = group.playing || isRunning
                group.capturing = group.capturing || isCapturing
                groups[identity.id] = group
            } else {
                groups[identity.id] = (identity, [objectID], isRunning, isCapturing)
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
                    isRegularApp: group.identity.isRegularApp,
                    isCapturingInput: group.capturing)
            }
            .sorted { $0.id < $1.id }

        guard updated != apps else { return }
        apps = updated
        if publish { onChange?(updated) }
    }
}

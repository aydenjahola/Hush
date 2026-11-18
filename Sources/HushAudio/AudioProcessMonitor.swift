import AppKit
import CoreAudio
import HushCore
import os

/// Publishes the apps that own Core Audio process objects, with helpers grouped under their app.
@MainActor
public final class AudioProcessMonitor: AudioProcessSource {
    public private(set) var apps: [AudioApp] = []

    private var onChange: (@MainActor ([AudioApp]) -> Void)?
    private var listListener: AudioObjectPropertyListenerBlock?
    /// Per process object: one listener block per selector in `runningSelectors`.
    private var runningListeners: [AudioObjectID: [AudioObjectPropertySelector: AudioObjectPropertyListenerBlock]] = [:]
    /// Fast paths only: the HAL often skips these notifications, so `poller` backs them up.
    private static let runningSelectors = [kAudioProcessPropertyIsRunning, kAudioProcessPropertyIsRunningOutput]
    private lazy var poller = RunningStatePoller(
        fastInterval: .seconds(1),
        slowInterval: .seconds(3),
        read: { Self.readIsRunningOutput($0) },
        onChange: { [weak self] in self?.refresh() })
    private let resolver = AppIdentityResolver()
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let ownBundleID = Bundle.main.bundleIdentifier
    private let logger = Logger(subsystem: HushIdentity.bundleID, category: "processes")

    public init() {}

    public func start(onChange: @escaping @MainActor ([AudioApp]) -> Void) {
        self.onChange = onChange
        listListener = addListener(to: CoreAudioProperty.systemObject, selector: kAudioHardwarePropertyProcessObjectList)
        resolver.onInvalidate = { [weak self] in self?.refresh() }
        resolver.startObserving()
        refresh()
        onChange(apps)
        poller.start()
    }

    public func setFastPolling(_ fast: Bool) {
        poller.setFast(fast)
    }

    public func stop() {
        poller.stop()
        resolver.stopObserving()
        if let listListener {
            removeListener(listListener, from: CoreAudioProperty.systemObject, selector: kAudioHardwarePropertyProcessObjectList)
        }
        listListener = nil
        for (objectID, blocks) in runningListeners {
            for (selector, block) in blocks { removeListener(block, from: objectID, selector: selector) }
        }
        runningListeners = [:]
        onChange = nil
    }

    private func refresh() {
        guard onChange != nil else { return }  // stopped: a queued listener block must not re-register listeners
        let objectIDs = (try? CoreAudioProperty.array(
            CoreAudioProperty.systemObject,
            kAudioHardwarePropertyProcessObjectList,
            filler: AudioObjectID(kAudioObjectUnknown))) ?? []
        syncRunningListeners(with: objectIDs)
        var running: [AudioObjectID: Bool] = [:]
        for objectID in objectIDs { running[objectID] = Self.readIsRunningOutput(objectID) }
        poller.record(running)

        var groups: [String: (identity: AppIdentity, objects: [AudioObjectID], playing: Bool)] = [:]
        var livePIDs: Set<pid_t> = []
        for objectID in objectIDs {
            guard let pid = try? CoreAudioProperty.scalar(objectID, kAudioProcessPropertyPID, initial: pid_t(0)),
                  pid > 0, pid != ownPID
            else { continue }
            livePIDs.insert(pid)
            let rawBundleID = try? CoreAudioProperty.string(objectID, kAudioProcessPropertyBundleID)
            let bundleID = (rawBundleID?.isEmpty ?? true) ? nil : rawBundleID
            let isRunning = running[objectID] ?? false
            let identity = resolver.identity(pid: pid, bundleID: bundleID)
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
        onChange?(updated)
    }

    private func syncRunningListeners(with objectIDs: [AudioObjectID]) {
        let current = Set(objectIDs)
        for (objectID, blocks) in runningListeners where !current.contains(objectID) {
            for (selector, block) in blocks { removeListener(block, from: objectID, selector: selector) }
            runningListeners[objectID] = nil
        }
        for objectID in objectIDs where runningListeners[objectID] == nil {
            var blocks: [AudioObjectPropertySelector: AudioObjectPropertyListenerBlock] = [:]
            for selector in Self.runningSelectors {
                blocks[selector] = addListener(to: objectID, selector: selector)
            }
            runningListeners[objectID] = blocks
        }
    }

    private static func readIsRunningOutput(_ objectID: AudioObjectID) -> Bool {
        let value = (try? CoreAudioProperty.scalar(objectID, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0))) ?? 0
        return value != 0
    }

    private func addListener(to objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> AudioObjectPropertyListenerBlock? {
        var propertyAddress = CoreAudioProperty.address(selector)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        let status = AudioObjectAddPropertyListenerBlock(objectID, &propertyAddress, DispatchQueue.main, block)
        guard status == noErr else {
            logger.error("Could not listen to object \(objectID) selector \(selector) (OSStatus \(status))")
            return nil
        }
        return block
    }

    private func removeListener(_ block: @escaping AudioObjectPropertyListenerBlock, from objectID: AudioObjectID, selector: AudioObjectPropertySelector) {
        var propertyAddress = CoreAudioProperty.address(selector)
        AudioObjectRemovePropertyListenerBlock(objectID, &propertyAddress, DispatchQueue.main, block)
    }
}

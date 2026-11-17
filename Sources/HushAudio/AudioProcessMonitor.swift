import AppKit
import CoreAudio
import os

/// Publishes the apps that own Core Audio process objects, with helpers grouped under their app.
@MainActor
public final class AudioProcessMonitor: AudioProcessSource {
    public private(set) var apps: [AudioApp] = []

    private var onChange: (@MainActor ([AudioApp]) -> Void)?
    private var listListener: AudioObjectPropertyListenerBlock?
    private var runningListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private let resolver = AppIdentityResolver()
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let ownBundleID = Bundle.main.bundleIdentifier
    private let logger = Logger(subsystem: "io.github.hush-mixer.Hush", category: "processes")

    public init() {}

    public func start(onChange: @escaping @MainActor ([AudioApp]) -> Void) {
        self.onChange = onChange
        listListener = addListener(to: CoreAudioProperty.systemObject, selector: kAudioHardwarePropertyProcessObjectList)
        refresh()
        onChange(apps)
    }

    public func stop() {
        if let listListener {
            removeListener(listListener, from: CoreAudioProperty.systemObject, selector: kAudioHardwarePropertyProcessObjectList)
        }
        listListener = nil
        for (objectID, block) in runningListeners {
            removeListener(block, from: objectID, selector: kAudioProcessPropertyIsRunningOutput)
        }
        runningListeners = [:]
        onChange = nil
    }

    private func refresh() {
        let objectIDs = (try? CoreAudioProperty.array(
            CoreAudioProperty.systemObject,
            kAudioHardwarePropertyProcessObjectList,
            filler: AudioObjectID(kAudioObjectUnknown))) ?? []
        syncRunningListeners(with: objectIDs)

        var groups: [String: (identity: AppIdentity, objects: [AudioObjectID], playing: Bool)] = [:]
        var livePIDs: Set<pid_t> = []
        for objectID in objectIDs {
            guard let pid = try? CoreAudioProperty.scalar(objectID, kAudioProcessPropertyPID, initial: pid_t(0)),
                  pid > 0, pid != ownPID
            else { continue }
            livePIDs.insert(pid)
            let rawBundleID = try? CoreAudioProperty.string(objectID, kAudioProcessPropertyBundleID)
            let bundleID = (rawBundleID?.isEmpty ?? true) ? nil : rawBundleID
            let isRunning = (try? CoreAudioProperty.scalar(
                objectID, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0))) ?? 0
            let identity = resolver.identity(pid: pid, bundleID: bundleID)
            if let ownBundleID, identity.id == ownBundleID { continue }

            if var group = groups[identity.id] {
                group.objects.append(objectID)
                group.playing = group.playing || isRunning != 0
                groups[identity.id] = group
            } else {
                groups[identity.id] = (identity, [objectID], isRunning != 0)
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
                    isPlaying: group.playing)
            }
            .sorted { $0.id < $1.id }

        guard updated != apps else { return }
        apps = updated
        onChange?(updated)
    }

    private func syncRunningListeners(with objectIDs: [AudioObjectID]) {
        let current = Set(objectIDs)
        for (objectID, block) in runningListeners where !current.contains(objectID) {
            removeListener(block, from: objectID, selector: kAudioProcessPropertyIsRunningOutput)
            runningListeners[objectID] = nil
        }
        for objectID in objectIDs where runningListeners[objectID] == nil {
            runningListeners[objectID] = addListener(to: objectID, selector: kAudioProcessPropertyIsRunningOutput)
        }
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

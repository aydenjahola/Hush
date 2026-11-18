import Carbon.HIToolbox
import HushCore
import os

/// Registers one system-wide key combination. A protocol so `GlobalShortcutController` can be
/// tested without touching the real event system.
package protocol HotKeyRegistering: AnyObject {
    /// Called on the main actor each time the registered combination is pressed.
    var onPress: (@MainActor () -> Void)? { get set }
    /// Registers `shortcut` in place of any previous one. Returns false, leaving nothing
    /// registered, when the system or another app already uses it.
    func register(_ shortcut: GlobalShortcut) -> Bool
    func unregister()
}

/// A global shortcut through Carbon's `RegisterEventHotKey`. Unlike an event tap or a global
/// `NSEvent` monitor, this needs no Accessibility or Input Monitoring permission: the system
/// delivers only the registered combination, and only to Hush.
package final class GlobalHotKey: HotKeyRegistering {
    package var onPress: (@MainActor () -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let logger = Logger(subsystem: HushIdentity.bundleID, category: "shortcut")

    /// 'Hush', so the handler only answers to its own hot key.
    nonisolated private static let signature: OSType = 0x4875_7368

    package init() {}

    isolated deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }

    package func register(_ shortcut: GlobalShortcut) -> Bool {
        unregister()
        guard installHandler() else { return false }
        if Self.isReservedBySystem(shortcut, symbolicHotKeys: Self.enabledSymbolicHotKeys()) {
            return false
        }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            Self.carbonModifiers(shortcut.modifiers),
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &ref)
        guard status == noErr, let ref else {
            logger.notice("Couldn't register the global shortcut (status \(status, privacy: .public))")
            return false
        }
        hotKey = ref
        return true
    }

    package func unregister() {
        guard let hotKey else { return }
        UnregisterEventHotKey(hotKey)
        self.hotKey = nil
    }

    /// Installs the hot-key event handler once, on the application's event target. Carbon calls
    /// it on the main thread.
    private func installHandler() -> Bool {
        if handler != nil { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard status == noErr, id.signature == GlobalHotKey.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { hotKey.onPress?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler)
        guard status == noErr else {
            logger.error("Couldn't install the global shortcut handler (status \(status, privacy: .public))")
            handler = nil
            return false
        }
        return true
    }

    // MARK: Pure helpers

    /// Carbon's modifier mask for `RegisterEventHotKey`.
    nonisolated static func carbonModifiers(_ modifiers: GlobalShortcut.Modifiers) -> UInt32 {
        var result = 0
        if modifiers.contains(.command) { result |= cmdKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.control) { result |= controlKey }
        if modifiers.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }

    /// A system shortcut from Keyboard settings (`CopySymbolicHotKeys`): its key code, Carbon
    /// modifier mask, and whether it's turned on.
    struct SymbolicHotKey: Equatable {
        var keyCode: Int
        var carbonModifiers: Int
        var isEnabled: Bool
    }

    /// Whether a system shortcut that's turned on already uses this combination. macOS lets
    /// `RegisterEventHotKey` succeed for these, but the system shortcut wins, so Hush's would
    /// never fire.
    nonisolated static func isReservedBySystem(
        _ shortcut: GlobalShortcut, symbolicHotKeys: [SymbolicHotKey]
    ) -> Bool {
        let mask = cmdKey | optionKey | controlKey | shiftKey
        let modifiers = Int(carbonModifiers(shortcut.modifiers))
        return symbolicHotKeys.contains { hotKey in
            hotKey.isEnabled && hotKey.keyCode == Int(shortcut.keyCode) && hotKey.carbonModifiers & mask == modifiers
        }
    }

    private static func enabledSymbolicHotKeys() -> [SymbolicHotKey] {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
            let entries = unmanaged?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return entries.compactMap { entry in
            guard let keyCode = entry[kHISymbolicHotKeyCode as String] as? Int,
                let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int
            else { return nil }
            let enabled = entry[kHISymbolicHotKeyEnabled as String] as? Bool ?? false
            return SymbolicHotKey(keyCode: keyCode, carbonModifiers: modifiers, isEnabled: enabled)
        }
    }
}

import Carbon.HIToolbox
import HushCore
import os

/// Registers one system-wide key combination. A protocol so `GlobalShortcutController` can be
/// tested without touching the real event system.
package protocol HotKeyRegistering: AnyObject {
    /// Called on the main actor each time the registered combination is pressed.
    var onPress: (@MainActor () -> Void)? { get set }
    /// Registers `shortcut` in place of any previous one. Returns false, leaving nothing
    /// registered, when it's known to be taken. That check is best effort: see `GlobalHotKey`.
    func register(_ shortcut: GlobalShortcut) -> Bool
    func unregister()
}

/// A global shortcut through Carbon's `RegisterEventHotKey`. Unlike an event tap or a global
/// `NSEvent` monitor, this needs no Accessibility or Input Monitoring permission: the system
/// delivers only the registered combination, and only to Hush.
///
/// Detecting a combination that's already taken is best effort. Hush refuses one that an enabled
/// macOS shortcut uses (from `CopySymbolicHotKeys`), and `RegisterEventHotKey` fails when another
/// app registered the same combination exclusively. A non-exclusive registration by another app
/// isn't reported, so the two may overlap. Hush registers non-exclusively itself.
package final class GlobalHotKey: HotKeyRegistering {
    package var onPress: (@MainActor () -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let symbolicHotKeys: @MainActor () -> [SymbolicHotKey]
    private let logger = Logger(subsystem: HushIdentity.bundleID, category: "shortcut")

    /// 'Hush', so the handler only answers to its own hot key.
    nonisolated private static let signature: OSType = 0x4875_7368
    /// Hush registers one hot key, always with this id.
    nonisolated private static let hotKeyID: UInt32 = 1

    package convenience init() {
        self.init(symbolicHotKeys: GlobalHotKey.enabledSymbolicHotKeys)
    }

    /// `symbolicHotKeys` lists the system's shortcuts; tests pass a fixed list.
    init(symbolicHotKeys: @escaping @MainActor () -> [SymbolicHotKey]) {
        self.symbolicHotKeys = symbolicHotKeys
    }

    isolated deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }

    package func register(_ shortcut: GlobalShortcut) -> Bool {
        unregister()
        // Checked first, so a refused combination touches nothing in Carbon.
        if Self.isReservedBySystem(shortcut, symbolicHotKeys: symbolicHotKeys()) {
            return false
        }
        guard installHandler() else { return false }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            Self.carbonModifiers(shortcut.modifiers),
            EventHotKeyID(signature: Self.signature, id: Self.hotKeyID),
            GetApplicationEventTarget(),
            0,  // not kEventHotKeyExclusive, so Hush never blocks another app's registration
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
    ///
    /// The handler stays installed until deinit, even while no hot key is registered. It only
    /// answers to Hush's own hot-key ID, so it costs nothing in between. Keeping it also means
    /// re-registering after recording or a change can't fail halfway, with a hot key but no
    /// handler. Deinit removes it, because the handler holds an unretained pointer to `self`.
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
                guard status == noErr, id.signature == GlobalHotKey.signature, id.id == GlobalHotKey.hotKeyID else {
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

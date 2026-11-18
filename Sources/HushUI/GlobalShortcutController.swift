import AppKit
import Carbon.HIToolbox
import HushCore
import Observation

/// The global shortcut that opens the mixer: what's saved, whether it's registered, and the
/// message Settings shows when a combination can't be used. Off until the user records one.
@MainActor
@Observable
package final class GlobalShortcutController {
    /// Why the last recorded combination wasn't saved (or, at launch, why the saved one isn't active).
    package enum Problem: Equatable {
        /// The system or another app already uses it.
        case inUse
        /// It has no ⌘, ⌥ or ⌃ and isn't a function key.
        case needsModifier
        /// Only ⌘ or ⌘⇧ on an ordinary key, which apps use for their own commands.
        case standardShortcut
    }

    package private(set) var shortcut: GlobalShortcut?
    package private(set) var problem: Problem?
    /// True while the recorder is listening, during which the shortcut is unregistered so
    /// pressing it records it instead of opening the mixer.
    package private(set) var isRecording = false

    /// What the shortcut does; the app sets this to toggle the popover.
    @ObservationIgnored package var onPress: (@MainActor () -> Void)?

    @ObservationIgnored private let persister: any SettingsPersisting
    @ObservationIgnored private let hotKey: any HotKeyRegistering

    package init(persister: any SettingsPersisting, hotKey: any HotKeyRegistering) {
        self.persister = persister
        self.hotKey = hotKey
        hotKey.onPress = { [weak self] in self?.onPress?() }
    }

    /// Reads the saved shortcut (from the settings already in memory, if any) and registers it.
    package func start() {
        shortcut = persister.latest().globalShortcut
        problem = nil
        registerSaved()
    }

    /// Registers the saved shortcut if it's allowed. One that isn't (written by hand, or by a
    /// version with looser rules) stays saved but inactive, with the reason shown in Settings.
    private func registerSaved() {
        guard let shortcut else { return }
        switch shortcut.validity {
        case .ok: if !hotKey.register(shortcut) { problem = .inUse }
        case .needsModifier: problem = .needsModifier
        case .standardShortcut: problem = .standardShortcut
        }
    }

    /// Unregisters the shortcut (when Hush quits). The saved value is kept.
    package func stop() {
        hotKey.unregister()
    }

    package func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        problem = nil
        hotKey.unregister()
    }

    /// Stops listening and registers the saved shortcut again.
    package func endRecording() {
        guard isRecording else { return }
        isRecording = false
        registerSaved()
    }

    /// Saves and registers a combination the user pressed while recording. A combination that
    /// isn't allowed keeps recording; one that can't be registered ends it. Either way the
    /// previous shortcut is kept and the result is false.
    @discardableResult
    package func record(_ candidate: GlobalShortcut) -> Bool {
        switch candidate.validity {
        case .ok: break
        case .needsModifier:
            problem = .needsModifier
            return false
        case .standardShortcut:
            problem = .standardShortcut
            return false
        }
        isRecording = false
        guard hotKey.register(candidate) else {
            problem = .inUse
            // Trying the candidate cleared the previous registration; put it back.
            if let shortcut, shortcut.isValid { _ = hotKey.register(shortcut) }
            return false
        }
        problem = nil
        save(candidate)
        return true
    }

    /// Removes the shortcut, so no key combination opens the mixer.
    package func clear() {
        hotKey.unregister()
        problem = nil
        save(nil)
    }

    private func save(_ shortcut: GlobalShortcut?) {
        self.shortcut = shortcut
        persister.update { $0.globalShortcut = shortcut }
    }
}

// MARK: Display

/// Shows shortcuts with the standard glyphs, such as "⌥⌘H", taking each letter from the current
/// keyboard layout.
package enum ShortcutFormatter {
    package static func string(
        for shortcut: GlobalShortcut,
        layoutCharacters: @MainActor (UInt16) -> String? = KeyboardLayout.characters(forKeyCode:)
    ) -> String {
        shortcut.displayString(keyLabel: keyLabel(for: shortcut.keyCode, layoutCharacters: layoutCharacters))
    }

    package static func keyLabel(for keyCode: UInt16, layoutCharacters: @MainActor (UInt16) -> String?) -> String {
        switch GlobalShortcut.specialKey(for: keyCode) {
        case .symbol(let symbol): return symbol
        case .space: return String(localized: L10n.spaceKey)
        case nil:
            return GlobalShortcut.keyLabel(fromLayoutCharacters: layoutCharacters(keyCode))
                ?? String(localized: L10n.unknownKey(Int(keyCode)))
        }
    }
}

extension GlobalShortcut.Modifiers {
    /// The modifiers Hush records from a key event; Caps Lock, Fn and the numeric-pad flag are ignored.
    package init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
    }
}

/// The character each key types in the current keyboard layout, for labels only.
package enum KeyboardLayout {
    /// The unmodified character for `keyCode`, from the current layout or, when that gives nothing
    /// printable (a non-Latin input source, for example), the current ASCII-capable layout.
    package static func characters(forKeyCode keyCode: UInt16) -> String? {
        let sources = [
            TISCopyCurrentKeyboardLayoutInputSource(), TISCopyCurrentASCIICapableKeyboardLayoutInputSource(),
        ]
        for case let source? in sources.map({ $0?.takeRetainedValue() }) {
            if let characters = translate(keyCode, in: source),
                GlobalShortcut.keyLabel(fromLayoutCharacters: characters) != nil
            {
                return characters
            }
        }
        return nil
    }

    private static func translate(_ keyCode: UInt16, in source: TISInputSource) -> String? {
        guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}

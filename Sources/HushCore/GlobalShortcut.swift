import Foundation

/// The key combination that opens the mixer from anywhere (Settings → General → Keyboard shortcut).
///
/// Stored as a virtual key code, which names a physical key rather than a character, so the
/// shortcut keeps working when the keyboard layout changes. Only the display uses the layout.
package struct GlobalShortcut: Codable, Equatable, Hashable, Sendable {
    /// The modifier keys held with the key. On disk each is a name ("command", "option"…) so the
    /// file stays readable; unknown names are ignored.
    package struct Modifiers: OptionSet, Hashable, Sendable {
        package let rawValue: Int
        package init(rawValue: Int) { self.rawValue = rawValue }

        package static let control = Modifiers(rawValue: 1 << 0)
        package static let option = Modifiers(rawValue: 1 << 1)
        package static let shift = Modifiers(rawValue: 1 << 2)
        package static let command = Modifiers(rawValue: 1 << 3)

        /// In the order macOS menus draw them, with their names on disk and their glyphs.
        static let ordered: [(modifier: Modifiers, name: String, glyph: String)] = [
            (.control, "control", "⌃"),
            (.option, "option", "⌥"),
            (.shift, "shift", "⇧"),
            (.command, "command", "⌘"),
        ]
    }

    /// A macOS virtual key code (`kVK_…` in Carbon's Events.h).
    package var keyCode: UInt16
    package var modifiers: Modifiers

    package init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // MARK: Validation

    /// Whether a combination can be used as the global shortcut, and if not, why.
    package enum Validity: Equatable, Sendable {
        case ok
        /// No ⌘, ⌥ or ⌃ (⇧ alone would take over a character the user types).
        case needsModifier
        /// Only ⌘ or ⌘⇧ on an ordinary key, such as ⌘C or ⌘⇧4. Apps use these for their own
        /// commands, and a global shortcut would take them over in every app.
        case standardShortcut
        /// A combination macOS keeps for itself whatever the settings: ⌥⌘Esc (Force Quit) and
        /// ⌥⌘⇧Esc (force quit the front app).
        case reservedByMacOS
    }

    /// A function key is allowed on its own or with any modifiers. Any other key needs ⌥ or ⌃,
    /// or ⌘ with one of them.
    package var validity: Validity {
        if Self.isFunctionKey(keyCode) { return .ok }
        if modifiers.isDisjoint(with: [.command, .option, .control]) { return .needsModifier }
        if modifiers.isSubset(of: [.command, .shift]) { return .standardShortcut }
        if keyCode == KeyCode.escape, modifiers.isSuperset(of: [.command, .option]),
            modifiers.isSubset(of: [.command, .option, .shift])
        {
            return .reservedByMacOS
        }
        return .ok
    }

    package var isValid: Bool { validity == .ok }

    /// F1 to F20.
    package static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        functionKeys[keyCode] != nil
    }

    // MARK: Display

    /// The modifier glyphs in menu order, such as "⌃⌥⌘".
    package var modifierGlyphs: String {
        Modifiers.ordered.filter { modifiers.contains($0.modifier) }.map(\.glyph).joined()
    }

    /// How a key is shown when its label doesn't come from the keyboard layout.
    package enum SpecialKey: Equatable, Sendable {
        /// A standard symbol or name that needs no translation, such as "↩" or "F5".
        case symbol(String)
        /// The space bar, shown as a localised word.
        case space
    }

    /// The fixed label for keys whose character isn't a printable letter (Return, arrows, F-keys
    /// and so on), or nil for keys that take their label from the keyboard layout.
    package static func specialKey(for keyCode: UInt16) -> SpecialKey? {
        if keyCode == KeyCode.space { return .space }
        if let number = functionKeys[keyCode] { return .symbol("F\(number)") }
        return specialSymbols[keyCode].map(SpecialKey.symbol)
    }

    /// Turns the character a key types (from the keyboard layout) into its label: trimmed,
    /// uppercased, and nil when it isn't something printable.
    package static func keyLabel(fromLayoutCharacters characters: String?) -> String? {
        guard let characters else { return nil }
        let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            trimmed.unicodeScalars.allSatisfy({ !$0.properties.generalCategory.isControlOrUnassigned })
        else { return nil }
        return trimmed.uppercased()
    }

    /// The whole shortcut as menus show it, such as "⌥⌘H". `keyLabel` is the key's own label.
    package func displayString(keyLabel: String) -> String {
        modifierGlyphs + keyLabel
    }

    // MARK: Key codes

    package enum KeyCode {
        package static let returnKey: UInt16 = 0x24
        package static let tab: UInt16 = 0x30
        package static let space: UInt16 = 0x31
        package static let delete: UInt16 = 0x33
        package static let escape: UInt16 = 0x35
        package static let keypadEnter: UInt16 = 0x4C
        package static let forwardDelete: UInt16 = 0x75
        package static let home: UInt16 = 0x73
        package static let end: UInt16 = 0x77
        package static let pageUp: UInt16 = 0x74
        package static let pageDown: UInt16 = 0x79
        package static let leftArrow: UInt16 = 0x7B
        package static let rightArrow: UInt16 = 0x7C
        package static let downArrow: UInt16 = 0x7D
        package static let upArrow: UInt16 = 0x7E
        package static let keypadClear: UInt16 = 0x47
        package static let f1: UInt16 = 0x7A
        package static let f5: UInt16 = 0x60
        package static let f12: UInt16 = 0x6F
        package static let f20: UInt16 = 0x5A
    }

    /// Function key codes and their numbers. They aren't contiguous.
    private static let functionKeys: [UInt16: Int] = [
        0x7A: 1, 0x78: 2, 0x63: 3, 0x76: 4, 0x60: 5, 0x61: 6, 0x62: 7, 0x64: 8, 0x65: 9, 0x6D: 10,
        0x67: 11, 0x6F: 12, 0x69: 13, 0x6B: 14, 0x71: 15, 0x6A: 16, 0x40: 17, 0x4F: 18, 0x50: 19, 0x5A: 20,
    ]

    private static let specialSymbols: [UInt16: String] = [
        KeyCode.returnKey: "↩",
        KeyCode.tab: "⇥",
        KeyCode.delete: "⌫",
        KeyCode.escape: "⎋",
        KeyCode.keypadEnter: "⌤",
        KeyCode.forwardDelete: "⌦",
        KeyCode.home: "↖",
        KeyCode.end: "↘",
        KeyCode.pageUp: "⇞",
        KeyCode.pageDown: "⇟",
        KeyCode.leftArrow: "←",
        KeyCode.rightArrow: "→",
        KeyCode.downArrow: "↓",
        KeyCode.upArrow: "↑",
        KeyCode.keypadClear: "⌧",
    ]

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        let names = try container.decodeIfPresent([String].self, forKey: .modifiers) ?? []
        modifiers = Modifiers.ordered.reduce(into: []) { result, entry in
            if names.contains(entry.name) { result.insert(entry.modifier) }
        }
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(
            Modifiers.ordered.filter { modifiers.contains($0.modifier) }.map(\.name), forKey: .modifiers)
    }
}

extension Unicode.GeneralCategory {
    fileprivate var isControlOrUnassigned: Bool {
        switch self {
        case .control, .format, .unassigned, .privateUse, .surrogate: true
        default: false
        }
    }
}

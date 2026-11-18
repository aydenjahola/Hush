import Foundation
import Testing

@testable import HushCore

@Suite struct GlobalShortcutTests {
    private typealias Key = GlobalShortcut.KeyCode
    /// kVK_ANSI_H.
    private let keyH: UInt16 = 0x04

    // MARK: Validation

    @Test(arguments: [
        GlobalShortcut.Modifiers.option, .control, [.option, .command], [.control, .command], [.option, .shift],
        [.control, .option, .command], [.command, .shift, .control],
    ])
    func optionOrControlMakesItValid(modifiers: GlobalShortcut.Modifiers) {
        #expect(GlobalShortcut(keyCode: keyH, modifiers: modifiers).validity == .ok)
    }

    @Test func aPlainKeyOrShiftAloneNeedsAModifier() {
        #expect(GlobalShortcut(keyCode: keyH, modifiers: []).validity == .needsModifier)
        #expect(GlobalShortcut(keyCode: keyH, modifiers: .shift).validity == .needsModifier)
        #expect(GlobalShortcut(keyCode: Key.space, modifiers: .shift).validity == .needsModifier)
        #expect(GlobalShortcut(keyCode: Key.returnKey, modifiers: []).validity == .needsModifier)
        #expect(!GlobalShortcut(keyCode: keyH, modifiers: []).isValid)
    }

    @Test func commandOrCommandShiftOnAnOrdinaryKeyIsAStandardShortcut() {
        let keyC: UInt16 = 0x08
        let keyQ: UInt16 = 0x0C
        let digit4: UInt16 = 0x15
        let refused = [
            GlobalShortcut(keyCode: keyC, modifiers: .command),
            GlobalShortcut(keyCode: keyQ, modifiers: .command),
            GlobalShortcut(keyCode: digit4, modifiers: [.command, .shift]),
            GlobalShortcut(keyCode: Key.space, modifiers: .command),
            GlobalShortcut(keyCode: Key.returnKey, modifiers: .command),
            GlobalShortcut(keyCode: Key.tab, modifiers: [.command, .shift]),
            GlobalShortcut(keyCode: Key.leftArrow, modifiers: .command),
            GlobalShortcut(keyCode: Key.delete, modifiers: .command),
            GlobalShortcut(keyCode: Key.escape, modifiers: .command),
        ]
        for shortcut in refused {
            #expect(shortcut.validity == .standardShortcut, "\(shortcut)")
            #expect(!shortcut.isValid)
        }
    }

    @Test func allowedExamples() {
        let allowed = [
            GlobalShortcut(keyCode: keyH, modifiers: [.option, .command]),
            GlobalShortcut(keyCode: 0x2E, modifiers: [.control, .command]),  // ⌃⌘M
            GlobalShortcut(keyCode: Key.f5, modifiers: .command),
            GlobalShortcut(keyCode: Key.f5, modifiers: [.command, .shift]),
            GlobalShortcut(keyCode: Key.f5, modifiers: []),
        ]
        for shortcut in allowed { #expect(shortcut.validity == .ok, "\(shortcut)") }
    }

    @Test(arguments: [Key.f1, Key.f5, Key.f12, Key.f20])
    func functionKeysAreValidOnTheirOwn(keyCode: UInt16) {
        #expect(GlobalShortcut.isFunctionKey(keyCode))
        #expect(GlobalShortcut(keyCode: keyCode, modifiers: []).isValid)
        #expect(GlobalShortcut(keyCode: keyCode, modifiers: .shift).isValid)
    }

    @Test func everyFunctionKeyIsRecognised() {
        let codes: [UInt16] = [
            0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,
            0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A,
        ]
        for (index, code) in codes.enumerated() {
            #expect(GlobalShortcut.specialKey(for: code) == .symbol("F\(index + 1)"))
        }
        #expect(!GlobalShortcut.isFunctionKey(keyH))
    }

    // MARK: Display

    @Test func modifierGlyphsFollowMenuOrder() {
        let all = GlobalShortcut(keyCode: keyH, modifiers: [.command, .shift, .option, .control])
        #expect(all.modifierGlyphs == "⌃⌥⇧⌘")
        let shortcut = GlobalShortcut(keyCode: keyH, modifiers: [.command, .option])
        #expect(shortcut.displayString(keyLabel: "H") == "⌥⌘H")
        #expect(GlobalShortcut(keyCode: Key.f5, modifiers: []).displayString(keyLabel: "F5") == "F5")
    }

    @Test func specialKeysHaveFixedLabels() {
        #expect(GlobalShortcut.specialKey(for: Key.space) == .space)
        #expect(GlobalShortcut.specialKey(for: Key.returnKey) == .symbol("↩"))
        #expect(GlobalShortcut.specialKey(for: Key.tab) == .symbol("⇥"))
        #expect(GlobalShortcut.specialKey(for: Key.delete) == .symbol("⌫"))
        #expect(GlobalShortcut.specialKey(for: Key.escape) == .symbol("⎋"))
        #expect(GlobalShortcut.specialKey(for: Key.leftArrow) == .symbol("←"))
        #expect(GlobalShortcut.specialKey(for: Key.rightArrow) == .symbol("→"))
        #expect(GlobalShortcut.specialKey(for: Key.upArrow) == .symbol("↑"))
        #expect(GlobalShortcut.specialKey(for: Key.downArrow) == .symbol("↓"))
        #expect(GlobalShortcut.specialKey(for: keyH) == nil)
    }

    @Test func layoutCharactersBecomeUppercaseLabels() {
        #expect(GlobalShortcut.keyLabel(fromLayoutCharacters: "h") == "H")
        #expect(GlobalShortcut.keyLabel(fromLayoutCharacters: "ß") == "SS")
        #expect(GlobalShortcut.keyLabel(fromLayoutCharacters: "é") == "É")
        #expect(GlobalShortcut.keyLabel(fromLayoutCharacters: ",") == ",")
        #expect(GlobalShortcut.keyLabel(fromLayoutCharacters: nil) == nil)
        #expect(GlobalShortcut.keyLabel(fromLayoutCharacters: "") == nil)
        #expect(GlobalShortcut.keyLabel(fromLayoutCharacters: " ") == nil)
        // AppKit reports arrows and function keys as private-use characters.
        #expect(GlobalShortcut.keyLabel(fromLayoutCharacters: "\u{F704}") == nil)
        #expect(GlobalShortcut.keyLabel(fromLayoutCharacters: "\u{1B}") == nil)
    }

    // MARK: Coding

    @Test func encodesModifiersByName() throws {
        let shortcut = GlobalShortcut(keyCode: keyH, modifiers: [.command, .option])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let text = String(decoding: try encoder.encode(shortcut), as: UTF8.self)
        #expect(text == #"{"keyCode":4,"modifiers":["option","command"]}"#)
        #expect(try JSONDecoder().decode(GlobalShortcut.self, from: Data(text.utf8)) == shortcut)
    }

    @Test func decodingIgnoresUnknownModifierNames() throws {
        let json = #"{"keyCode": 4, "modifiers": ["control", "hyper"]}"#
        let shortcut = try JSONDecoder().decode(GlobalShortcut.self, from: Data(json.utf8))
        #expect(shortcut == GlobalShortcut(keyCode: 4, modifiers: .control))
        let noModifiers = try JSONDecoder().decode(GlobalShortcut.self, from: Data(#"{"keyCode": 96}"#.utf8))
        #expect(noModifiers == GlobalShortcut(keyCode: Key.f5, modifiers: []))
    }

    // MARK: Settings file

    @Test func settingsWithoutAShortcutStillLoad() throws {
        let json = """
            {
              "version": 1,
              "preferences": { "maxBoostPercent": 150, "showInactiveApps": true },
              "apps": {},
              "updates": { "automaticUpdateChecks": true }
            }
            """
        let document = try SettingsDocument.decode(from: Data(json.utf8))
        #expect(document.globalShortcut == nil)
        #expect(document.preferences.maxBoostPercent == .percent150)
        #expect(SettingsDocument().globalShortcut == nil)
    }

    @Test func shortcutRoundTripsThroughTheSettingsFile() throws {
        let shortcut = GlobalShortcut(keyCode: keyH, modifiers: [.control, .command])
        let document = SettingsDocument(globalShortcut: shortcut)
        let data = try document.encoded()
        #expect(String(decoding: data, as: UTF8.self).contains("\"globalShortcut\""))
        #expect(try SettingsDocument.decode(from: data).globalShortcut == shortcut)
        #expect(!String(decoding: try SettingsDocument().encoded(), as: UTF8.self).contains("globalShortcut"))
    }

    @Test func aMalformedShortcutIsDroppedWithoutLosingTheFile() throws {
        let json = """
            { "version": 1, "preferences": { "maxBoostPercent": 100 }, "apps": {}, "globalShortcut": "⌥⌘H" }
            """
        let document = try SettingsDocument.decode(from: Data(json.utf8))
        #expect(document.globalShortcut == nil)
        #expect(document.preferences.maxBoostPercent == .percent100)
    }
}

import AppKit
import Carbon.HIToolbox
import HushCore
import Testing

@testable import HushUI

@MainActor
private final class FakeHotKey: HotKeyRegistering {
    var onPress: (@MainActor () -> Void)?
    /// Combinations the "system" already uses.
    var taken: Set<GlobalShortcut> = []
    private(set) var registered: GlobalShortcut?
    private(set) var registrations: [GlobalShortcut] = []

    func register(_ shortcut: GlobalShortcut) -> Bool {
        registrations.append(shortcut)
        guard !taken.contains(shortcut) else {
            registered = nil
            return false
        }
        registered = shortcut
        return true
    }

    func unregister() { registered = nil }

    func press() { if registered != nil { onPress?() } }
}

/// Collects VoiceOver announcements instead of posting them.
@MainActor
private final class Spoken {
    private(set) var lines: [String] = []
    func say(_ line: String) { lines.append(line) }
}

@MainActor
@Suite(.timeLimit(.minutes(1))) struct GlobalShortcutControllerTests {
    private let optionCommandH = GlobalShortcut(keyCode: 0x04, modifiers: [.option, .command])
    private let controlF5 = GlobalShortcut(keyCode: GlobalShortcut.KeyCode.f5, modifiers: .control)
    private let spoken = Spoken()

    @Test func forceQuitIsReservedByMacOSNotAStandardShortcut() {
        let (controller, hotKey, persister) = make(saved: optionCommandH)
        controller.start()
        controller.beginRecording()
        let forceQuit = GlobalShortcut(keyCode: GlobalShortcut.KeyCode.escape, modifiers: [.command, .option])
        #expect(!controller.record(forceQuit))
        #expect(controller.problem == .reservedByMacOS)
        #expect(controller.isRecording)
        #expect(hotKey.registrations == [optionCommandH])
        #expect(persister.saved.isEmpty)
        #expect(spoken.lines == ["macOS uses that shortcut. Try another."])
    }

    @Test func everyRejectedAttemptIsAnnouncedEvenWhenRepeated() {
        let (controller, _, _) = make()
        controller.start()
        controller.beginRecording()
        let plainH = GlobalShortcut(keyCode: 0x04, modifiers: [])
        controller.record(plainH)
        controller.record(plainH)
        #expect(spoken.lines == Array(repeating: "Include ⌥ or ⌃, or use a function key.", count: 2))
    }

    @Test func savingAndClearingAreAnnounced() {
        let (controller, hotKey, _) = make()
        hotKey.taken = [controlF5]
        controller.start()
        controller.beginRecording()
        controller.record(controlF5)
        controller.beginRecording()
        controller.record(optionCommandH)
        controller.clear()
        let saved = String(localized: L10n.shortcutSaved(ShortcutFormatter.string(for: optionCommandH)))
        #expect(
            spoken.lines == ["That shortcut is in use. Try another.", saved, "Keyboard shortcut cleared"])
    }

    private func make(
        saved: GlobalShortcut? = nil
    ) -> (GlobalShortcutController, FakeHotKey, FakePersister) {
        let persister = FakePersister(document: SettingsDocument(globalShortcut: saved))
        let hotKey = FakeHotKey()
        let controller = GlobalShortcutController(persister: persister, hotKey: hotKey, announce: spoken.say)
        return (controller, hotKey, persister)
    }

    @Test func offByDefault() {
        let (controller, hotKey, _) = make()
        controller.start()
        #expect(controller.shortcut == nil)
        #expect(hotKey.registrations.isEmpty)
        #expect(controller.problem == nil)
    }

    @Test func registersTheSavedShortcutAtStartAndCallsOnPress() {
        let (controller, hotKey, _) = make(saved: optionCommandH)
        var presses = 0
        controller.onPress = { presses += 1 }
        controller.start()
        #expect(hotKey.registered == optionCommandH)
        hotKey.press()
        #expect(presses == 1)
    }

    @Test func aSavedShortcutThatIsTakenAtStartIsKeptButReported() {
        let (controller, hotKey, _) = make(saved: optionCommandH)
        hotKey.taken = [optionCommandH]
        controller.start()
        #expect(controller.shortcut == optionCommandH)
        #expect(controller.problem == .inUse)
        #expect(hotKey.registered == nil)
    }

    @Test func recordingUnregistersUntilItEnds() {
        let (controller, hotKey, _) = make(saved: optionCommandH)
        controller.start()
        controller.beginRecording()
        #expect(controller.isRecording)
        #expect(hotKey.registered == nil)
        controller.endRecording()
        #expect(!controller.isRecording)
        #expect(hotKey.registered == optionCommandH)
    }

    @Test func recordingAValidShortcutSavesAndRegistersIt() {
        let (controller, hotKey, persister) = make(saved: optionCommandH)
        controller.start()
        controller.beginRecording()
        #expect(controller.record(controlF5))
        #expect(!controller.isRecording)
        #expect(controller.shortcut == controlF5)
        #expect(hotKey.registered == controlF5)
        #expect(persister.document.globalShortcut == controlF5)
        controller.endRecording()  // the recorder's teardown after a save changes nothing
        #expect(hotKey.registered == controlF5)
    }

    @Test func aShortcutInUseIsNotSavedAndThePreviousOneComesBack() {
        let (controller, hotKey, persister) = make(saved: optionCommandH)
        controller.start()
        hotKey.taken = [controlF5]
        controller.beginRecording()
        #expect(!controller.record(controlF5))
        #expect(controller.problem == .inUse)
        #expect(controller.shortcut == optionCommandH)
        #expect(hotKey.registered == optionCommandH)
        #expect(persister.document.globalShortcut == optionCommandH)
        #expect(persister.saved.isEmpty)
    }

    @Test func aShortcutWithoutAModifierKeepsRecording() {
        let (controller, hotKey, persister) = make()
        controller.start()
        controller.beginRecording()
        let plainH = GlobalShortcut(keyCode: 0x04, modifiers: .shift)
        #expect(!controller.record(plainH))
        #expect(controller.problem == .needsModifier)
        #expect(controller.isRecording)
        #expect(hotKey.registrations.isEmpty)
        #expect(persister.saved.isEmpty)
        // A new recording clears the message.
        controller.endRecording()
        controller.beginRecording()
        #expect(controller.problem == nil)
    }

    @Test func aStandardAppShortcutIsRefusedAndKeepsRecording() {
        let (controller, hotKey, persister) = make(saved: optionCommandH)
        controller.start()
        controller.beginRecording()
        let commandC = GlobalShortcut(keyCode: 0x08, modifiers: .command)
        #expect(!controller.record(commandC))
        #expect(controller.problem == .standardShortcut)
        #expect(controller.isRecording)
        #expect(controller.shortcut == optionCommandH)
        #expect(hotKey.registrations == [optionCommandH])  // only the one from start()
        #expect(persister.saved.isEmpty)
        #expect(
            String(localized: GlobalShortcutController.Problem.standardShortcut.message)
                == "That's a standard app shortcut. Add ⌥ or ⌃.")
    }

    @Test func endRecordingRegistersTheSavedShortcutAgain() {
        let (controller, hotKey, _) = make(saved: optionCommandH)
        controller.start()
        controller.beginRecording()
        #expect(hotKey.registered == nil)
        controller.endRecording()
        #expect(hotKey.registered == optionCommandH)
        #expect(hotKey.registrations == [optionCommandH, optionCommandH])
        #expect(controller.problem == nil)
    }

    @Test func aFailedReRegistrationAfterRecordingReportsInUse() {
        let (controller, hotKey, persister) = make(saved: optionCommandH)
        controller.start()
        controller.beginRecording()
        hotKey.taken = [optionCommandH]  // another app took it meanwhile
        controller.endRecording()
        #expect(controller.problem == .inUse)
        #expect(controller.shortcut == optionCommandH)
        #expect(persister.document.globalShortcut == optionCommandH)
    }

    @Test(arguments: [
        (GlobalShortcut(keyCode: 0x08, modifiers: .command), GlobalShortcutController.Problem.standardShortcut),
        (GlobalShortcut(keyCode: 0x08, modifiers: .shift), .needsModifier),
    ])
    func aSavedShortcutThatIsNoLongerAllowedIsNotRegistered(
        saved: GlobalShortcut, problem: GlobalShortcutController.Problem
    ) {
        let (controller, hotKey, _) = make(saved: saved)
        controller.start()
        #expect(controller.shortcut == saved)
        #expect(controller.problem == problem)
        #expect(hotKey.registrations.isEmpty)
        controller.beginRecording()
        controller.endRecording()
        #expect(hotKey.registrations.isEmpty)
    }

    /// Goes through the real `GlobalHotKey` with a fixed list of system shortcuts. The reserved
    /// check comes before any Carbon call, so nothing is registered in the test process.
    @Test func aValidCombinationReservedBySystemIsInUse() {
        let controlUp = GlobalShortcut(keyCode: GlobalShortcut.KeyCode.upArrow, modifiers: .control)
        let missionControl = GlobalHotKey.SymbolicHotKey(
            keyCode: Int(GlobalShortcut.KeyCode.upArrow), carbonModifiers: controlKey, isEnabled: true)
        let hotKey = GlobalHotKey(symbolicHotKeys: { [missionControl] })
        let persister = FakePersister(document: SettingsDocument())
        let controller = GlobalShortcutController(persister: persister, hotKey: hotKey, announce: spoken.say)
        controller.start()
        controller.beginRecording()
        #expect(controlUp.validity == .ok)
        #expect(!controller.record(controlUp))
        #expect(controller.problem == .inUse)
        #expect(controller.shortcut == nil)
        #expect(persister.saved.isEmpty)
    }

    @Test func clearingRemovesTheShortcut() {
        let (controller, hotKey, persister) = make(saved: optionCommandH)
        controller.start()
        controller.clear()
        #expect(controller.shortcut == nil)
        #expect(hotKey.registered == nil)
        #expect(persister.document.globalShortcut == nil)
    }

    @Test func stopUnregistersButKeepsTheSavedValue() {
        let (controller, hotKey, persister) = make(saved: optionCommandH)
        controller.start()
        controller.stop()
        #expect(hotKey.registered == nil)
        #expect(persister.document.globalShortcut == optionCommandH)
    }

    @Test func savingLeavesTheRestOfTheDocumentAlone() {
        let persister = FakePersister(
            document: SettingsDocument(preferences: Preferences(maxBoostPercent: .percent150)))
        let controller = GlobalShortcutController(persister: persister, hotKey: FakeHotKey(), announce: spoken.say)
        controller.start()
        controller.beginRecording()
        controller.record(optionCommandH)
        #expect(persister.document.preferences.maxBoostPercent == .percent150)
        #expect(persister.document.globalShortcut == optionCommandH)
    }

    // MARK: Formatting

    @Test func formatsWithLayoutCharactersAndSpecialKeys() {
        let layout: @MainActor (UInt16) -> String? = { $0 == 0x04 ? "h" : nil }
        #expect(ShortcutFormatter.string(for: optionCommandH, layoutCharacters: layout) == "⌥⌘H")
        #expect(ShortcutFormatter.string(for: controlF5, layoutCharacters: layout) == "⌃F5")
        let space = GlobalShortcut(keyCode: GlobalShortcut.KeyCode.space, modifiers: [.control, .option])
        #expect(ShortcutFormatter.string(for: space, layoutCharacters: layout) == "⌃⌥Space")
        let up = GlobalShortcut(keyCode: GlobalShortcut.KeyCode.upArrow, modifiers: .command)
        #expect(ShortcutFormatter.string(for: up, layoutCharacters: layout) == "⌘↑")
        let unknown = GlobalShortcut(keyCode: 0x0A, modifiers: .command)
        #expect(ShortcutFormatter.string(for: unknown, layoutCharacters: layout) == "⌘Key 10")
    }

    @Test func aDifferentLayoutChangesOnlyTheLabel() {
        // kVK_ANSI_Y types "z" on a German layout.
        let shortcut = GlobalShortcut(keyCode: 0x10, modifiers: .command)
        #expect(ShortcutFormatter.string(for: shortcut, layoutCharacters: { _ in "z" }) == "⌘Z")
        #expect(ShortcutFormatter.string(for: shortcut, layoutCharacters: { _ in "y" }) == "⌘Y")
    }

    @Test func eventModifierFlagsMapToShortcutModifiers() {
        #expect(GlobalShortcut.Modifiers([.command, .option]) == [.command, .option])
        #expect(GlobalShortcut.Modifiers([.control, .shift]) == [.control, .shift])
        #expect(GlobalShortcut.Modifiers([.capsLock, .function, .numericPad]) == [])
    }

    // MARK: Carbon

    @Test func carbonModifiersUseCarbonBits() {
        #expect(GlobalHotKey.carbonModifiers([]) == 0)
        #expect(GlobalHotKey.carbonModifiers(.command) == UInt32(cmdKey))
        #expect(
            GlobalHotKey.carbonModifiers([.command, .option, .control, .shift])
                == UInt32(cmdKey | optionKey | controlKey | shiftKey))
    }

    @Test func enabledSystemShortcutsAreReserved() {
        // ⌘Space (Spotlight) and ⌃↑ (Mission Control, turned off here).
        let spotlight = GlobalHotKey.SymbolicHotKey(
            keyCode: Int(GlobalShortcut.KeyCode.space), carbonModifiers: cmdKey, isEnabled: true)
        let missionControl = GlobalHotKey.SymbolicHotKey(
            keyCode: Int(GlobalShortcut.KeyCode.upArrow), carbonModifiers: controlKey | 0x80_0000, isEnabled: false)
        let hotKeys = [spotlight, missionControl]
        let commandSpace = GlobalShortcut(keyCode: GlobalShortcut.KeyCode.space, modifiers: .command)
        let controlUp = GlobalShortcut(keyCode: GlobalShortcut.KeyCode.upArrow, modifiers: .control)
        let optionSpace = GlobalShortcut(keyCode: GlobalShortcut.KeyCode.space, modifiers: .option)
        #expect(GlobalHotKey.isReservedBySystem(commandSpace, symbolicHotKeys: hotKeys))
        #expect(!GlobalHotKey.isReservedBySystem(controlUp, symbolicHotKeys: hotKeys))
        #expect(!GlobalHotKey.isReservedBySystem(optionSpace, symbolicHotKeys: hotKeys))
        // Extra bits such as the function-key flag are ignored when comparing.
        let enabledUp = GlobalHotKey.SymbolicHotKey(
            keyCode: Int(GlobalShortcut.KeyCode.upArrow), carbonModifiers: controlKey | 0x80_0000, isEnabled: true)
        #expect(GlobalHotKey.isReservedBySystem(controlUp, symbolicHotKeys: [enabledUp]))
    }
}

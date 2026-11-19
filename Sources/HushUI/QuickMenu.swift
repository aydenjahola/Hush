import AppKit
import HushAudio
import HushCore

/// The quick menu's bulk mute item: which way it goes and whether it can be used.
package struct BulkMuteAction: Equatable, Sendable {
    package enum Kind: Equatable, Sendable {
        case muteAllPlaying, unmuteAll
    }

    package var kind: Kind
    package var isEnabled: Bool

    package init(kind: Kind, isEnabled: Bool) {
        self.kind = kind
        self.isEnabled = isEnabled
    }
}

/// A snapshot of everything the quick menu shows, taken each time it opens.
package struct QuickMenuModel: Equatable {
    package struct Output: Equatable {
        package var device: OutputDevice
        package var isCurrent: Bool
    }

    package struct PresetItem: Equatable {
        package var id: Preset.ID
        package var name: String
        /// The current levels match this preset exactly.
        package var isActive: Bool

        package init(id: Preset.ID, name: String, isActive: Bool) {
            self.id = id
            self.name = name
            self.isActive = isActive
        }
    }

    package var outputs: [Output]
    package var bulkMute: BulkMuteAction
    package var canCheckForUpdates: Bool
    package var presets: [PresetItem]
    /// False without Audio Recording permission: presets can't be applied or saved then.
    package var presetsEnabled: Bool
    /// "Duck During Calls" is on (checked).
    package var duckingOn: Bool
    /// False without Audio Recording permission: nothing can be ducked then.
    package var duckingEnabled: Bool

    package init(
        outputs: [Output],
        bulkMute: BulkMuteAction,
        canCheckForUpdates: Bool,
        presets: [PresetItem] = [],
        presetsEnabled: Bool = true,
        duckingOn: Bool = false,
        duckingEnabled: Bool = true
    ) {
        self.outputs = outputs
        self.bulkMute = bulkMute
        self.canCheckForUpdates = canCheckForUpdates
        self.presets = presets
        self.presetsEnabled = presetsEnabled
        self.duckingOn = duckingOn
        self.duckingEnabled = duckingEnabled
    }

    /// The model for the current store and update state. Outputs use the same list (and the
    /// same "current device is always there" rule) as the header's output pill.
    package init(store: MixerStore, updates: UpdateChecker) {
        let current = store.outputDevice
        self.outputs = OutputMenuItems.items(devices: store.outputDevices, current: current).map {
            Output(device: $0, isCurrent: $0.id == current?.id)
        }
        self.bulkMute = store.bulkMute
        self.canCheckForUpdates = updates.checkStatus != .checking
        let active = store.activePresetID
        self.presets = store.presets.map { PresetItem(id: $0.id, name: $0.name, isActive: $0.id == active) }
        self.presetsEnabled = store.controlsEnabled
        self.duckingOn = store.duckingEnabled
        self.duckingEnabled = store.controlsEnabled
    }
}

/// What the quick menu's items do. The app supplies these; tests record them.
package struct QuickMenuActions {
    package var selectOutput: (OutputDevice) -> Void
    package var openSoundSettings: () -> Void
    package var muteAllPlaying: () -> Void
    package var unmuteAll: () -> Void
    package var openSettings: () -> Void
    package var checkForUpdates: () -> Void
    package var quit: () -> Void
    package var applyPreset: (Preset.ID) -> Void
    /// Asks for a name and saves the current levels (the app opens Settings with the save sheet).
    package var savePreset: () -> Void
    /// Opens Settings on the Presets section.
    package var managePresets: () -> Void
    /// Turns "Lower other apps during calls" on or off.
    package var toggleDucking: () -> Void

    package init(
        selectOutput: @escaping (OutputDevice) -> Void,
        openSoundSettings: @escaping () -> Void,
        muteAllPlaying: @escaping () -> Void,
        unmuteAll: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        checkForUpdates: @escaping () -> Void,
        quit: @escaping () -> Void,
        applyPreset: @escaping (Preset.ID) -> Void = { _ in },
        savePreset: @escaping () -> Void = {},
        managePresets: @escaping () -> Void = {},
        toggleDucking: @escaping () -> Void = {}
    ) {
        self.selectOutput = selectOutput
        self.openSoundSettings = openSoundSettings
        self.muteAllPlaying = muteAllPlaying
        self.unmuteAll = unmuteAll
        self.openSettings = openSettings
        self.checkForUpdates = checkForUpdates
        self.quit = quit
        self.applyPreset = applyPreset
        self.savePreset = savePreset
        self.managePresets = managePresets
        self.toggleDucking = toggleDucking
    }
}

/// Builds the menu that opens on a right-click (or two-finger or Control-click) of the menu bar
/// icon: Output ▸, Presets ▸, Duck During Calls, Mute All Playing Apps / Unmute All, Settings…,
/// Check for Updates…, Quit Hush.
package enum QuickMenu {
    /// System Settings → Sound, the same page as the output pill's "Sound Settings…".
    package static var soundSettingsURL: URL { OutputPicker.soundSettingsURL }

    /// Replaces `menu`'s items with a fresh set. Items carry their own enabled state, so the
    /// menu's automatic enabling is turned off.
    package static func populate(_ menu: NSMenu, model: QuickMenuModel, actions: QuickMenuActions) {
        menu.autoenablesItems = false
        menu.items = items(for: model, actions: actions)
    }

    package static func items(for model: QuickMenuModel, actions: QuickMenuActions) -> [NSMenuItem] {
        let output = NSMenuItem(title: String(localized: L10n.output), action: nil, keyEquivalent: "")
        output.image = symbol("hifispeaker.fill")
        output.submenu = outputSubmenu(model.outputs, actions: actions)

        let presets = NSMenuItem(title: String(localized: L10n.presets), action: nil, keyEquivalent: "")
        presets.image = symbol("slider.horizontal.3")
        presets.submenu = presetsSubmenu(model.presets, enabled: model.presetsEnabled, actions: actions)

        let ducking = ActionMenuItem.make(
            title: String(localized: L10n.duckDuringCalls), handler: actions.toggleDucking)
        ducking.image = symbol("speaker.wave.1.fill")
        ducking.state = model.duckingOn ? .on : .off
        ducking.isEnabled = model.duckingEnabled

        let bulk: NSMenuItem
        switch model.bulkMute.kind {
        case .muteAllPlaying:
            bulk = ActionMenuItem.make(title: String(localized: L10n.muteAllPlaying), handler: actions.muteAllPlaying)
            bulk.image = symbol("speaker.slash.fill")
        case .unmuteAll:
            bulk = ActionMenuItem.make(title: String(localized: L10n.unmuteAll), handler: actions.unmuteAll)
            bulk.image = symbol("speaker.wave.2.fill")
        }
        bulk.isEnabled = model.bulkMute.isEnabled

        let settings = ActionMenuItem.make(
            title: String(localized: L10n.settingsEllipsis), keyEquivalent: ",", handler: actions.openSettings)
        let checkForUpdates = ActionMenuItem.make(
            title: String(localized: L10n.checkForUpdates), handler: actions.checkForUpdates)
        checkForUpdates.isEnabled = model.canCheckForUpdates
        let quit = ActionMenuItem.make(title: String(localized: L10n.quit), keyEquivalent: "q", handler: actions.quit)

        return [output, presets, ducking, bulk, .separator(), settings, checkForUpdates, .separator(), quit]
    }

    private static func outputSubmenu(_ outputs: [QuickMenuModel.Output], actions: QuickMenuActions) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for output in outputs {
            let device = output.device
            let item = ActionMenuItem.make(title: device.name) { actions.selectOutput(device) }
            item.image = symbol(device.transport.symbolName)
            item.state = output.isCurrent ? .on : .off
            menu.addItem(item)
        }
        if !outputs.isEmpty { menu.addItem(.separator()) }
        menu.addItem(
            ActionMenuItem.make(title: String(localized: L10n.soundSettings), handler: actions.openSoundSettings))
        return menu
    }

    /// The saved presets (the active one checked), then Save and Manage. With no presets, a
    /// disabled "No Presets" stands in for the list.
    private static func presetsSubmenu(
        _ presets: [QuickMenuModel.PresetItem], enabled: Bool, actions: QuickMenuActions
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if presets.isEmpty {
            let none = NSMenuItem(title: String(localized: L10n.noPresets), action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for preset in presets {
            let id = preset.id
            let item = ActionMenuItem.make(title: preset.name) { actions.applyPreset(id) }
            item.state = preset.isActive ? .on : .off
            item.isEnabled = enabled
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let save = ActionMenuItem.make(
            title: String(localized: L10n.saveCurrentLevelsAsPreset), handler: actions.savePreset)
        save.isEnabled = enabled
        menu.addItem(save)
        menu.addItem(ActionMenuItem.make(title: String(localized: L10n.managePresets), handler: actions.managePresets))
        return menu
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
}

/// Makes menu items that run a closure when chosen, so the menu needs no separate target object.
/// The item keeps its handler alive through `representedObject` (an item's `target` is weak).
package enum ActionMenuItem {
    package static func make(title: String, keyEquivalent: String = "", handler: @escaping () -> Void) -> NSMenuItem {
        let action = MenuItemAction(handler)
        let item = NSMenuItem(title: title, action: #selector(MenuItemAction.run), keyEquivalent: keyEquivalent)
        item.target = action
        item.representedObject = action
        return item
    }

    /// Runs `item`'s handler as if it were chosen (tests).
    package static func perform(_ item: NSMenuItem) {
        (item.representedObject as? MenuItemAction)?.run()
    }
}

final class MenuItemAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
        super.init()
    }

    @objc func run() { handler() }
}

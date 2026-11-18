import HushAudio
import HushCore

/// "Remember levels for each output device": each output device, keyed by UID, keeps its own app
/// levels. The rules live in `DeviceLevelBook`; this extension keeps the book in step with the
/// current levels and switches sets when the default output changes.
///
/// The current levels (`settings`) always belong to `levelsDevice`, and every change to them is
/// copied into that device's set, so the book is up to date whenever it's saved or switched.
/// Presets, Mute All, Unmute All and Reset All Levels all act on `settings`, so they act on the
/// current device's levels.
package extension MixerStore {
    var rememberLevelsPerDevice: Bool {
        get { preferences.rememberLevelsPerDevice }
        set { setRememberLevelsPerDevice(newValue) }
    }

    /// Turning it on seeds the current device's set from the current levels. Turning it off keeps
    /// the current levels as the single set; other devices' sets stay saved for next time.
    func setRememberLevelsPerDevice(_ on: Bool) {
        guard on != preferences.rememberLevelsPerDevice else { return }
        preferences.rememberLevelsPerDevice = on
        levelsDevice = on ? outputDevice.flatMap(Self.levelsDevice(for:)) : nil
        settingsDidChange()  // stores the seeded set and saves the preference
    }

    /// The devices with saved levels, sorted by name, for Settings.
    var savedLevelDevices: [DeviceLevelBook.Device] { deviceLevelBook.devices }

    /// Drops a device's saved levels. Forgetting the current device changes nothing audible: the
    /// current levels stay, and it gets a set again with the next change or switch.
    func forgetLevels(forDevice uid: String) {
        guard deviceLevelBook.levels(for: uid) != nil else { return }
        deviceLevelBook.forget(uid)
        saver.schedule()
    }
}

extension MixerStore {
    /// Copies the current levels (and the device's name) into the current device's set while the
    /// feature is on. The book is only assigned when the set changed, so observers such as the
    /// Settings list aren't invalidated by changes that leave it as it was.
    func storeCurrentDeviceLevels() {
        guard preferences.rememberLevelsPerDevice, let levelsDevice else { return }
        var book = deviceLevelBook
        book.store(settings, for: levelsDevice, maxPercent: maxPercent, excluding: hiddenApps.ids)
        if book != deviceLevelBook { deviceLevelBook = book }
    }

    /// Switches to `device`'s levels when the feature is on and its UID differs from the device
    /// the current levels belong to. Returns whether the sets switched. Same-UID reports (a
    /// re-enumeration across sleep, say) and devices without a UID never switch; a new name for
    /// the same UID is just recorded and saved.
    func switchDeviceLevels(to device: OutputDevice?) -> Bool {
        guard preferences.rememberLevelsPerDevice, let device, let new = Self.levelsDevice(for: device) else {
            return false
        }
        guard levelsDevice?.uid != new.uid else {
            if levelsDevice?.name != new.name {
                levelsDevice = new
                storeCurrentDeviceLevels()  // the saved name follows a rename
                saver.schedule()
            }
            return false
        }
        let result = deviceLevelBook.switching(
            from: levelsDevice, to: new, current: settings, maxPercent: maxPercent, excluding: hiddenApps.ids)
        levelsDevice = new
        deviceLevelBook = result.book
        settings = result.settings
        return true
    }

    /// Before the engines are rebuilt on a new device whose levels were just loaded: a control
    /// engine takes its new gain now, so its rebuild hands over at that gain rather than the old
    /// device's. Engines the new levels don't need as control engines are torn down; reconcile
    /// then starts a meter-only one if the popover wants it. Meter-only engines are rebuilt as
    /// they are and switched to control in place by reconcile if the new levels need it. Apps with
    /// no engine get one through the normal fresh-engine path.
    func prepareEnginesForSwitchedLevels() {
        var present: [String: AudioApp] = [:]
        for app in apps { present[app.id] = app }
        for (id, engine) in engines {
            let setting = settings[id] ?? AppVolumeSetting()
            let desired = present[id].flatMap { app in
                EnginePlan.desiredMode(
                    setting: setting,
                    isPlaying: app.isPlaying,
                    isPopoverVisible: isPopoverVisible,
                    showLevelMeters: preferences.appearance.showLevelMeters)
            }
            switch (engine.mode, desired) {
            case (_, nil), (.control, .meterOnly):
                tearDownEngine(id)
            case (.control, .control):
                engine.setGain(setting.effectiveGain)
            case (.meterOnly, _):
                break
            }
        }
    }

    private static func levelsDevice(for device: OutputDevice) -> DeviceLevelBook.Device? {
        device.uid.isEmpty ? nil : DeviceLevelBook.Device(uid: device.uid, name: device.name)
    }
}

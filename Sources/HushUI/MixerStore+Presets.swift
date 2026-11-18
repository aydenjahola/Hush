import Foundation
import HushAudio
import HushCore

/// Volume presets: named snapshots of every app's level that the user can switch between.
///
/// Presets live in `presetLibrary` and are written in the same debounced save as the levels
/// (`persistNow`), so a levels save never overwrites them with an older copy.
package extension MixerStore {
    var presets: [Preset] { presetLibrary.presets }

    /// The preset the current levels match exactly, if any. Computed from the levels each time,
    /// so it stops being active as soon as any app is adjusted. Hidden apps are left out, so a
    /// preset that holds one can still be active.
    var activePresetID: Preset.ID? {
        presetLibrary.activePreset(for: settings, maxPercent: maxPercent, excluding: hiddenApps.ids)?.id
    }

    func checkPresetName(_ name: String, renaming: Preset.ID? = nil) -> PresetLibrary.NameCheck {
        presetLibrary.check(name: name, renaming: renaming)
    }

    /// Saves every app that isn't at 100% and unmuted under `name`, replacing the preset with
    /// that name if there is one. Returns nil when the name is empty or there are already
    /// `PresetLibrary.maxCount` presets.
    @discardableResult
    func saveCurrentLevelsAsPreset(named name: String) -> Preset? {
        let levels = Preset.levels(from: settings, displayName: presetDisplayName(for:))
        guard let preset = presetLibrary.save(name: name, apps: levels) else { return nil }
        saver.schedule()
        return preset
    }

    /// Reproduces the preset exactly: its apps get their saved level and mute, and every other
    /// adjusted app goes back to 100% and unmuted. One debounced save and one reconcile, which
    /// creates and stops engines as usual. Hidden apps in the preset are skipped: they never get
    /// a level, and the rest of the preset still applies.
    func applyPreset(_ id: Preset.ID) {
        guard controlsEnabled, let preset = presetLibrary.preset(id) else { return }
        let applied = preset.applied(
            to: settings, maxPercent: maxPercent, now: now(), excluding: hiddenApps.ids)
        guard applied != settings else { return }
        for id in Set(settings.keys).union(applied.keys) { engineErrors[id] = nil }
        settings = applied
        settingsDidChange()
    }

    @discardableResult
    func renamePreset(_ id: Preset.ID, to name: String) -> Bool {
        guard presetLibrary.rename(id, to: name) else { return false }
        saver.schedule()
        return true
    }

    func deletePreset(_ id: Preset.ID) {
        guard presetLibrary.preset(id) != nil else { return }
        presetLibrary.delete(id)
        saver.schedule()
    }

    /// The name to store with an app's level: the running app's name, else the installed app's,
    /// else the ID.
    private func presetDisplayName(for id: String) -> String {
        if let app = apps.first(where: { $0.id == id }) { return app.displayName }
        return cachedInstalledApp(id)?.displayName ?? id
    }
}

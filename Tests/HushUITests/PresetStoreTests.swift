import AppKit
import Foundation
import HushAudio
import HushCore
import Testing

@testable import HushUI

@MainActor
@Suite(.timeLimit(.minutes(1))) struct PresetStoreTests {
    private let earlier = Date(timeIntervalSince1970: 1_700_000_000)

    private func level(_ percent: Int, muted: Bool = false, name: String) -> Preset.Level {
        Preset.Level(displayName: name, percent: percent, isMuted: muted)
    }

    // MARK: Save

    @Test func savingCapturesEveryAdjustedAppWithItsName() throws {
        let saved = AppVolumeSetting(percent: 30, lastAdjusted: earlier)
        let h = Harness(
            document: SettingsDocument(apps: ["installed": saved, "unknown": mutedSetting()]),
            installedApp: { id in id == "installed" ? InstalledAppInfo(displayName: "Installed App", icon: nil) : nil })
        h.processes.emit([
            AudioApp(id: "running", displayName: "Running App", processObjectIDs: [42], isPlaying: true),
            makeApp("untouched", objects: [43]),
        ])
        h.store.setPercent(70, for: "running")

        let preset = try #require(h.store.saveCurrentLevelsAsPreset(named: " Call "))

        #expect(preset.name == "Call")
        #expect(
            preset.apps == [
                "running": level(70, name: "Running App"),
                "installed": level(30, name: "Installed App"),
                "unknown": level(100, muted: true, name: "unknown"),
            ])
        #expect(h.store.presets == [preset])
    }

    @Test func savingWritesOnceThroughTheDebouncedSave() {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(60, for: "a")
        h.store.saveCurrentLevelsAsPreset(named: "Call")
        #expect(h.persister.saved.isEmpty, "debounced, not written straight away")

        h.store.flushPendingSave()

        #expect(h.persister.saved.count == 1)
        #expect(h.persister.saved.last?.presets?.map(\.name) == ["Call"])
        #expect(h.persister.saved.last?.apps["a"]?.percent == 60)
    }

    @Test func savingAnExistingNameReplacesIt() throws {
        let call = Preset(name: "Call", apps: ["old": level(10, name: "Old")])
        let h = Harness(document: SettingsDocument(presets: [call]))
        h.processes.emit([makeApp("a")])
        h.store.setPercent(60, for: "a")

        let replaced = try #require(h.store.saveCurrentLevelsAsPreset(named: "call"))

        #expect(replaced.id == call.id)
        #expect(h.store.presets.count == 1)
        #expect(h.store.presets.first?.apps == ["a": level(60, name: "a")])
    }

    @Test func savingRefusesABlankNameOrAFullLibrary() {
        let full = (1...PresetLibrary.maxCount).map { Preset(name: "P\($0)", apps: [:]) }
        let h = Harness(document: SettingsDocument(presets: full))
        #expect(h.store.saveCurrentLevelsAsPreset(named: "New") == nil)
        #expect(h.store.saveCurrentLevelsAsPreset(named: "  ") == nil)
        #expect(h.store.checkPresetName("New") == .limitReached)
        h.store.flushPendingSave()
        #expect(h.persister.saved.isEmpty)
    }

    // MARK: Apply

    @Test func applyingReproducesThePresetAndResetsEveryOtherApp() throws {
        let preset = Preset(name: "Call", apps: ["chat": level(150, name: "Chat"), "music": level(20, name: "Music")])
        let h = Harness(
            document: SettingsDocument(
                preferences: Preferences(maxBoostPercent: .percent200),
                apps: ["game": AppVolumeSetting(percent: 40, lastAdjusted: earlier)],
                presets: [preset]))
        h.processes.emit([makeApp("chat"), makeApp("music", objects: [43]), makeApp("game", objects: [44])])
        let game = try #require(h.factory.live("game"))

        h.store.applyPreset(preset.id)

        let strips = Dictionary(uniqueKeysWithValues: h.store.strips.map { ($0.id, $0.setting) })
        #expect(strips["chat"]?.percent == 150)
        #expect(strips["music"]?.percent == 20)
        #expect(strips["game"] == AppVolumeSetting(), "not in the preset, so back to 100% and unmuted")
        #expect(game.isStopped, "nothing left to do for it while the popover is closed")
        #expect(try isApproximatelyEqual(#require(h.factory.live("chat")).initialGain, VolumeCurve.gain(percent: 150)))
        #expect(try isApproximatelyEqual(#require(h.factory.live("music")).initialGain, VolumeCurve.gain(percent: 20)))
        #expect(h.store.activePresetID == preset.id)

        #expect(h.persister.saved.isEmpty, "one debounced save")
        h.store.flushPendingSave()
        #expect(h.persister.saved.count == 1)
        #expect(h.persister.saved.last?.apps.keys.sorted() == ["chat", "music"])
        #expect(h.persister.saved.last?.apps["chat"]?.lastAdjusted == Harness.fixedNow)
    }

    @Test func applyingClampsToTheCurrentMaximumBoost() {
        let preset = Preset(name: "Loud", apps: ["a": level(200, name: "A")])
        let h = Harness(
            document: SettingsDocument(preferences: Preferences(maxBoostPercent: .percent150), presets: [preset]))
        h.processes.emit([makeApp("a")])
        h.store.applyPreset(preset.id)
        #expect(h.store.strips.first?.setting.percent == 150)
        #expect(h.store.activePresetID == preset.id)
    }

    @Test func applyingDoesNothingWithoutPermission() {
        let preset = Preset(name: "Call", apps: ["a": level(20, name: "A")])
        let h = Harness(document: SettingsDocument(presets: [preset]), permission: .denied)
        h.processes.emit([makeApp("a")])
        h.store.applyPreset(preset.id)
        #expect(h.store.strips.first?.setting == AppVolumeSetting())
        #expect(h.factory.made.isEmpty)
        h.store.flushPendingSave()
        #expect(h.persister.saved.isEmpty)
    }

    @Test func applyingTheActivePresetAgainChangesNothing() {
        let saved = AppVolumeSetting(percent: 20, lastAdjusted: earlier)
        let preset = Preset(name: "Call", apps: ["a": level(20, name: "A")])
        let h = Harness(document: SettingsDocument(apps: ["a": saved], presets: [preset]))
        h.processes.emit([makeApp("a")])
        h.store.applyPreset(preset.id)
        h.store.flushPendingSave()
        #expect(h.persister.saved.isEmpty)
        #expect(h.store.strips.first?.setting == saved)
    }

    // MARK: Active preset

    @Test func activePresetFollowsTheLevels() {
        let preset = Preset(name: "Call", apps: ["a": level(20, name: "A")])
        let h = Harness(document: SettingsDocument(presets: [preset]))
        h.processes.emit([makeApp("a")])
        #expect(h.store.activePresetID == nil)

        h.store.setPercent(20, for: "a")
        #expect(h.store.activePresetID == preset.id)

        h.store.toggleMute(for: "a")
        #expect(h.store.activePresetID == nil)
    }

    // MARK: Rename and delete

    @Test func renamingAndDeletingAreSaved() {
        let call = Preset(name: "Call", apps: [:])
        let focus = Preset(name: "Focus", apps: [:])
        let h = Harness(document: SettingsDocument(presets: [call, focus]))

        #expect(!h.store.renamePreset(call.id, to: "FOCUS"))
        #expect(h.store.renamePreset(call.id, to: "Meeting"))
        h.store.flushPendingSave()
        #expect(h.persister.saved.last?.presets?.map(\.name) == ["Meeting", "Focus"])

        h.store.deletePreset(call.id)
        h.store.deletePreset(focus.id)
        h.store.flushPendingSave()
        #expect(h.store.presets.isEmpty)
        #expect(h.persister.saved.last?.presets == nil, "no presets left, so none in the file")
    }

    // MARK: Persistence

    @Test func presetsSurviveLevelSavesAndOtherWritersInTheSameFile() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "HushTests-\(UUID().uuidString)")
        let file = directory.appending(path: "settings.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = SettingsStore(fileURL: file)
        let processes = FakeProcessSource()
        let store = MixerStore(
            processSource: processes,
            outputSource: FakeOutputSource(),
            engineFactory: FakeEngineFactory(),
            permissionSource: FakePermission(),
            persister: settings,
            saveDelay: .seconds(3600),
            now: { Harness.fixedNow },
            installedApp: { _ in nil })
        store.start()
        processes.emit([makeApp("a")])

        store.setPercent(40, for: "a")
        store.saveCurrentLevelsAsPreset(named: "Quiet")
        store.flushPendingSave()
        // The update checker writes its own section through the same SettingsStore.
        settings.saveUpdateSettings(UpdateSettings(automaticUpdateChecks: false))
        // Later level changes are saved as a whole document section; the presets must stay.
        store.setPercent(90, for: "a")
        store.flushPendingSave()

        let onDisk = try SettingsDocument.decode(from: Data(contentsOf: file))
        #expect(onDisk.presets?.map(\.name) == ["Quiet"])
        #expect(onDisk.presets?.first?.apps["a"]?.percent == 40)
        #expect(onDisk.apps["a"]?.percent == 90)
        #expect(!onDisk.updates.automaticUpdateChecks)

        let reloaded = MixerStore(
            processSource: FakeProcessSource(),
            outputSource: FakeOutputSource(),
            engineFactory: FakeEngineFactory(),
            permissionSource: FakePermission(),
            persister: SettingsStore(fileURL: file))
        #expect(reloaded.presets.map(\.name) == ["Quiet"])
    }

    // MARK: Quick menu model

    @Test func quickMenuModelListsPresetsAndChecksTheActiveOne() {
        let call = Preset(name: "Call", apps: ["a": level(20, name: "A")])
        let focus = Preset(name: "Focus", apps: [:])
        let h = Harness(document: SettingsDocument(presets: [call, focus]))
        let model = QuickMenuModel(store: h.store, updates: UpdateHarness().checker)
        #expect(
            model.presets == [
                QuickMenuModel.PresetItem(id: call.id, name: "Call", isActive: false),
                QuickMenuModel.PresetItem(id: focus.id, name: "Focus", isActive: true),
            ])
        #expect(model.presetsEnabled)
        #expect(
            !QuickMenuModel(store: Harness(permission: .denied).store, updates: UpdateHarness().checker).presetsEnabled)
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1))) struct SettingsNavigatorTests {
    @Test func takeReturnsThePendingRequestOnce() {
        let navigator = SettingsNavigator()
        #expect(navigator.take() == nil)
        navigator.request(.savePreset)
        #expect(navigator.take() == .savePreset)
        #expect(navigator.pending == nil)
        #expect(navigator.take() == nil)
    }
}

import AppKit
import Foundation
import HushAudio
import HushCore
import Testing

@testable import HushUI

@MainActor
@Suite(.timeLimit(.minutes(1))) struct DeviceLevelsStoreTests {
    private let speakers = OutputDevice(id: 1, uid: "built-in", name: "MacBook Pro Speakers")
    private let headphones = OutputDevice(id: 2, uid: "airpods", name: "AirPods Pro")
    private let earlier = Date(timeIntervalSince1970: 1_700_000_000)

    private func percent(_ h: Harness, _ id: String) -> Int? {
        h.store.strips.first { $0.id == id }?.setting.percent
    }

    private func setting(_ percent: Int, muted: Bool = false) -> AppVolumeSetting {
        AppVolumeSetting(percent: percent, isMuted: muted, lastAdjusted: earlier)
    }

    /// The feature on, with the speakers' levels as given and the headphones' saved set as given.
    private func harness(
        speakers speakerApps: [String: AppVolumeSetting],
        headphones headphoneApps: [String: AppVolumeSetting]?,
        hiddenApps: [HiddenApp]? = nil,
        presets: [Preset]? = nil
    ) -> Harness {
        var sets = ["built-in": DeviceLevels(name: speakers.name, apps: speakerApps)]
        if let headphoneApps { sets["airpods"] = DeviceLevels(name: headphones.name, apps: headphoneApps) }
        return Harness(
            document: SettingsDocument(
                preferences: Preferences(rememberLevelsPerDevice: true),
                apps: speakerApps,
                hiddenApps: hiddenApps,
                presets: presets,
                deviceLevels: sets))
    }

    // MARK: Switching

    @Test func offByDefaultKeepsOneLevelPerApp() {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(40, for: "a")
        h.output.emit(headphones)
        h.store.setPercent(150, for: "a")
        h.output.emit(speakers)
        #expect(percent(h, "a") == 150)
        #expect(h.store.deviceLevelBook.isEmpty)
        h.store.flushPendingSave()
        #expect(h.persister.saved.last?.deviceLevels == nil)
        #expect(h.persister.saved.last?.preferences.rememberLevelsPerDevice == false)
    }

    @Test func turningOnThenSwitchingRoundTrips() {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(40, for: "a")

        h.store.rememberLevelsPerDevice = true
        #expect(h.store.savedLevelDevices.map(\.uid) == ["built-in"], "turning it on seeds the current device")
        #expect(h.store.deviceLevelBook.levels(for: "built-in")?.apps["a"]?.percent == 40)

        h.output.emit(headphones)
        #expect(percent(h, "a") == 40, "the first visit carries the levels over")
        h.store.setPercent(150, for: "a")
        #expect(h.store.deviceLevelBook.levels(for: "airpods")?.apps["a"]?.percent == 150)

        h.output.emit(speakers)
        #expect(percent(h, "a") == 40, "switching back restores the speakers' levels")
        h.output.emit(headphones)
        #expect(percent(h, "a") == 150)
        #expect(h.store.savedLevelDevices.map(\.name) == ["AirPods Pro", "MacBook Pro Speakers"])
    }

    @Test func switchingBackRestoresEachDevicesLevelsAndMutes() {
        let h = harness(
            speakers: ["a": setting(40), "b": setting(100, muted: true)],
            headphones: ["a": setting(150)])
        h.processes.emit([makeApp("a"), makeApp("b", objects: [43])])

        h.output.emit(headphones)
        #expect(percent(h, "a") == 150)
        #expect(h.store.strips.first { $0.id == "b" }?.setting.isMuted == false)

        h.output.emit(speakers)
        #expect(percent(h, "a") == 40)
        #expect(h.store.strips.first { $0.id == "b" }?.setting.isMuted == true)
    }

    @Test func theFirstVisitChangesNothingAudible() throws {
        let h = Harness(
            document: SettingsDocument(
                preferences: Preferences(rememberLevelsPerDevice: true), apps: ["a": setting(40)]))
        h.processes.emit([makeApp("a")])
        let engine = try #require(h.factory.live("a"))

        h.output.emit(headphones)

        #expect(h.factory.live("a") === engine, "rebuilt, not replaced")
        #expect(engine.rebuiltDeviceIDs == [2])
        #expect(try isApproximatelyEqual(#require(engine.gainsAtRebuild.last), VolumeCurve.gain(percent: 40)))
        #expect(h.store.deviceLevelBook.levels(for: "airpods")?.apps["a"]?.percent == 40)
    }

    @Test func turningOffKeepsTheCurrentLevelsAndTheSavedSets() {
        let h = harness(speakers: ["a": setting(40)], headphones: ["a": setting(150)])
        h.processes.emit([makeApp("a")])
        h.output.emit(headphones)
        #expect(percent(h, "a") == 150)

        h.store.rememberLevelsPerDevice = false
        #expect(percent(h, "a") == 150, "the current device's levels stay as the single set")
        h.output.emit(speakers)
        #expect(percent(h, "a") == 150, "no switching while it's off")
        h.store.setPercent(70, for: "a")
        #expect(h.store.deviceLevelBook.levels(for: "built-in")?.apps["a"]?.percent == 40, "saved sets are kept")
        h.store.flushPendingSave()
        #expect(h.persister.saved.last?.deviceLevels?.keys.sorted() == ["airpods", "built-in"])

        // On again: the current device (the speakers) is seeded from the current levels.
        h.store.rememberLevelsPerDevice = true
        #expect(h.store.deviceLevelBook.levels(for: "built-in")?.apps["a"]?.percent == 70)
        h.output.emit(headphones)
        #expect(percent(h, "a") == 150, "the other device's set came back")
    }

    @Test func aSameUIDReportNeverSwitches() throws {
        let h = harness(speakers: ["a": setting(40)], headphones: ["a": setting(150)])
        h.processes.emit([makeApp("a")])
        let engine = try #require(h.factory.live("a"))

        // The speakers re-enumerated under a new object ID, as after a wake.
        h.output.emit(OutputDevice(id: 9, uid: "built-in", name: "MacBook Pro Speakers"))
        h.simulateWake()

        #expect(percent(h, "a") == 40)
        #expect(engine.rebuiltDeviceIDs.isEmpty, "kept, as in #33")
        #expect(h.store.healthCheckTask != nil)
        #expect(try isApproximatelyEqual(#require(h.factory.live("a")).currentGain, VolumeCurve.gain(percent: 40)))
    }

    @Test func aDeviceWithoutAUIDNeverSwitches() {
        let h = harness(speakers: ["a": setting(40)], headphones: nil)
        h.processes.emit([makeApp("a")])
        h.output.emit(OutputDevice(id: 5, uid: "", name: "Mystery"))
        h.store.setPercent(60, for: "a")
        #expect(h.store.savedLevelDevices.map(\.uid) == ["built-in"])
        #expect(h.store.deviceLevelBook.levels(for: "built-in")?.apps["a"]?.percent == 60)
    }

    // MARK: Engines

    @Test func rebuiltEnginesStartAtTheNewDevicesGains() throws {
        let h = harness(
            speakers: ["a": setting(40), "b": setting(60)],
            headphones: ["a": setting(150), "b": setting(100, muted: true), "c": setting(30)])
        h.processes.emit([makeApp("a"), makeApp("b", objects: [43]), makeApp("c", objects: [44])])
        let a = try #require(h.factory.live("a"))
        let b = try #require(h.factory.live("b"))
        #expect(h.factory.live("c") == nil, "at 100% on the speakers, so no engine")
        let eventsBefore = h.factory.events.count

        h.output.emit(headphones)

        #expect(h.factory.live("a") === a)
        #expect(h.factory.live("b") === b)
        #expect(a.gainsAtRebuild == [VolumeCurve.gain(percent: 150)], "never the speakers' gain")
        #expect(b.gainsAtRebuild == [0], "muted on the headphones")
        #expect(a.mode == .control)
        #expect(isApproximatelyEqual(a.currentGain, VolumeCurve.gain(percent: 150)))
        let c = try #require(h.factory.live("c"), "100% to adjusted: a fresh engine")
        #expect(c.mode == .control)
        #expect(isApproximatelyEqual(c.initialGain, VolumeCurve.gain(percent: 30)))
        let made = h.factory.events.dropFirst(eventsBefore).filter { $0.hasPrefix("make") }
        #expect(made == ["make c control"], "the adjusted apps were rebuilt, not replaced")
    }

    @Test func anAppAtFullVolumeOnTheNewDeviceIsTornDownNotRebuilt() throws {
        let h = harness(speakers: ["a": setting(40)], headphones: [:])
        h.processes.emit([makeApp("a")])
        let a = try #require(h.factory.live("a"))

        h.output.emit(headphones)

        #expect(a.isStopped)
        #expect(a.rebuiltDeviceIDs.isEmpty, "torn down before the rebuild, never restarted at the old gain")
        #expect(h.factory.live("a") == nil)
        #expect(h.store.engineCount == 0)
    }

    @Test func aControlEngineNoLongerNeededWithMetersOnBecomesAFreshMeterEngine() throws {
        let h = harness(speakers: ["a": setting(40)], headphones: [:])
        h.processes.emit([makeApp("a")])
        h.store.popoverDidAppear()
        let a = try #require(h.factory.live("a"))
        #expect(a.mode == .control)

        h.output.emit(headphones)

        #expect(a.isStopped)
        #expect(a.rebuiltDeviceIDs.isEmpty)
        let meter = try #require(h.factory.live("a"))
        #expect(meter.mode == .meterOnly)
    }

    @Test func aMeterEngineIsRebuiltThenTakesControlInPlace() throws {
        let h = harness(speakers: [:], headphones: ["a": setting(30)])
        h.processes.emit([makeApp("a")])
        h.store.popoverDidAppear()
        let meter = try #require(h.factory.live("a"))
        #expect(meter.mode == .meterOnly)

        h.output.emit(headphones)

        #expect(h.factory.live("a") === meter)
        #expect(meter.rebuiltDeviceIDs == [2])
        #expect(meter.mode == .control)
        #expect(isApproximatelyEqual(meter.currentGain, VolumeCurve.gain(percent: 30)))
    }

    // MARK: Interactions

    @Test func presetsAndBulkMuteActOnTheCurrentDevice() {
        let preset = Preset(name: "Call", apps: ["a": Preset.Level(displayName: "A", percent: 20)])
        let h = harness(speakers: ["a": setting(40)], headphones: nil, presets: [preset])
        h.processes.emit([makeApp("a"), makeApp("b", objects: [43])])
        h.output.emit(headphones)
        #expect(h.store.activePresetID == nil)

        h.store.applyPreset(preset.id)
        #expect(h.store.activePresetID == preset.id)
        #expect(h.store.deviceLevelBook.levels(for: "airpods")?.apps["a"]?.percent == 20)
        h.store.muteAllPlaying()
        #expect(h.store.deviceLevelBook.levels(for: "airpods")?.apps["b"]?.isMuted == true)

        h.output.emit(speakers)
        #expect(percent(h, "a") == 40)
        #expect(h.store.strips.first { $0.id == "b" }?.setting.isMuted == false)
        #expect(h.store.activePresetID == nil, "the check uses the current levels")

        h.output.emit(headphones)
        #expect(h.store.strips.first { $0.id == "b" }?.setting.isMuted == true)
        h.store.unmuteAll()
        #expect(h.store.deviceLevelBook.levels(for: "airpods")?.apps["b"] == nil)
        #expect(h.store.deviceLevelBook.levels(for: "built-in")?.apps["a"]?.percent == 40)
    }

    @Test func hiddenAppsAreNeverStoredOrApplied() {
        let h = harness(
            speakers: ["a": setting(40), "x": setting(30)],
            headphones: ["a": setting(150), "x": setting(20)])
        h.processes.emit([makeApp("a"), makeApp("x", objects: [43])])

        h.store.hideApp("x", displayName: "X")
        #expect(h.store.deviceLevelBook.levels(for: "built-in")?.apps["x"] == nil)
        #expect(h.store.deviceLevelBook.levels(for: "airpods")?.apps["x"] == nil, "dropped from every device")

        h.output.emit(headphones)
        #expect(h.store.settings["x"] == nil)
        #expect(h.factory.live("x") == nil)
        h.store.showApp("x")
        #expect(h.store.strips.first { $0.id == "x" }?.setting == AppVolumeSetting())
    }

    @Test func hiddenAppsInALoadedFileAreStripped() {
        let h = harness(
            speakers: ["a": setting(40)],
            headphones: ["a": setting(150), "x": setting(20)],
            hiddenApps: [HiddenApp(bundleID: "x", displayName: "X")])
        h.processes.emit([makeApp("a"), makeApp("x", objects: [43])])
        h.output.emit(headphones)
        #expect(h.store.settings["x"] == nil)
        #expect(h.factory.live("x") == nil)
    }

    @Test func forgettingADeviceDropsOnlyItsStoredCopy() {
        let h = harness(speakers: ["a": setting(40)], headphones: ["a": setting(150)])
        h.processes.emit([makeApp("a")])

        h.store.forgetLevels(forDevice: "airpods")
        h.store.forgetLevels(forDevice: "built-in")
        #expect(h.store.savedLevelDevices.isEmpty)
        #expect(percent(h, "a") == 40, "forgetting the current device changes nothing audible")

        h.output.emit(headphones)
        #expect(percent(h, "a") == 40, "the headphones were forgotten, so the levels carry over")
        h.store.flushPendingSave()
        #expect(h.persister.saved.last?.deviceLevels?.keys.sorted() == ["airpods", "built-in"])
    }

    @Test func resetAllLevelsClearsEveryDevicesSet() {
        let h = harness(speakers: ["a": setting(40)], headphones: ["a": setting(150)])
        h.processes.emit([makeApp("a")])

        h.store.resetAllLevels()

        #expect(percent(h, "a") == 100)
        #expect(h.store.savedLevelDevices.map(\.uid) == ["built-in"], "only the current device, now empty")
        #expect(h.store.deviceLevelBook.levels(for: "built-in")?.apps.isEmpty == true)
        h.output.emit(headphones)
        #expect(percent(h, "a") == 100)
    }

    @Test func loweringTheMaximumBoostClampsEveryDevice() {
        let h = harness(speakers: ["a": setting(40)], headphones: ["a": setting(200)])
        h.processes.emit([makeApp("a")])
        h.store.maxBoost = .percent150
        #expect(h.store.deviceLevelBook.levels(for: "airpods")?.apps["a"]?.percent == 150)
        h.output.emit(headphones)
        #expect(percent(h, "a") == 150)
    }

    // MARK: Persistence

    @Test func switchingSavesBothSetsInOneDebouncedWrite() {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(40, for: "a")
        h.store.rememberLevelsPerDevice = true
        h.output.emit(headphones)
        h.store.setPercent(150, for: "a")
        #expect(h.persister.saved.isEmpty, "debounced")

        h.store.flushPendingSave()

        #expect(h.persister.saved.count == 1)
        let saved = h.persister.saved.last
        #expect(saved?.preferences.rememberLevelsPerDevice == true)
        #expect(saved?.apps["a"]?.percent == 150)
        #expect(
            saved?.deviceLevels?["built-in"]
                == DeviceLevels(
                    name: "MacBook Pro Speakers",
                    apps: ["a": AppVolumeSetting(percent: 40, lastAdjusted: Harness.fixedNow)]))
        #expect(saved?.deviceLevels?["airpods"]?.apps["a"]?.percent == 150)
    }

    @Test func deviceLevelsSurviveOtherWritersAndTheyKeepTheirSections() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "HushTests-\(UUID().uuidString)")
        let file = directory.appending(path: "settings.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = SettingsStore(fileURL: file)
        let processes = FakeProcessSource()
        let output = FakeOutputSource()
        let store = MixerStore(
            processSource: processes,
            outputSource: output,
            engineFactory: FakeEngineFactory(),
            permissionSource: FakePermission(),
            persister: settings,
            saveDelay: .seconds(3600),
            now: { Harness.fixedNow },
            installedApp: { _ in nil })
        store.start()
        processes.emit([makeApp("a")])
        let shortcut = GlobalShortcut(keyCode: 0x04, modifiers: [.option, .command])

        store.setPercent(40, for: "a")
        store.rememberLevelsPerDevice = true
        output.emit(headphones)
        store.setPercent(150, for: "a")
        store.flushPendingSave()
        // The update checker and the shortcut recorder write their own sections to the same file.
        settings.saveUpdateSettings(UpdateSettings(automaticUpdateChecks: false))
        settings.update { $0.globalShortcut = shortcut }
        // A later level save writes the whole mixer-owned part; the other sections must stay.
        store.setPercent(120, for: "a")
        store.flushPendingSave()

        let onDisk = try SettingsDocument.decode(from: Data(contentsOf: file))
        #expect(onDisk.preferences.rememberLevelsPerDevice)
        #expect(onDisk.deviceLevels?["built-in"]?.apps["a"]?.percent == 40)
        #expect(onDisk.deviceLevels?["airpods"]?.apps["a"]?.percent == 120)
        #expect(onDisk.apps["a"]?.percent == 120)
        #expect(!onDisk.updates.automaticUpdateChecks)
        #expect(onDisk.globalShortcut == shortcut)

        let reloadedOutput = FakeOutputSource()
        let reloadedProcesses = FakeProcessSource()
        let reloaded = MixerStore(
            processSource: reloadedProcesses,
            outputSource: reloadedOutput,
            engineFactory: FakeEngineFactory(),
            permissionSource: FakePermission(),
            persister: SettingsStore(fileURL: file),
            saveDelay: .seconds(3600))
        reloaded.start()
        reloadedProcesses.emit([makeApp("a")])
        #expect(reloaded.rememberLevelsPerDevice)
        #expect(
            reloaded.strips.first?.setting.percent == 40,
            "launched on the speakers, so their saved levels load")
        reloadedOutput.emit(headphones)
        #expect(reloaded.strips.first?.setting.percent == 120)
    }
}

import AppKit
import CoreAudio
import Foundation
import HushAudio
import HushCore
import Testing
@testable import HushUI

@MainActor
@Suite(.timeLimit(.minutes(1))) struct HiddenAppsTests {
    private func hidden(_ ids: String...) -> [HiddenApp] {
        ids.map { HiddenApp(bundleID: $0, displayName: $0) }
    }

    // MARK: Pure rules

    @Test func visibleAppsDropsHiddenOnes() {
        let apps = [makeApp("a"), makeApp("b"), makeApp("c")]
        #expect(HiddenAppsPlan.visibleApps(apps, hidden: ["b"]).map(\.id) == ["a", "c"])
        #expect(HiddenAppsPlan.visibleApps(apps, hidden: []).map(\.id) == ["a", "b", "c"])
    }

    @Test func hidingDropsTheSavedLevel() {
        let settings = ["a": AppVolumeSetting(percent: 40), "b": mutedSetting()]
        let result = HiddenAppsPlan.hide(
            HiddenApp(bundleID: "a", displayName: "A"), hidden: [], settings: settings)
        #expect(result.hidden == [HiddenApp(bundleID: "a", displayName: "A")])
        #expect(result.settings.keys.sorted() == ["b"])

        let untouched = HiddenAppsPlan.hide(
            HiddenApp(bundleID: "c", displayName: "C"), hidden: result.hidden, settings: result.settings)
        #expect(untouched.settings == result.settings)
        #expect(untouched.hidden.map(\.bundleID) == ["a", "c"])
    }

    @Test func stripListBuilderSkipsHiddenAppsRunningOrSaved() {
        var preferences = Preferences()
        preferences.showInactiveApps = true
        let builder = StripListBuilder(
            apps: [makeApp("a"), makeApp("b", playing: false)],
            settings: ["b": AppVolumeSetting(percent: 50), "saved": AppVolumeSetting(percent: 50)],
            hidden: ["b", "saved"],
            preferences: preferences,
            engineErrors: [:],
            isPopoverVisible: false,
            previousOrder: [])
        #expect(builder.build(installedApp: { _ in nil }).strips.map(\.id) == ["a"])
    }

    // MARK: The store

    @Test func hiddenAppGetsNoStripEngineOrCount() {
        let h = Harness(document: SettingsDocument(hiddenApps: hidden("b")))
        h.processes.emit([makeApp("a", objects: [1]), makeApp("b", objects: [2])])
        h.store.popoverDidAppear()

        #expect(h.store.strips.map(\.id) == ["a"])
        #expect(h.store.playingCount == 1)
        #expect(h.factory.live("a")?.mode == .meterOnly)
        #expect(h.factory.live("b") == nil, "no meter engine for a hidden app")
        #expect(h.factory.events.allSatisfy { !$0.contains(" b ") })
    }

    @Test func savedLevelOfAHiddenAppIsNeverApplied() {
        let h = Harness(
            document: SettingsDocument(apps: ["b": mutedSetting()], hiddenApps: hidden("b")))
        h.processes.emit([makeApp("b", objects: [2])])

        #expect(h.factory.made.isEmpty)
        #expect(h.store.strips.isEmpty)
        #expect(h.store.isAnyAppAttenuated == false)
        #expect(h.processes.pollingCalls.allSatisfy { $0 == .off }, "a hidden app's objects aren't polled")
    }

    @Test func hidingResetsTheSettingAndTearsDownTheEngine() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(40, for: "a")
        let engine = try #require(h.factory.live("a"))

        h.store.hideApp("a", displayName: "Player")

        #expect(engine.isStopped)
        #expect(h.store.engineCount == 0)
        #expect(h.store.strips.isEmpty)
        #expect(h.store.hiddenApps == [HiddenApp(bundleID: "a", displayName: "Player")])
        h.store.flushPendingSave()
        #expect(h.persister.saved.last?.apps["a"] == nil)
        #expect(h.persister.saved.last?.hiddenApps == [HiddenApp(bundleID: "a", displayName: "Player")])
    }

    @Test func hidingWorksWithoutPermission() {
        let h = Harness(permission: .denied)
        h.processes.emit([makeApp("a")])
        h.store.hideApp("a", displayName: "A")
        #expect(h.store.strips.isEmpty)
        #expect(h.store.hiddenApps.map(\.bundleID) == ["a"])
    }

    @Test func showingBringsTheAppBackAtItsNormalVolume() {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(40, for: "a")
        h.store.hideApp("a", displayName: "A")

        h.store.showApp("a")

        #expect(h.store.hiddenApps.isEmpty)
        #expect(h.store.strips.map(\.id) == ["a"])
        #expect(h.store.strips.first?.setting == AppVolumeSetting())
        #expect(h.store.engineCount == 0)
        h.store.flushPendingSave()
        #expect(h.persister.saved.last?.hiddenApps == nil, "an empty list isn't stored")
    }

    @Test func hiddenListPersistsAcrossLaunches() {
        let first = Harness()
        first.processes.emit([makeApp("a"), makeApp("b")])
        first.store.hideApp("b", displayName: "B")
        first.store.flushPendingSave()

        let second = Harness(document: first.persister.document)
        second.processes.emit([makeApp("a"), makeApp("b")])
        #expect(second.store.hiddenApps.map(\.bundleID) == ["b"])
        #expect(second.store.strips.map(\.id) == ["a"])
    }

    @Test func levelSavesKeepTheHiddenListAndUpdateSettings() {
        var document = SettingsDocument(hiddenApps: hidden("b"))
        document.updates.skippedVersion = "0.3.0"
        let h = Harness(document: document)
        h.processes.emit([makeApp("a")])

        h.store.setPercent(80, for: "a")
        h.store.flushPendingSave()

        #expect(h.persister.saved.last?.hiddenApps == hidden("b"))
        #expect(h.persister.saved.last?.updates.skippedVersion == "0.3.0")
        #expect(h.persister.saved.last?.apps["a"]?.percent == 80)
    }

    @Test func resetAllLevelsKeepsAppsHidden() {
        let h = Harness(document: SettingsDocument(hiddenApps: hidden("b")))
        h.processes.emit([makeApp("a"), makeApp("b")])
        h.store.resetAllLevels()
        h.store.flushPendingSave()
        #expect(h.store.strips.map(\.id) == ["a"])
        #expect(h.persister.saved.last?.hiddenApps == hidden("b"))
    }

    @Test func showInactiveAppsDoesNotListAHiddenApp() {
        var document = SettingsDocument(hiddenApps: hidden("paused"))
        document.preferences.showInactiveApps = true
        let h = Harness(document: document)
        h.processes.emit([makeApp("a"), makeApp("paused", playing: false)])
        #expect(h.store.strips.map(\.id) == ["a"])
    }

    @Test func muteAllPlayingSkipsHiddenApps() {
        let h = Harness(document: SettingsDocument(hiddenApps: hidden("b")))
        h.processes.emit([makeApp("a", objects: [1]), makeApp("b", objects: [2])])

        h.store.muteAllPlaying()

        #expect(h.factory.live("a")?.initialGain == 0)
        #expect(h.factory.live("b") == nil)
        h.store.flushPendingSave()
        #expect(h.persister.saved.last?.apps["b"] == nil)
        #expect(h.store.bulkMute == BulkMuteAction(kind: .unmuteAll, isEnabled: true), "every visible app is muted")
    }

    @Test func bulkMuteIgnoresAHiddenAppThatIsPlaying() {
        let h = Harness(document: SettingsDocument(hiddenApps: hidden("b")))
        h.processes.emit([makeApp("b")])
        #expect(h.store.bulkMute == BulkMuteAction(kind: .muteAllPlaying, isEnabled: false))
    }

    @Test func hiddenAppIconComesFromTheRunningAppThenTheInstalledApp() {
        let running = NSImage(size: NSSize(width: 1, height: 1))
        let installed = NSImage(size: NSSize(width: 2, height: 2))
        let h = Harness(
            document: SettingsDocument(hiddenApps: hidden("a", "gone")),
            installedApp: { $0 == "gone" ? InstalledAppInfo(displayName: "Gone", icon: installed) : nil })
        h.processes.emit([
            AudioApp(id: "a", displayName: "A", icon: running, processObjectIDs: [1], isPlaying: true)
        ])
        #expect(h.store.icon(forHiddenApp: "a") === running)
        #expect(h.store.icon(forHiddenApp: "gone") === installed)
        #expect(h.store.icon(forHiddenApp: "unknown") == nil)
    }
}

@Suite(.timeLimit(.minutes(1))) struct HiddenAppsSettingsStoreTests {
    @Test func updateSettingsWritesKeepTheHiddenList() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "HushTests-\(UUID().uuidString)")
        let file = directory.appending(path: "settings.json")
        let store = SettingsStore(fileURL: file)
        _ = store.load()
        let hidden = [HiddenApp(bundleID: "com.example.player", displayName: "Player")]

        store.update { $0.hiddenApps = hidden }
        store.saveUpdateSettings(UpdateSettings(skippedVersion: "0.3.0"))

        let reloaded = SettingsStore(fileURL: file).load()
        #expect(reloaded.hiddenApps == hidden)
        #expect(reloaded.updates.skippedVersion == "0.3.0")
    }
}

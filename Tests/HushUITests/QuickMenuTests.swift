import AppKit
import CoreAudio
import Foundation
import HushAudio
import HushCore
import Testing

@testable import HushUI

private let speakers = OutputDevice(
    id: 1, uid: "built-in", name: "MacBook Pro Speakers", transport: .builtInSpeakers)
private let airPods = OutputDevice(id: 2, uid: "airpods", name: "AirPods Pro", transport: .bluetooth)

@MainActor
@Suite(.timeLimit(.minutes(1))) struct BulkMuteStoreTests {
    @Test func muteAllPlayingMutesOnlyPlayingAppsAndKeepsPercents() throws {
        let h = Harness()
        h.processes.emit([makeApp("a"), makeApp("b", objects: [43]), makeApp("idle", playing: false, objects: [44])])
        h.store.setPercent(60, for: "a")

        h.store.muteAllPlaying()

        let strips = Dictionary(uniqueKeysWithValues: h.store.strips.map { ($0.id, $0.setting) })
        #expect(strips["a"]?.isMuted == true)
        #expect(strips["a"]?.percent == 60)
        #expect(strips["b"]?.isMuted == true)
        #expect(strips["b"]?.percent == 100)
        #expect(try #require(h.factory.live("a")).currentGain == 0)
        #expect(try #require(h.factory.live("b")).initialGain == 0)
        #expect(h.factory.live("idle") == nil)
        h.store.flushPendingSave()
        #expect(h.persister.saved.last?.apps["idle"] == nil, "apps that aren't playing are left alone")
    }

    @Test func muteAllPlayingSavesOnceThroughTheDebouncedSave() {
        let h = Harness()
        h.processes.emit([makeApp("a"), makeApp("b", objects: [43])])
        h.store.muteAllPlaying()
        #expect(h.persister.saved.isEmpty, "debounced, not written straight away")

        h.store.flushPendingSave()
        #expect(h.persister.saved.count == 1)
        #expect(h.persister.saved.last?.apps["a"]?.isMuted == true)
        #expect(h.persister.saved.last?.apps["b"]?.isMuted == true)
    }

    @Test func unmuteAllRestoresGainAndKeepsPercents() throws {
        let h = Harness()
        h.processes.emit([makeApp("a"), makeApp("b", objects: [43])])
        h.store.setPercent(60, for: "a")
        h.store.toggleMute(for: "a")
        h.store.toggleMute(for: "b")
        let engineA = try #require(h.factory.live("a"))
        let engineB = try #require(h.factory.live("b"))
        #expect(engineA.currentGain == 0)

        h.store.unmuteAll()

        #expect(h.store.strips.allSatisfy { !$0.setting.isMuted })
        #expect(h.store.strips.first { $0.id == "a" }?.setting.percent == 60)
        #expect(isApproximatelyEqual(engineA.currentGain, VolumeCurve.gain(percent: 60)))
        // Back to 100% and unmuted: nothing to do, so the engine goes away while the popover is closed.
        #expect(engineB.isStopped)
        h.store.flushPendingSave()
        #expect(h.persister.saved.count == 1)
        #expect(h.persister.saved.last?.apps["a"] == AppVolumeSetting(percent: 60, lastAdjusted: Harness.fixedNow))
        #expect(h.persister.saved.last?.apps["b"] == nil)
    }

    @Test func unmuteAllCoversMutedAppsThatAreNotPlayingOrRunning() {
        let saved = mutedSetting(percent: 40)
        let h = Harness(document: SettingsDocument(apps: ["gone": saved]))
        h.processes.emit([makeApp("idle", playing: false)])
        h.store.toggleMute(for: "idle")

        h.store.unmuteAll()
        h.store.flushPendingSave()

        #expect(h.persister.saved.last?.apps["gone"] == AppVolumeSetting(percent: 40, lastAdjusted: Harness.fixedNow))
        #expect(h.persister.saved.last?.apps["idle"] == nil)
    }

    @Test func muteAllPlayingLeavesAnAlreadyMutedAppUntouched() {
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let saved = AppVolumeSetting(percent: 30, isMuted: true, lastAdjusted: earlier)
        let h = Harness(document: SettingsDocument(apps: ["a": saved]))
        h.processes.emit([makeApp("a"), makeApp("b", objects: [43])])

        h.store.muteAllPlaying()
        h.store.flushPendingSave()

        #expect(h.persister.saved.last?.apps["a"] == saved, "percent, mute and lastAdjusted unchanged")
        #expect(h.persister.saved.last?.apps["b"]?.isMuted == true)
    }

    @Test func unmuteAllDoesNothingWithoutPermission() {
        let saved = mutedSetting(percent: 40)
        let h = Harness(document: SettingsDocument(apps: ["a": saved]), permission: .denied)
        h.processes.emit([makeApp("a")])

        h.store.unmuteAll()
        h.store.flushPendingSave()

        #expect(h.store.strips.first?.setting == saved)
        #expect(h.persister.saved.isEmpty, "nothing changed, nothing written")
    }

    @Test func bulkActionsDoNothingWithoutPermission() {
        let h = Harness(permission: .denied)
        h.processes.emit([makeApp("a")])
        h.store.muteAllPlaying()
        #expect(h.store.strips.first?.setting.isMuted == false)
        #expect(h.factory.made.isEmpty)
    }

    @Test func bulkMuteOffersMuteUntilEveryPlayingAppIsMuted() {
        let h = Harness()
        #expect(h.store.bulkMute == BulkMuteAction(kind: .muteAllPlaying, isEnabled: false), "nothing playing")

        h.processes.emit([makeApp("a"), makeApp("b", objects: [43])])
        #expect(h.store.bulkMute == BulkMuteAction(kind: .muteAllPlaying, isEnabled: true))

        h.store.toggleMute(for: "a")
        #expect(h.store.bulkMute == BulkMuteAction(kind: .muteAllPlaying, isEnabled: true), "b still plays")

        h.store.toggleMute(for: "b")
        #expect(h.store.bulkMute == BulkMuteAction(kind: .unmuteAll, isEnabled: true))

        h.processes.emit([])
        #expect(
            h.store.bulkMute == BulkMuteAction(kind: .unmuteAll, isEnabled: true),
            "nothing plays but saved apps are muted")

        h.store.unmuteAll()
        #expect(h.store.bulkMute == BulkMuteAction(kind: .muteAllPlaying, isEnabled: false))
    }

    @Test func bulkMuteIsDisabledWithoutPermission() {
        let saved = mutedSetting()
        let denied = Harness(document: SettingsDocument(apps: ["a": saved]), permission: .denied)
        denied.processes.emit([makeApp("a")])
        #expect(denied.store.bulkMute == BulkMuteAction(kind: .unmuteAll, isEnabled: false))

        let deniedPlaying = Harness(permission: .denied)
        deniedPlaying.processes.emit([makeApp("a")])
        #expect(deniedPlaying.store.bulkMute == BulkMuteAction(kind: .muteAllPlaying, isEnabled: false))
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1))) struct QuickMenuTests {
    /// Records which action each item ran.
    final class Recorder {
        var calls: [String] = []

        var actions: QuickMenuActions {
            QuickMenuActions(
                selectOutput: { self.calls.append("output \($0.name)") },
                openSoundSettings: { self.calls.append("sound settings") },
                muteAllPlaying: { self.calls.append("mute all") },
                unmuteAll: { self.calls.append("unmute all") },
                openSettings: { self.calls.append("settings") },
                checkForUpdates: { self.calls.append("check") },
                quit: { self.calls.append("quit") })
        }
    }

    private func model(
        outputs: [QuickMenuModel.Output] = [],
        bulkMute: BulkMuteAction = BulkMuteAction(kind: .muteAllPlaying, isEnabled: true),
        canCheckForUpdates: Bool = true
    ) -> QuickMenuModel {
        QuickMenuModel(outputs: outputs, bulkMute: bulkMute, canCheckForUpdates: canCheckForUpdates)
    }

    @Test func itemsComeInOrderWithStandardTitlesAndShortcuts() {
        let items = QuickMenu.items(for: model(), actions: Recorder().actions)
        #expect(
            items.map(\.title) == [
                "Output", "Mute All Playing Apps", "", "Settings…", "Check for Updates…", "", "Quit Hush",
            ])
        #expect(items[2].isSeparatorItem)
        #expect(items[5].isSeparatorItem)
        #expect(items[3].keyEquivalent == ",")
        #expect(items[3].keyEquivalentModifierMask == .command)
        #expect(items[6].keyEquivalent == "q")
        #expect(items[6].keyEquivalentModifierMask == .command)
    }

    private func item(_ title: String, in items: [NSMenuItem]) throws -> NSMenuItem {
        try #require(items.first { $0.title == title }, "no \(title) item")
    }

    @Test func eachItemRunsItsAction() throws {
        let recorder = Recorder()
        let items = QuickMenu.items(for: model(), actions: recorder.actions)
        for title in ["Mute All Playing Apps", "Settings…", "Check for Updates…", "Quit Hush"] {
            ActionMenuItem.perform(try item(title, in: items))
        }
        #expect(recorder.calls == ["mute all", "settings", "check", "quit"])
    }

    @Test func outputSubmenuChecksTheCurrentDeviceAndEndsWithSoundSettings() throws {
        let recorder = Recorder()
        let outputs = [
            QuickMenuModel.Output(device: airPods, isCurrent: false),
            QuickMenuModel.Output(device: speakers, isCurrent: true),
        ]
        let items = QuickMenu.items(for: model(outputs: outputs), actions: recorder.actions)
        let submenu = try #require(items[0].submenu)

        #expect(submenu.items.map(\.title) == ["AirPods Pro", "MacBook Pro Speakers", "", "Sound Settings…"])
        #expect(submenu.items.map(\.state) == [.off, .on, .off, .off])
        #expect(submenu.items[0].image != nil)

        ActionMenuItem.perform(submenu.items[0])
        ActionMenuItem.perform(submenu.items[3])
        #expect(recorder.calls == ["output AirPods Pro", "sound settings"])
    }

    @Test func outputSubmenuWithNoDevicesStillOffersSoundSettings() throws {
        let items = QuickMenu.items(for: model(), actions: Recorder().actions)
        #expect(try #require(items[0].submenu).items.map(\.title) == ["Sound Settings…"])
    }

    @Test func bulkItemSwitchesToUnmuteAll() {
        let recorder = Recorder()
        let items = QuickMenu.items(
            for: model(bulkMute: BulkMuteAction(kind: .unmuteAll, isEnabled: true)), actions: recorder.actions)
        #expect(items[1].title == "Unmute All")
        #expect(items[1].isEnabled)
        ActionMenuItem.perform(items[1])
        #expect(recorder.calls == ["unmute all"])
    }

    @Test func disabledStatesFollowTheModel() throws {
        let menu = NSMenu()
        QuickMenu.populate(
            menu,
            model: model(bulkMute: BulkMuteAction(kind: .muteAllPlaying, isEnabled: false), canCheckForUpdates: false),
            actions: Recorder().actions)
        #expect(!menu.autoenablesItems)
        #expect(try !item("Mute All Playing Apps", in: menu.items).isEnabled)
        #expect(try !item("Check for Updates…", in: menu.items).isEnabled)
        #expect(try item("Settings…", in: menu.items).isEnabled)
        #expect(try item("Quit Hush", in: menu.items).isEnabled)
    }

    @Test func modelReadsTheStoreAndUpdateChecker() {
        let h = Harness()
        h.output.emitDevices([airPods, speakers])
        h.processes.emit([makeApp("a")])
        let updates = UpdateHarness().checker!

        let model = QuickMenuModel(store: h.store, updates: updates)

        #expect(model.outputs.map(\.device.id) == [2, 1])
        #expect(model.outputs.map(\.isCurrent) == [false, true])
        #expect(model.bulkMute == BulkMuteAction(kind: .muteAllPlaying, isEnabled: true))
        #expect(model.canCheckForUpdates)
    }

    @Test func modelKeepsTheCurrentDeviceWhenTheListLacksIt() {
        let h = Harness()
        h.output.emitDevices([airPods])
        let model = QuickMenuModel(store: h.store, updates: UpdateHarness().checker)
        #expect(model.outputs.map(\.device.id) == [2, 1])
        #expect(model.outputs.map(\.isCurrent) == [false, true])
    }

    @Test func checkForUpdatesIsDisabledWhileChecking() async throws {
        let fetcher = GatedReleaseFetcher(release: makeRelease("0.1.0"))
        let updates = UpdateHarness(fetcher: fetcher)
        let check = Task { await updates.checker.checkNow() }
        var spins = 0
        while await fetcher.started == 0 {
            spins += 1
            try #require(spins < 10_000, "the fetch never started")
            await Task.yield()
        }
        #expect(!QuickMenuModel(store: Harness().store, updates: updates.checker).canCheckForUpdates)
        await fetcher.open()
        await check.value
        #expect(QuickMenuModel(store: Harness().store, updates: updates.checker).canCheckForUpdates)
    }
}

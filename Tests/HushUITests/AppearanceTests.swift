import AppKit
import HushAudio
import HushCore
import Observation
import SwiftUI
import Testing
@testable import HushUI

@MainActor
@Suite(.timeLimit(.minutes(1))) struct MeterToggleTests {
    private func harness(meters: Bool) -> Harness {
        Harness(document: SettingsDocument(
            preferences: Preferences(appearance: AppearancePreferences(showLevelMeters: meters))))
    }

    @Test func metersOffCreatesNoMeterOnlyEnginesWhenThePopoverOpens() {
        let h = harness(meters: false)
        h.processes.emit([makeApp("a"), makeApp("b")])
        h.store.popoverDidAppear()
        #expect(h.factory.made.isEmpty)
        #expect(!h.factory.events.contains { $0.hasSuffix("meterOnly") })
    }

    @Test func metersOffStillControlsAdjustedApps() {
        let h = harness(meters: false)
        h.processes.emit([makeApp("a"), makeApp("b")])
        h.store.setPercent(50, for: "b")
        h.store.popoverDidAppear()
        #expect(h.factory.live("a") == nil)
        #expect(h.factory.live("b")?.mode == .control)
    }

    @Test func turningMetersOffWhileOpenTearsDownMeterOnlyEngines() throws {
        let h = harness(meters: true)
        h.processes.emit([makeApp("a")])
        h.store.popoverDidAppear()
        let meter = try #require(h.factory.live("a"))
        #expect(meter.mode == .meterOnly)

        h.store.showLevelMeters = false
        #expect(meter.isStopped)
        #expect(h.store.engineCount == 0)

        h.store.showLevelMeters = true
        #expect(h.factory.live("a")?.mode == .meterOnly)
    }

    @Test func meterToggleIsSaved() {
        let h = harness(meters: true)
        h.store.showLevelMeters = false
        h.store.flushPendingSave()
        #expect(h.persister.document.preferences.appearance.showLevelMeters == false)
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1))) struct SortModeTests {
    @Test func alphabeticalSortsIgnoringPlayback() {
        let h = Harness()
        h.processes.emit([
            makeApp("zoom", playing: true), makeApp("arc", playing: false), makeApp("music", playing: true),
        ])
        h.store.showInactiveApps = true
        #expect(h.store.strips.map(\.id) == ["music", "zoom", "arc"])

        h.store.sortMode = .alphabetical
        #expect(h.store.strips.map(\.id) == ["arc", "music", "zoom"])
    }

    @Test func switchingSortModeWhileOpenReordersImmediately() {
        let h = Harness()
        h.processes.emit([makeApp("b"), makeApp("a")])
        h.store.setPercent(50, for: "b")
        h.store.popoverDidAppear()
        #expect(h.store.strips.map(\.id) == ["b", "a"])

        h.store.sortMode = .alphabetical
        #expect(h.store.strips.map(\.id) == ["a", "b"])
        h.store.sortMode = .activity
        #expect(h.store.strips.map(\.id) == ["b", "a"])
    }

    @Test func alphabeticalPlacesNewcomersInOrderWhileOpen() {
        let h = Harness(document: SettingsDocument(
            preferences: Preferences(appearance: AppearancePreferences(sortMode: .alphabetical))))
        h.processes.emit([makeApp("c")])
        h.store.popoverDidAppear()
        h.processes.emit([makeApp("c"), makeApp("a")])
        #expect(h.store.strips.map(\.id) == ["a", "c"])
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1))) struct StripMeterTests {
    @Test func publishesOnlyWhenTheDisplayedHeightChanges() {
        let meter = StripMeter()
        #expect(meter.update(level: 0.5))
        let shown = meter.fraction
        // 0.05 dB louder: well under one 0.6 dB step.
        #expect(!meter.update(level: 0.5 * 1.006))
        #expect(meter.fraction == shown)
        // 2 dB louder: several steps.
        #expect(meter.update(level: 0.5 * 1.26))
        #expect(meter.fraction > shown)
    }

    @Test func observersAreNotifiedOnlyOnChange() {
        let meter = StripMeter()
        meter.update(level: 0.5)
        let notifications = Counter()
        withObservationTracking { _ = meter.fraction } onChange: { notifications.increment() }
        meter.update(level: 0.5 * 1.001)
        #expect(notifications.value == 0)
        meter.update(level: 0.1)
        #expect(notifications.value == 1)
    }

    @Test func meterTicksDoNotInvalidateStoreState() {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.popoverDidAppear()
        let meter = h.store.meter(for: "a")
        h.factory.live("a")?.peak = 0.5

        let storeChanges = Counter()
        withObservationTracking {
            _ = h.store.strips
            _ = h.store.preferences
        } onChange: { storeChanges.increment() }
        h.store.tickMeters(elapsed: 1.0 / 30.0)

        #expect(storeChanges.value == 0, "a tick must not re-render strips, rows or the popover")
        // The tick really ran and published through the meter, not through the store.
        #expect(meter.fraction > 0)
        #expect(h.store.meterBank.isSilent == false)
    }

    @Test func steadyLevelPublishesOnce() {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.popoverDidAppear()
        let meter = h.store.meter(for: "a")
        h.factory.live("a")?.peak = 0.5

        let notifications = Counter()
        withObservationTracking { _ = meter.fraction } onChange: { notifications.increment() }
        h.store.tickMeters(elapsed: 1.0 / 30.0)
        #expect(notifications.value == 1)
        // Same peak every tick: the ballistics hold at the peak, so nothing more is published.
        withObservationTracking { _ = meter.fraction } onChange: { notifications.increment() }
        for _ in 0..<10 { h.store.tickMeters(elapsed: 1.0 / 30.0) }
        #expect(notifications.value == 1)
    }

    @Test func meterFallsToZeroWhenItsEngineGoes() {
        let h = Harness()
        h.store.showInactiveApps = true  // keep the strip once it stops playing
        h.processes.emit([makeApp("a")])
        h.store.popoverDidAppear()
        let meter = h.store.meter(for: "a")
        h.factory.live("a")?.peak = 0.5
        h.store.tickMeters(elapsed: 1.0 / 30.0)
        #expect(meter.fraction > 0)

        h.processes.emit([makeApp("a", playing: false)])
        h.store.tickMeters(elapsed: 1.0 / 30.0)
        #expect(meter.fraction == 0)
    }

    @Test func closingThePopoverZeroesMeters() {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.popoverDidAppear()
        let meter = h.store.meter(for: "a")
        h.factory.live("a")?.peak = 0.5
        h.store.tickMeters(elapsed: 1.0 / 30.0)
        h.store.popoverDidDisappear()
        #expect(meter.fraction == 0)
    }

    @Test func onlyTheListLayoutsNeedOptionToScrollTheVolume() {
        #expect(!MixerAppearance(layout: .channelStrips).scrollNeedsOption)
        #expect(MixerAppearance(layout: .classicRows).scrollNeedsOption)
        #expect(MixerAppearance(layout: .tiles).scrollNeedsOption)
    }

    @Test func boostIsAmberWhateverTheAccent() {
        // `boost` takes no accent: the system accent only reaches normal fills.
        #expect(Palette.boost(.light, .standard) == Palette.amber(.light, .standard))
    }

    @Test func stripActionsCompareByTargetAndApp() {
        let h = Harness()
        let other = Harness()
        #expect(StripActions(target: h.store, id: "a") == StripActions(target: h.store, id: "a"))
        #expect(StripActions(target: h.store, id: "a") != StripActions(target: h.store, id: "b"))
        #expect(StripActions(target: h.store, id: "a") != StripActions(target: other.store, id: "a"))
    }
}

/// Renders every layout offscreen with real strips, so a broken layout fails here rather than
/// in the menu bar.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct LayoutSmokeTests {
    @Test(arguments: MixerLayout.allCases, MixerDensity.allCases)
    func everyLayoutRenders(layout: MixerLayout, density: MixerDensity) throws {
        for meters in [true, false] {
            let h = Harness(document: SettingsDocument(apps: [
                "boosted": AppVolumeSetting(percent: 170, lastAdjusted: Harness.fixedNow),
                "muted": mutedSetting(),
            ]))
            let ids = ["boosted", "muted"] + (2..<8).map { "app\($0)" }
            h.processes.emit(ids.enumerated().map { index, id in makeApp(id, objects: [UInt32(index + 1)]) })
            h.store.layout = layout
            h.store.density = density
            h.store.showLevelMeters = meters
            h.store.popoverDidAppear()
            h.store.tickMeters(elapsed: 1.0 / 30.0)

            let host = NSHostingView(rootView: MixerPopover(store: h.store, updates: UpdateHarness().checker))
            host.frame = CGRect(x: 0, y: 0, width: 340, height: 600)
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            #expect(host.fittingSize.height > 100)
            h.store.popoverDidDisappear()
        }
    }

    @Test(arguments: MixerLayout.allCases)
    func appearancePreviewRenders(layout: MixerLayout) {
        let host = NSHostingView(rootView: AppearancePreview(
            appearance: MixerAppearance(layout: layout), maxPercent: 200))
        host.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height > 50)
    }

    @Test func faderGlyphIsATemplateWithAnAttenuatedVariant() {
        let full = MenuBarIcon.image(style: .fader, attenuated: false, badged: false)
        let lowered = MenuBarIcon.image(style: .fader, attenuated: true, badged: false)
        #expect(full.isTemplate && lowered.isTemplate)
        #expect(full !== lowered)
        #expect(MenuBarIcon.image(style: .fader, attenuated: false, badged: true).size == full.size)
        #expect(zip(MenuBarIcon.faderLevels(attenuated: true), MenuBarIcon.faderLevels(attenuated: false)).allSatisfy { $0 < $1 })
    }
}

nonisolated final class Counter: @unchecked Sendable {
    private(set) var value = 0
    func increment() { value += 1 }
}

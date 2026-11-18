import Foundation
import Testing

@testable import HushCore

@Suite struct PresetTests {
    private let earlier = Date(timeIntervalSince1970: 1_700_000_000)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func level(_ percent: Int, muted: Bool = false, name: String = "App") -> Preset.Level {
        Preset.Level(displayName: name, percent: percent, isMuted: muted)
    }

    // MARK: Snapshot

    @Test func levelsKeepOnlyAdjustedAppsWithTheirNames() {
        let settings: [String: AppVolumeSetting] = [
            "quiet": AppVolumeSetting(percent: 40, lastAdjusted: earlier),
            "muted": AppVolumeSetting(percent: 100, isMuted: true, lastAdjusted: earlier),
            "default": AppVolumeSetting(percent: 100, lastAdjusted: earlier),
        ]
        let levels = Preset.levels(from: settings) { $0.uppercased() }
        #expect(
            levels == [
                "quiet": Preset.Level(displayName: "QUIET", percent: 40),
                "muted": Preset.Level(displayName: "MUTED", percent: 100, isMuted: true),
            ])
    }

    @Test func levelPercentIsClampedToTheAbsoluteRange() {
        #expect(level(500).percent == 200)
        #expect(level(-5).percent == 0)
    }

    // MARK: Apply

    @Test func applyingReproducesTheSnapshotExactly() {
        let preset = Preset(name: "Call", apps: ["chat": level(150), "music": level(30, muted: true)])
        let settings: [String: AppVolumeSetting] = [
            "music": AppVolumeSetting(percent: 80, lastAdjusted: earlier),
            "game": AppVolumeSetting(percent: 20, isMuted: true, lastAdjusted: earlier),
        ]

        let applied = preset.applied(to: settings, maxPercent: 200, now: now)

        #expect(
            applied == [
                "chat": AppVolumeSetting(percent: 150, lastAdjusted: now),
                "music": AppVolumeSetting(percent: 30, isMuted: true, lastAdjusted: now),
            ], "game isn't in the preset, so it goes back to 100% and unmuted (no entry)")
    }

    @Test func applyingKeepsLastAdjustedForAppsThatDontChange() {
        let preset = Preset(name: "Focus", apps: ["music": level(30)])
        let settings = ["music": AppVolumeSetting(percent: 30, lastAdjusted: earlier)]
        #expect(preset.applied(to: settings, maxPercent: 200, now: now) == settings)
    }

    @Test func applyingClampsToTheCurrentMaximumBoost() {
        let preset = Preset(name: "Loud", apps: ["a": level(200)])
        #expect(preset.applied(to: [:], maxPercent: 125, now: now)["a"]?.percent == 125)
    }

    @Test func applyingAnEmptyPresetResetsEverything() {
        let preset = Preset(name: "Normal", apps: [:])
        let settings = ["a": AppVolumeSetting(percent: 20, lastAdjusted: earlier)]
        #expect(preset.applied(to: settings, maxPercent: 200, now: now).isEmpty)
    }

    // MARK: Matching

    @Test func matchesOnlyTheExactLevels() {
        let preset = Preset(name: "Call", apps: ["chat": level(150), "music": level(30, muted: true)])
        let exact: [String: AppVolumeSetting] = [
            "chat": AppVolumeSetting(percent: 150, lastAdjusted: earlier),
            "music": AppVolumeSetting(percent: 30, isMuted: true, lastAdjusted: now),
        ]
        #expect(preset.matches(exact, maxPercent: 200), "lastAdjusted doesn't matter")

        var extra = exact
        extra["game"] = AppVolumeSetting(percent: 90, lastAdjusted: now)
        #expect(!preset.matches(extra, maxPercent: 200), "another adjusted app")

        var unmuted = exact
        unmuted["music"]?.isMuted = false
        #expect(!preset.matches(unmuted, maxPercent: 200))

        var missing = exact
        missing["chat"] = nil
        #expect(!preset.matches(missing, maxPercent: 200))
    }

    @Test func matchingIgnoresDefaultEntriesAndUsesTheClampedLevel() {
        let preset = Preset(name: "Loud", apps: ["a": level(200)])
        let settings: [String: AppVolumeSetting] = [
            "a": AppVolumeSetting(percent: 125, lastAdjusted: now),
            "b": AppVolumeSetting(percent: 100, lastAdjusted: now),
        ]
        #expect(preset.matches(settings, maxPercent: 125))
        #expect(!preset.matches(settings, maxPercent: 200))
    }

    @Test func anEmptyPresetMatchesWhenNothingIsAdjusted() {
        let preset = Preset(name: "Normal", apps: [:])
        #expect(preset.matches([:], maxPercent: 200))
        #expect(!preset.matches(["a": AppVolumeSetting(percent: 50)], maxPercent: 200))
    }

    @Test func roundTripsThroughJSON() throws {
        let preset = Preset(name: "Call", apps: ["chat": level(150, muted: true, name: "Chat")])
        let decoded = try JSONDecoder().decode(Preset.self, from: JSONEncoder().encode(preset))
        #expect(decoded == preset)
    }
}

@Suite struct PresetLibraryTests {
    private func preset(_ name: String, apps: [String: Preset.Level] = [:]) -> Preset {
        Preset(name: name, apps: apps)
    }

    private let quiet = ["a": Preset.Level(displayName: "A", percent: 40)]

    // MARK: Names

    @Test func blankNamesAreEmpty() {
        let library = PresetLibrary()
        #expect(library.check(name: "") == .empty)
        #expect(library.check(name: "  \n\t ") == .empty)
    }

    @Test func namesAreTrimmed() {
        #expect(PresetLibrary().check(name: "  Call  ") == .available("Call"))
    }

    @Test func namesAreUniqueIgnoringCase() {
        let call = preset("Call")
        let library = PresetLibrary(presets: [call])
        #expect(library.check(name: "call") == .taken(call))
        #expect(library.check(name: " CALL ") == .taken(call))
        #expect(library.check(name: "Calls") == .available("Calls"))
    }

    @Test func renamingIgnoresThePresetsOwnName() {
        let call = preset("Call")
        let focus = preset("Focus")
        let library = PresetLibrary(presets: [call, focus])
        #expect(library.check(name: "CALL", renaming: call.id) == .available("CALL"))
        #expect(library.check(name: "focus", renaming: call.id) == .taken(focus))
    }

    @Test func aFullLibraryRefusesNewNamesButAllowsReplacingAndRenaming() {
        let presets = (1...PresetLibrary.maxCount).map { preset("P\($0)") }
        let library = PresetLibrary(presets: presets)
        #expect(library.isFull)
        #expect(library.check(name: "New") == .limitReached)
        #expect(library.check(name: "p3") == .taken(presets[2]))
        #expect(library.check(name: "New", renaming: presets[0].id) == .available("New"))
    }

    // MARK: Save

    @Test func savingAddsAtTheEnd() {
        var library = PresetLibrary(presets: [preset("Call")])
        let id = UUID()
        let saved = library.save(name: " Focus ", apps: quiet, id: id)
        #expect(saved == Preset(id: id, name: "Focus", apps: quiet))
        #expect(library.presets.map(\.name) == ["Call", "Focus"])
    }

    @Test func savingAnExistingNameReplacesItInPlace() {
        let call = preset("Call")
        var library = PresetLibrary(presets: [call, preset("Focus")])
        let saved = library.save(name: "CALL", apps: quiet)
        #expect(saved?.id == call.id, "keeps its identity")
        #expect(library.presets.map(\.name) == ["CALL", "Focus"], "keeps its place, takes the new spelling")
        #expect(library.presets[0].apps == quiet)
    }

    @Test func savingRefusesBlankNamesAndAFullLibrary() {
        var library = PresetLibrary()
        let blank = library.save(name: "   ", apps: quiet)
        #expect(blank == nil)
        #expect(library.isEmpty)

        var full = PresetLibrary(presets: (1...PresetLibrary.maxCount).map { preset("P\($0)") })
        let new = full.save(name: "New", apps: quiet)
        #expect(new == nil)
        #expect(full.presets.count == PresetLibrary.maxCount)
        let replaced = full.save(name: "P1", apps: quiet)
        #expect(replaced != nil, "replacing still works when full")
    }

    @Test func savingDropsDefaultLevels() {
        var library = PresetLibrary()
        let saved = library.save(name: "X", apps: ["a": Preset.Level(displayName: "A", percent: 100)])
        #expect(saved?.apps.isEmpty == true)
    }

    // MARK: Rename and delete

    @Test func renaming() {
        let call = preset("Call")
        var library = PresetLibrary(presets: [call, preset("Focus")])
        let renamed = library.rename(call.id, to: "  Meeting ")
        #expect(renamed)
        #expect(library.presets.map(\.name) == ["Meeting", "Focus"])
        let taken = library.rename(call.id, to: "focus")
        #expect(!taken, "another preset has that name")
        let blank = library.rename(call.id, to: " ")
        #expect(!blank)
        let missing = library.rename(UUID(), to: "Other")
        #expect(!missing)
        #expect(library.presets.map(\.name) == ["Meeting", "Focus"])
    }

    @Test func deleting() {
        let call = preset("Call")
        var library = PresetLibrary(presets: [call, preset("Focus")])
        library.delete(call.id)
        #expect(library.presets.map(\.name) == ["Focus"])
        #expect(library.preset(call.id) == nil)
    }

    // MARK: Active preset

    @Test func activePresetIsTheFirstExactMatch() {
        let call = preset("Call", apps: quiet)
        let same = preset("Same", apps: quiet)
        let normal = preset("Normal")
        let library = PresetLibrary(presets: [normal, call, same])
        let settings = ["a": AppVolumeSetting(percent: 40)]
        #expect(library.activePreset(for: settings, maxPercent: 200) == call)
        #expect(library.activePreset(for: [:], maxPercent: 200) == normal)
        #expect(library.activePreset(for: ["a": AppVolumeSetting(percent: 41)], maxPercent: 200) == nil)
    }

    // MARK: Loading

    @Test func loadingDropsWhatTheRulesDontAllow() {
        let first = Preset(name: " Call ", apps: ["a": Preset.Level(displayName: "A", percent: 100)])
        let repeated = Preset(id: first.id, name: "Other", apps: [:])
        let presets = [first, preset("CALL"), preset("  "), repeated] + (1...25).map { preset("P\($0)") }

        let library = PresetLibrary(presets: presets)

        #expect(library.presets.count == PresetLibrary.maxCount)
        #expect(library.presets[0].name == "Call")
        #expect(library.presets[0].apps.isEmpty, "default levels dropped")
        #expect(library.presets.map(\.name).prefix(3) == ["Call", "P1", "P2"])
        #expect(library.presets.last?.name == "P19")
    }
}

import Foundation
import Testing
@testable import HushCore

@Suite struct AppearancePreferencesTests {
    @Test func defaultsMatchTheOriginalLook() {
        let appearance = AppearancePreferences()
        #expect(appearance.layout == .channelStrips)
        #expect(appearance.showLevelMeters)
        #expect(appearance.density == .comfortable)
        #expect(appearance.showPercentages)
        #expect(appearance.sortMode == .activity)
        #expect(appearance.accent == .amber)
        #expect(appearance.menuBarIcon == .speaker)
    }

    /// A settings.json written before Appearance existed still loads, with every option at its default.
    @Test func fileWithoutAppearanceDecodesWithDefaults() throws {
        let json = """
            {
              "version": 1,
              "preferences": { "maxBoostPercent": 150, "showInactiveApps": true },
              "apps": {}
            }
            """
        let document = try SettingsDocument.decode(from: Data(json.utf8))
        #expect(document.preferences.maxBoostPercent == .percent150)
        #expect(document.preferences.showInactiveApps)
        #expect(document.preferences.appearance == AppearancePreferences())
    }

    @Test func missingKeysTakeTheirDefaults() throws {
        let json = """
            {
              "version": 1,
              "preferences": { "appearance": { "layout": "tiles", "showLevelMeters": false } },
              "apps": {}
            }
            """
        let appearance = try SettingsDocument.decode(from: Data(json.utf8)).preferences.appearance
        #expect(appearance.layout == .tiles)
        #expect(!appearance.showLevelMeters)
        #expect(appearance.density == .comfortable)
        #expect(appearance.showPercentages)
        #expect(appearance.sortMode == .activity)
    }

    /// A value from a newer Hush (or a typo) falls back to the default instead of failing the
    /// whole file, which would move it aside and lose every saved level.
    @Test func unknownValuesFallBackWithoutLosingTheFile() throws {
        let json = """
            {
              "version": 1,
              "preferences": {
                "maxBoostPercent": 200,
                "appearance": { "layout": "hexagons", "density": 3, "accent": "system" }
              },
              "apps": { "com.example.player": { "percent": 62, "isMuted": false, "lastAdjusted": "2026-11-17T14:03:00Z" } }
            }
            """
        let document = try SettingsDocument.decode(from: Data(json.utf8))
        #expect(document.preferences.appearance.layout == .channelStrips)
        #expect(document.preferences.appearance.density == .comfortable)
        #expect(document.preferences.appearance.accent == .system)
        #expect(document.apps["com.example.player"]?.percent == 62)
    }

    @Test func malformedAppearanceSectionFallsBackToDefaults() throws {
        let json = """
            { "version": 1, "preferences": { "maxBoostPercent": 100, "appearance": "tiles" }, "apps": {} }
            """
        let document = try SettingsDocument.decode(from: Data(json.utf8))
        #expect(document.preferences.maxBoostPercent == .percent100)
        #expect(document.preferences.appearance == AppearancePreferences())
    }

    @Test func roundTripsEveryOption() throws {
        let appearance = AppearancePreferences(
            layout: .classicRows, showLevelMeters: false, density: .compact, showPercentages: false,
            sortMode: .alphabetical, accent: .system, menuBarIcon: .fader)
        let document = SettingsDocument(preferences: Preferences(appearance: appearance))
        let data = try document.encoded()
        #expect(try SettingsDocument.decode(from: data).preferences.appearance == appearance)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"layout\" : \"rows\""))
        #expect(text.contains("\"menuBarIcon\" : \"fader\""))
    }
}

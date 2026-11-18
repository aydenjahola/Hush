import Foundation
import Testing
@testable import HushCore

@Suite struct SettingsDocumentTests {
    private let date = Date(timeIntervalSince1970: 1_794_924_180)

    @Test func roundTrips() throws {
        let document = SettingsDocument(
            preferences: Preferences(maxBoostPercent: .percent150, showInactiveApps: true),
            apps: [
                "com.example.player": AppVolumeSetting(percent: 62, lastAdjusted: date),
                "com.example.chat": AppVolumeSetting(percent: 100, isMuted: true, lastAdjusted: date),
            ])
        let decoded = try SettingsDocument.decode(from: document.encoded())
        #expect(decoded == document)
    }

    @Test func decodesSpecExample() throws {
        let json = """
            {
              "version": 1,
              "preferences": { "maxBoostPercent": 200, "showInactiveApps": false },
              "apps": {
                "com.example.player": { "percent": 62, "isMuted": false, "lastAdjusted": "2026-11-17T14:03:00Z" },
                "com.example.chat":   { "percent": 150, "isMuted": false, "lastAdjusted": "2026-11-17T13:40:12Z" }
              }
            }
            """
        let document = try SettingsDocument.decode(from: Data(json.utf8))
        #expect(document.preferences == Preferences())
        #expect(document.apps["com.example.player"]?.percent == 62)
        #expect(document.apps["com.example.chat"]?.percent == 150)
        let expectedDate = try #require(ISO8601DateFormatter().date(from: "2026-11-17T14:03:00Z"))
        #expect(document.apps["com.example.player"]?.lastAdjusted == expectedDate)
    }

    @Test func encodingDropsDefaultEntries() throws {
        let document = SettingsDocument(apps: [
            "com.example.default": AppVolumeSetting(percent: 100, lastAdjusted: date),
            "com.example.quiet": AppVolumeSetting(percent: 80, lastAdjusted: date),
        ])
        let data = try document.encoded()
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("com.example.default"))
        #expect(try SettingsDocument.decode(from: data).apps.keys.sorted() == ["com.example.quiet"])
    }

    @Test func encodesDatesAsISO8601() throws {
        let document = SettingsDocument(apps: ["x": AppVolumeSetting(percent: 50, lastAdjusted: date)])
        let text = String(decoding: try document.encoded(), as: UTF8.self)
        #expect(text.contains("\"lastAdjusted\" : \"2026-11-"))
        #expect(text.contains("Z\""))
    }

    @Test func normalizingClampsToMaxBoost() {
        let document = SettingsDocument(
            preferences: Preferences(maxBoostPercent: .percent150),
            apps: ["x": AppVolumeSetting(percent: 200, lastAdjusted: date)])
        #expect(document.normalized().apps["x"]?.percent == 150)
    }

    @Test func rejectsGarbage() {
        #expect(throws: (any Error).self) {
            try SettingsDocument.decode(from: Data("not json".utf8))
        }
    }

    @Test func rejectsUnknownVersion() {
        let json = #"{"version": 2, "preferences": {}, "apps": {}}"#
        #expect(throws: SettingsDocument.DecodingFailure.unsupportedVersion(2)) {
            try SettingsDocument.decode(from: Data(json.utf8))
        }
    }

    // MARK: Update settings (additive, optional fields in version 1)

    @Test func versionOneFileWithoutUpdateFieldsLoadsWithDefaults() throws {
        let json = """
            {
              "version": 1,
              "preferences": { "maxBoostPercent": 150, "showInactiveApps": true },
              "apps": {}
            }
            """
        let document = try SettingsDocument.decode(from: Data(json.utf8))
        #expect(document.version == 1)
        #expect(document.preferences == Preferences(maxBoostPercent: .percent150, showInactiveApps: true))
        #expect(document.updates == UpdateSettings())
        #expect(document.updates.automaticUpdateChecks)
        #expect(document.updates.skippedVersion == nil)
        #expect(document.updates.snoozedUntil == nil)
        #expect(document.updates.lastUpdateCheck == nil)
    }

    @Test func partialUpdateFieldsKeepDefaultsForTheRest() throws {
        let json = #"{"version": 1, "preferences": {}, "apps": {}, "updates": {"skippedVersion": "0.3.0"}}"#
        let document = try SettingsDocument.decode(from: Data(json.utf8))
        #expect(document.updates.skippedVersion == "0.3.0")
        #expect(document.updates.automaticUpdateChecks)
    }

    @Test func updateSettingsRoundTrip() throws {
        var document = SettingsDocument()
        document.updates = UpdateSettings(
            automaticUpdateChecks: false,
            skippedVersion: "0.2.0",
            snoozedUntil: date,
            lastUpdateCheck: date.addingTimeInterval(-60),
            notifiedVersion: "0.2.0")
        let data = try document.encoded()
        #expect(String(decoding: data, as: UTF8.self).contains("\"automaticUpdateChecks\" : false"))
        #expect(try SettingsDocument.decode(from: data) == document)
        #expect(try SettingsDocument.decode(from: data).version == 1)
    }

    // MARK: Presets (additive, optional field in version 1)

    private static let presetID = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    @Test func fileWithoutPresetsLoadsWithNone() throws {
        let json = #"{"version": 1, "preferences": {}, "apps": {}}"#
        #expect(try SettingsDocument.decode(from: Data(json.utf8)).presets == nil)
    }

    @Test func noPresetsLeavesTheFileWithoutThem() throws {
        let text = String(decoding: try SettingsDocument().encoded(), as: UTF8.self)
        #expect(!text.contains("presets"))
        let emptied = SettingsDocument(presets: [])
        #expect(!String(decoding: try emptied.encoded(), as: UTF8.self).contains("presets"))
    }

    @Test func presetsRoundTrip() throws {
        let document = SettingsDocument(
            apps: ["x": AppVolumeSetting(percent: 50, lastAdjusted: date)],
            presets: [
                Preset(
                    id: Self.presetID, name: "Call",
                    apps: [
                        "com.example.chat": Preset.Level(displayName: "Chat", percent: 150),
                        "com.example.player": Preset.Level(displayName: "Player", percent: 30, isMuted: true),
                    ])
            ])
        let decoded = try SettingsDocument.decode(from: document.encoded())
        #expect(decoded == document)
    }

    @Test func decodesPresetsFromJSON() throws {
        let json = """
            {
              "version": 1, "preferences": {}, "apps": {},
              "presets": [
                { "id": "\(Self.presetID.uuidString)", "name": "Call",
                  "apps": { "com.example.chat": { "displayName": "Chat", "percent": 150, "isMuted": false } } }
              ]
            }
            """
        let presets = try #require(try SettingsDocument.decode(from: Data(json.utf8)).presets)
        #expect(presets.map(\.name) == ["Call"])
        #expect(presets.first?.id == Self.presetID)
        #expect(presets.first?.apps["com.example.chat"] == Preset.Level(displayName: "Chat", percent: 150))
    }

    @Test func malformedPresetsValueIsDroppedButTheFileLoads() throws {
        let json = """
            {"version": 1, "preferences": {}, "apps": {
              "x": { "percent": 50, "isMuted": false, "lastAdjusted": "2026-11-17T14:03:00Z" }
            }, "presets": "nonsense"}
            """
        let document = try SettingsDocument.decode(from: Data(json.utf8))
        #expect(document.presets == nil)
        #expect(document.apps["x"]?.percent == 50)
    }

    @Test func malformedPresetIsDroppedAndTheOthersKept() throws {
        let json = """
            {"version": 1, "preferences": {}, "apps": {}, "presets": [
              { "name": "No ID", "apps": {} },
              42,
              { "id": "\(Self.presetID.uuidString)", "name": "Focus", "apps": {} },
              { "id": "\(UUID().uuidString)", "name": "Bad level", "apps": { "a": { "percent": "loud" } } }
            ]}
            """
        let presets = try #require(try SettingsDocument.decode(from: Data(json.utf8)).presets)
        #expect(presets.map(\.name) == ["Focus"])
    }

    @Test func normalizingAppliesThePresetRules() {
        let document = SettingsDocument(presets: [
            Preset(name: "Call", apps: [:]), Preset(name: "call", apps: [:]), Preset(name: " ", apps: [:]),
        ])
        #expect(document.normalized().presets?.map(\.name) == ["Call"])
        #expect(SettingsDocument(presets: [Preset(name: " ", apps: [:])]).normalized().presets == nil)
    }

    @Test func normalizingKeepsPresetLevelsAboveTheCurrentMaximumBoost() {
        let document = SettingsDocument(
            preferences: Preferences(maxBoostPercent: .percent150),
            presets: [Preset(name: "Loud", apps: ["a": Preset.Level(displayName: "A", percent: 200)])])
        #expect(document.normalized().presets?.first?.apps["a"]?.percent == 200)
    }
}

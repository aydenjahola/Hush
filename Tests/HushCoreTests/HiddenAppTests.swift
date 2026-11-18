import Foundation
import Testing
@testable import HushCore

@Suite struct HiddenAppTests {
    private let date = Date(timeIntervalSince1970: 1_794_924_180)
    private let safari = HiddenApp(bundleID: "com.apple.Safari", displayName: "Safari")
    private let music = HiddenApp(bundleID: "com.apple.Music", displayName: "Music")

    @Test func hidingAddsSortedByNameAndRefreshesTheName() {
        let list = [safari].hiding(music)
        #expect(list == [music, safari])
        let renamed = list.hiding(HiddenApp(bundleID: "com.apple.Music", displayName: "Apple Music"))
        #expect(renamed.map(\.displayName) == ["Apple Music", "Safari"])
    }

    @Test func showingRemovesTheApp() {
        #expect([music, safari].showing("com.apple.Music") == [safari])
        #expect([music].showing("missing") == [music])
    }

    @Test func normalizingDropsDuplicateIDs() {
        let duplicate = HiddenApp(bundleID: "com.apple.Safari", displayName: "Other")
        #expect([safari, duplicate, music].normalized() == [music, safari])
    }

    // MARK: SettingsDocument (an additive, optional field in version 1)

    @Test func fileWithoutHiddenAppsLoadsWithNone() throws {
        let json = #"{"version": 1, "preferences": {}, "apps": {}}"#
        let document = try SettingsDocument.decode(from: Data(json.utf8))
        #expect(document.hiddenApps == nil)
    }

    @Test func malformedHiddenAppsAreDroppedAndTheRestOfTheFileKept() throws {
        let json = """
            {
              "version": 1,
              "preferences": { "maxBoostPercent": 150 },
              "apps": { "com.example.player": { "percent": 62, "isMuted": false, "lastAdjusted": "2026-11-17T14:03:00Z" } },
              "hiddenApps": [{ "bundleID": 7 }]
            }
            """
        let document = try SettingsDocument.decode(from: Data(json.utf8))
        #expect(document.hiddenApps == nil)
        #expect(document.preferences.maxBoostPercent == .percent150)
        #expect(document.apps["com.example.player"]?.percent == 62)
    }

    @Test func hiddenAppsRoundTrip() throws {
        let document = SettingsDocument(
            apps: ["com.example.player": AppVolumeSetting(percent: 62, lastAdjusted: date)],
            hiddenApps: [music, safari])
        let data = try document.encoded()
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"hiddenApps\""))
        #expect(text.contains("\"bundleID\" : \"com.apple.Safari\""))
        #expect(try SettingsDocument.decode(from: data) == document)
    }

    @Test func emptyHiddenListIsNotWritten() throws {
        let text = String(decoding: try SettingsDocument(hiddenApps: []).encoded(), as: UTF8.self)
        #expect(!text.contains("hiddenApps"))
    }

    @Test func normalizingDropsAHiddenAppsLevel() {
        let document = SettingsDocument(
            apps: [
                "com.apple.Safari": AppVolumeSetting(percent: 40, lastAdjusted: date),
                "com.example.player": AppVolumeSetting(percent: 62, lastAdjusted: date),
            ],
            hiddenApps: [safari])
        #expect(document.normalized().apps.keys.sorted() == ["com.example.player"])
    }
}

import Foundation
import Testing

@testable import HushCore

@Suite struct DuckingSettingsTests {
    private func app(_ id: String, _ name: String? = nil) -> DuckingApp {
        DuckingApp(bundleID: id, displayName: name ?? id)
    }

    // MARK: Defaults

    @Test func defaultsAreOffAt30PercentWithTheDefaultCallAppsAndNoExceptions() {
        let settings = DuckingSettings()
        #expect(!settings.isEnabled)
        #expect(settings.percent == 30)
        #expect(settings.callApps == DuckingSettings.defaultCallApps)
        #expect(settings.usesDefaultCallApps)
        #expect(settings.exceptions.isEmpty)
        #expect(settings.isDefault)
    }

    @Test func defaultCallAppsCoverTheCommonCallAppsAndBrowsers() {
        let ids = Set(DuckingSettings.defaultCallApps.map(\.bundleID))
        let expected: Set<String> = [
            "us.zoom.xos", "com.apple.FaceTime", "com.microsoft.teams2", "com.microsoft.teams", "com.hnc.Discord",
            "com.tinyspeck.slackmacgap", "Cisco-Systems.Spark", "com.apple.Safari", "com.google.Chrome",
            "company.thebrowser.Browser", "com.microsoft.edgemac", "org.mozilla.firefox",
        ]
        #expect(expected.isSubset(of: ids))
        #expect(DuckingSettings.defaultCallApps.count == ids.count, "no duplicates")
    }

    @Test func duckedGainFollowsTheVolumeCurve() {
        #expect(DuckingSettings().duckedGain == VolumeCurve.gain(percent: 30))
        #expect(DuckingSettings(percent: 0).duckedGain == 0)
        #expect(DuckingSettings(percent: 90).duckedGain == VolumeCurve.gain(percent: 90))
    }

    // MARK: Validation

    @Test func percentIsClampedToTheRangeAndSnappedToTheStep() {
        #expect(DuckingSettings(percent: -10).percent == 0)
        #expect(DuckingSettings(percent: 95).percent == 90)
        #expect(DuckingSettings(percent: 200).percent == 90)
        #expect(DuckingSettings(percent: 33).percent == 35)
        #expect(DuckingSettings(percent: 32).percent == 30)
        var settings = DuckingSettings()
        settings.setPercent(47)
        #expect(settings.percent == 45)
    }

    @Test func listsKeepOneEntryPerAppSortedByName() {
        var settings = DuckingSettings()
        settings.callApps = [app("b", "Beta"), app("a", "alpha"), app("b", "Other")]
        #expect(settings.callApps == [app("a", "alpha"), app("b", "Beta")])
        settings.exceptions = [app("x", "Zed"), app("y", "Why"), app("x", "Again")]
        #expect(settings.exceptions == [app("y", "Why"), app("x", "Zed")])
    }

    // MARK: Editing

    @Test func addingAndRemovingCallAppsStopsUsingTheDefaults() {
        var settings = DuckingSettings()
        settings.addCallApp(app("com.example.call", "Example Call"))
        #expect(!settings.usesDefaultCallApps)
        #expect(settings.isCallApp("com.example.call"))
        #expect(settings.callApps.count == DuckingSettings.defaultCallApps.count + 1)

        settings.removeCallApp("us.zoom.xos")
        #expect(!settings.isCallApp("us.zoom.xos"))
        #expect(!settings.isDefault)
    }

    @Test func addingAnAppAlreadyListedRefreshesItsName() {
        var settings = DuckingSettings()
        settings.addCallApp(app("us.zoom.xos", "zoom.us"))
        #expect(settings.callApps.filter { $0.bundleID == "us.zoom.xos" }.map(\.displayName) == ["zoom.us"])
    }

    @Test func restoringDefaultsBringsBackTheDefaultList() {
        var settings = DuckingSettings()
        settings.removeCallApp("us.zoom.xos")
        settings.restoreDefaultCallApps()
        #expect(settings.usesDefaultCallApps)
        #expect(settings.callApps == DuckingSettings.defaultCallApps)
    }

    @Test func editingBackToTheDefaultListCountsAsDefault() {
        var settings = DuckingSettings()
        settings.addCallApp(app("com.example.call"))
        settings.removeCallApp("com.example.call")
        #expect(settings.usesDefaultCallApps)
        #expect(settings.isDefault)
    }

    @Test func exceptionsAreEditable() {
        var settings = DuckingSettings()
        settings.addException(app("com.example.music", "Music"))
        #expect(settings.isException("com.example.music"))
        #expect(!settings.isDefault)
        settings.removeException("com.example.music")
        #expect(!settings.isException("com.example.music"))
        #expect(settings.isDefault)
    }

    // MARK: Coding

    @Test func roundTripsThroughJSON() throws {
        var settings = DuckingSettings(isEnabled: true, percent: 45)
        settings.removeCallApp("com.apple.Safari")
        settings.addException(app("com.example.music", "Music"))
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(DuckingSettings.self, from: data) == settings)
    }

    @Test func theDefaultCallListIsNotWrittenSoNewDefaultsReachExistingUsers() throws {
        let data = try JSONEncoder().encode(DuckingSettings(isEnabled: true))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("callApps"))
        #expect(try JSONDecoder().decode(DuckingSettings.self, from: data).usesDefaultCallApps)
    }

    @Test func missingFieldsTakeTheirDefaults() throws {
        let settings = try JSONDecoder().decode(DuckingSettings.self, from: Data(#"{"isEnabled": true}"#.utf8))
        #expect(settings == DuckingSettings(isEnabled: true))
    }

    @Test func malformedFieldsTakeTheirDefaultsAndBadListEntriesAreDropped() throws {
        let json = #"""
            {"isEnabled": "yes", "percent": 57,
             "callApps": [{"bundleID": "a", "displayName": "A"}, {"bundleID": 3}],
             "exceptions": "nonsense"}
            """#
        let settings = try JSONDecoder().decode(DuckingSettings.self, from: Data(json.utf8))
        #expect(!settings.isEnabled)
        #expect(settings.percent == 55)
        #expect(settings.callApps == [app("a", "A")])
        #expect(settings.exceptions.isEmpty)
    }
}

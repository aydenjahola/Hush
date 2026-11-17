import Foundation
import Testing
@testable import HushCore

@Suite struct AppVolumeSettingTests {
    @Test func defaultsToUnityAndUnmuted() {
        let setting = AppVolumeSetting()
        #expect(setting.percent == 100)
        #expect(!setting.isMuted)
        #expect(!setting.needsEngine)
        #expect(setting.isDefault)
    }

    @Test func clampsOnInit() {
        #expect(AppVolumeSetting(percent: -20).percent == 0)
        #expect(AppVolumeSetting(percent: 999).percent == 200)
        #expect(AppVolumeSetting(percent: 180, maxPercent: 150).percent == 150)
    }

    @Test func clampsOnWrite() {
        var setting = AppVolumeSetting()
        setting.setPercent(175, maxPercent: 150)
        #expect(setting.percent == 150)
        setting.setPercent(-5, maxPercent: 200)
        #expect(setting.percent == 0)
        setting.setPercent(300, maxPercent: 400)
        #expect(setting.percent == 200, "never above the absolute maximum")
    }

    @Test func needsEngineWhenMutedOrNotUnity() {
        #expect(!AppVolumeSetting(percent: 100).needsEngine)
        #expect(AppVolumeSetting(percent: 99).needsEngine)
        #expect(AppVolumeSetting(percent: 101).needsEngine)
        #expect(AppVolumeSetting(percent: 100, isMuted: true).needsEngine)
    }

    @Test func effectiveGainIsZeroWhenMuted() {
        #expect(AppVolumeSetting(percent: 150, isMuted: true).effectiveGain == 0)
        #expect(isApproximatelyEqual(AppVolumeSetting(percent: 50).effectiveGain, 0.25))
        #expect(isApproximatelyEqual(AppVolumeSetting(percent: 150).effectiveGain, 1.5))
    }

    @Test func decodingClampsOutOfRangePercent() throws {
        let json = #"{"percent": 450, "isMuted": false, "lastAdjusted": "2026-11-17T14:03:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let setting = try decoder.decode(AppVolumeSetting.self, from: Data(json.utf8))
        #expect(setting.percent == 200)
    }

    @Test func preferencesDefaults() {
        let preferences = Preferences()
        #expect(preferences.maxBoostPercent == .percent200)
        #expect(!preferences.showInactiveApps)
    }

    @Test func preferencesDecodeMissingKeysAsDefaults() throws {
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        #expect(preferences == Preferences())
    }

    @Test func preferencesRejectUnknownBoostLimit() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Preferences.self, from: Data(#"{"maxBoostPercent": 175}"#.utf8))
        }
    }
}

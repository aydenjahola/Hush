import Foundation
import Testing

@testable import HushUI

@Suite(.timeLimit(.minutes(1))) struct LocalizationTests {
    private static let missing = "\u{1}missing\u{1}"

    /// Keys of the checked-in source catalog.
    private func catalogKeys() throws -> Set<String> {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/HushUI/Resources/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let root = try #require(object as? [String: Any])
        #expect(root["sourceLanguage"] as? String == "en")
        return Set(try #require(root["strings"] as? [String: Any]).keys)
    }

    @Test func catalogHasExactlyTheKeysTheCodeUses() throws {
        let used = Set(L10n.all.map(\.key))
        let catalog = try catalogKeys()
        #expect(used.subtracting(catalog).isEmpty, "keys used in code but missing from the catalog")
        #expect(catalog.subtracting(used).isEmpty, "catalog keys no string uses")
    }

    @Test func compiledBundleResolvesEveryKey() {
        for resource in L10n.all {
            let value = Bundle.hushUI.localizedString(forKey: resource.key, value: Self.missing, table: nil)
            #expect(value != Self.missing, "\(resource.key) isn't in the bundle's compiled catalog")
        }
    }

    @Test func englishStringsResolveThroughTheBundle() {
        #expect(String(localized: L10n.mute("Safari")) == "Mute Safari")
        #expect(String(localized: L10n.unmute("Safari")) == "Unmute Safari")
        #expect(String(localized: L10n.warning("boom")) == "Warning: boom")
        #expect(String(localized: L10n.volumeLabel("Music")) == "Music volume")
        #expect(String(localized: L10n.volumeValue(70)) == "70 percent")
        #expect(String(localized: L10n.percent(70)) == "70%")
        #expect(String(localized: L10n.updateAvailable("1.2.0")) == "Hush 1.2.0 is available")
    }

    @Test(arguments: [(0, "No apps playing"), (1, "1 app playing"), (2, "2 apps playing"), (7, "7 apps playing")])
    func playingSummaryPluralises(count: Int, expected: String) {
        #expect(String(localized: L10n.playingSummary(count: count)) == expected)
    }
}

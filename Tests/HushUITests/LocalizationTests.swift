import Foundation
import Testing

@testable import HushUI

@Suite(.timeLimit(.minutes(1))) struct LocalizationTests {
    private static let missing = "\u{1}missing\u{1}"

    private static let sourceDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/HushUI/Resources/en.lproj")

    /// Top-level keys of a checked-in English table (.strings or .stringsdict; both are plists).
    private static func tableKeys(_ url: URL) throws -> Set<String> {
        let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return Set(try #require(object as? [String: Any]).keys)
    }

    @Test func tablesHaveExactlyTheKeysTheCodeUses() throws {
        let strings = try Self.tableKeys(Self.sourceDirectory.appendingPathComponent("Localizable.strings"))
        let plurals = try Self.tableKeys(Self.sourceDirectory.appendingPathComponent("Localizable.stringsdict"))
        #expect(strings.isDisjoint(with: plurals), "keys in both Localizable.strings and .stringsdict")
        let used = Set(L10n.all.map(\.key))
        let tables = strings.union(plurals)
        #expect(used.subtracting(tables).isEmpty, "keys used in code but missing from the tables")
        #expect(tables.subtracting(used).isEmpty, "table keys no string uses")
    }

    /// The built bundle (whichever SwiftPM build system made it) has both English tables, so a
    /// build that silently drops or fails to compile them fails here rather than shipping raw keys.
    @Test func builtBundleContainsTheEnglishTables() {
        for type in ["strings", "stringsdict"] {
            let path = Bundle.hushUI.path(
                forResource: "Localizable", ofType: type, inDirectory: nil, forLocalization: "en")
            #expect(path != nil, "Localizable.\(type) isn't in \(Bundle.hushUI.bundlePath)")
        }
    }

    @Test func compiledBundleResolvesEveryKey() {
        for resource in L10n.all {
            let value = Bundle.hushUI.localizedString(forKey: resource.key, value: Self.missing, table: nil)
            #expect(value != Self.missing, "\(resource.key) isn't in the bundle's compiled strings")
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

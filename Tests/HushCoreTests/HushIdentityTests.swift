import Foundation
import HushCore
import Testing

@Suite struct HushIdentityTests {
    @Test func bundleIDMatchesInfoPlist() throws {
        let plistURL = URL(filePath: #filePath)
            .deletingLastPathComponent()  // HushCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appending(path: "Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["CFBundleIdentifier"] as? String == HushIdentity.bundleID)
        #expect(HushIdentity.bundleID == "io.github.aydenjahola.Hush")
    }
}

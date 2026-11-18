import Testing
@testable import HushCore

@Suite struct SemanticVersionTests {
    @Test func parsesMajorMinorPatch() throws {
        let version = try #require(SemanticVersion("1.2.3"))
        #expect(version.major == 1)
        #expect(version.minor == 2)
        #expect(version.patch == 3)
        #expect(version.prerelease.isEmpty)
        #expect(version.description == "1.2.3")
    }

    @Test func stripsLeadingV() {
        #expect(SemanticVersion("v0.4.1") == SemanticVersion("0.4.1"))
        #expect(SemanticVersion("V2.0.0") == SemanticVersion("2.0.0"))
    }

    @Test func parsesPrereleaseAndIgnoresBuildMetadata() throws {
        let version = try #require(SemanticVersion("1.0.0-beta.2+exp.sha.5114f85"))
        #expect(version.prerelease == ["beta", "2"])
        #expect(version.isPrerelease)
        #expect(version.description == "1.0.0-beta.2")
        #expect(SemanticVersion("1.0.0+20261118") == SemanticVersion("1.0.0"))
    }

    @Test(arguments: [
        "", "1", "1.2", "1.2.3.4", "a.b.c", "1.2.x", "-1.2.3", "1.2.3-", "1.2.3-beta..1", "01.2.3",
        "1.2.3-01", "vv1.2.3", " 1.2.3", "1.2.3 ",
    ])
    func rejectsMalformed(_ text: String) {
        #expect(SemanticVersion(text) == nil)
    }

    @Test func comparesNumericallyNotLexically() throws {
        #expect(try #require(SemanticVersion("0.10.0")) > #require(SemanticVersion("0.9.0")))
        #expect(try #require(SemanticVersion("1.0.10")) > #require(SemanticVersion("1.0.9")))
        #expect(try #require(SemanticVersion("2.0.0")) > #require(SemanticVersion("1.99.99")))
    }

    @Test func releaseIsNewerThanItsPrerelease() throws {
        #expect(try #require(SemanticVersion("1.0.0")) > #require(SemanticVersion("1.0.0-beta")))
        #expect(try #require(SemanticVersion("1.0.0-rc.1")) < #require(SemanticVersion("1.0.0")))
    }

    /// The precedence example from semver.org §11.
    @Test func followsSemverPrecedenceChain() throws {
        let chain = [
            "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2",
            "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0",
        ]
        let versions = try chain.map { try #require(SemanticVersion($0)) }
        for (lower, higher) in zip(versions, versions.dropFirst()) {
            #expect(lower < higher, "\(lower) < \(higher)")
        }
        #expect(versions.shuffled().sorted() == versions)
    }

    @Test func equalVersionsAreNotOrdered() throws {
        let a = try #require(SemanticVersion("1.2.3"))
        let b = try #require(SemanticVersion("v1.2.3"))
        #expect(a == b)
        #expect(!(a < b) && !(b < a))
    }
}

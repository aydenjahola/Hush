/// A Semantic Versioning 2.0 version: MAJOR.MINOR.PATCH with optional prerelease identifiers.
/// A leading "v" (as in git tags) is accepted; build metadata ("+…") is accepted and ignored.
package struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    package let major: Int
    package let minor: Int
    package let patch: Int
    /// Dot-separated prerelease identifiers, e.g. ["beta", "2"] for "1.0.0-beta.2". Empty for a release.
    package let prerelease: [String]

    package var isPrerelease: Bool { !prerelease.isEmpty }

    package init(major: Int, minor: Int, patch: Int, prerelease: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    package init?(_ text: String) {
        var rest = Substring(text)
        if let first = rest.first, first == "v" || first == "V" { rest = rest.dropFirst() }
        if let plus = rest.firstIndex(of: "+") {
            let build = rest[rest.index(after: plus)...]
            guard Self.isValidIdentifierList(build) else { return nil }
            rest = rest[..<plus]
        }
        var prerelease: [String] = []
        if let dash = rest.firstIndex(of: "-") {
            let tail = rest[rest.index(after: dash)...]
            guard Self.isValidIdentifierList(tail) else { return nil }
            let identifiers = tail.split(separator: ".", omittingEmptySubsequences: false)
            // Numeric prerelease identifiers must not have leading zeros.
            guard identifiers.allSatisfy({ !Self.isNumeric($0) || Self.parseNumber($0) != nil }) else { return nil }
            prerelease = identifiers.map(String.init)
            rest = rest[..<dash]
        }
        let core = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3,
              let major = Self.parseNumber(core[0]),
              let minor = Self.parseNumber(core[1]),
              let patch = Self.parseNumber(core[2])
        else { return nil }
        self.init(major: major, minor: minor, patch: patch, prerelease: prerelease)
    }

    package var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : core + "-" + prerelease.joined(separator: ".")
    }

    package static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        // A release ranks above any of its prereleases.
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true), (true, false): return false
        case (false, true): return true
        case (false, false): break
        }
        for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
            switch (Int(a), Int(b)) {
            case let (x?, y?): return x < y
            case (.some, nil): return true       // numeric identifiers rank below alphanumeric ones
            case (nil, .some): return false
            case (nil, nil): return a < b
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    // MARK: Parsing helpers

    private static func isNumeric(_ text: Substring) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// A non-negative integer without leading zeros.
    private static func parseNumber(_ text: Substring) -> Int? {
        guard isNumeric(text), text == "0" || text.first != "0" else { return nil }
        return Int(text)
    }

    /// Non-empty dot-separated identifiers of [0-9A-Za-z-].
    private static func isValidIdentifierList(_ text: Substring) -> Bool {
        let identifiers = text.split(separator: ".", omittingEmptySubsequences: false)
        return identifiers.allSatisfy { identifier in
            !identifier.isEmpty && identifier.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }
}

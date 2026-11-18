import Foundation

package struct StripSortKey: Equatable, Sendable {
    package var id: String
    package var displayName: String
    package var isPlaying: Bool
    /// nil when the app has no saved setting.
    package var lastAdjusted: Date?

    package init(id: String, displayName: String, isPlaying: Bool, lastAdjusted: Date?) {
        self.id = id
        self.displayName = displayName
        self.isPlaying = isPlaying
        self.lastAdjusted = lastAdjusted
    }
}

/// Playing apps first, then most recently adjusted (apps with no setting last), then by name.
package enum StripOrdering {
    package static func areInIncreasingOrder(_ a: StripSortKey, _ b: StripSortKey) -> Bool {
        if a.isPlaying != b.isPlaying { return a.isPlaying }
        switch (a.lastAdjusted, b.lastAdjusted) {
        case let (left?, right?) where left != right:
            return left > right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            break
        }
        let byName = a.displayName.localizedStandardCompare(b.displayName)
        if byName != .orderedSame { return byName == .orderedAscending }
        return a.id < b.id
    }

    package static func sorted(_ keys: [StripSortKey]) -> [StripSortKey] {
        keys.sorted(by: areInIncreasingOrder)
    }

    /// By name (Finder-style, so "App 2" comes before "App 10"), then by ID.
    package static func alphabeticallyInIncreasingOrder(_ a: StripSortKey, _ b: StripSortKey) -> Bool {
        let byName = a.displayName.localizedStandardCompare(b.displayName)
        if byName != .orderedSame { return byName == .orderedAscending }
        return a.id < b.id
    }

    package static func sorted(_ keys: [StripSortKey], mode: StripSortMode) -> [StripSortKey] {
        switch mode {
        case .activity: keys.sorted(by: areInIncreasingOrder)
        case .alphabetical: keys.sorted(by: alphabeticallyInIncreasingOrder)
        }
    }
}

import Foundation

public struct StripSortKey: Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var isPlaying: Bool
    /// nil when the app has no saved setting.
    public var lastAdjusted: Date?

    public init(id: String, displayName: String, isPlaying: Bool, lastAdjusted: Date?) {
        self.id = id
        self.displayName = displayName
        self.isPlaying = isPlaying
        self.lastAdjusted = lastAdjusted
    }
}

/// Playing apps first, then most recently adjusted (apps with no setting last), then by name.
public enum StripOrdering {
    public static func areInIncreasingOrder(_ a: StripSortKey, _ b: StripSortKey) -> Bool {
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

    public static func sorted(_ keys: [StripSortKey]) -> [StripSortKey] {
        keys.sorted(by: areInIncreasingOrder)
    }
}

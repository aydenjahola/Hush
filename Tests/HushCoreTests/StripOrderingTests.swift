import Foundation
import Testing
@testable import HushCore

@Suite struct StripOrderingTests {
    private let older = Date(timeIntervalSince1970: 100)
    private let newer = Date(timeIntervalSince1970: 200)

    @Test func playingAppsComeFirst() {
        let keys = [
            StripSortKey(id: "paused", displayName: "Aardvark", isPlaying: false, lastAdjusted: newer),
            StripSortKey(id: "playing", displayName: "Zebra", isPlaying: true, lastAdjusted: nil),
        ]
        #expect(StripOrdering.sorted(keys).map(\.id) == ["playing", "paused"])
    }

    @Test func thenMostRecentlyAdjustedThenNeverAdjusted() {
        let keys = [
            StripSortKey(id: "none", displayName: "Alpha", isPlaying: true, lastAdjusted: nil),
            StripSortKey(id: "old", displayName: "Bravo", isPlaying: true, lastAdjusted: older),
            StripSortKey(id: "new", displayName: "Charlie", isPlaying: true, lastAdjusted: newer),
        ]
        #expect(StripOrdering.sorted(keys).map(\.id) == ["new", "old", "none"])
    }

    @Test func thenByDisplayName() {
        let keys = [
            StripSortKey(id: "3", displayName: "music", isPlaying: true, lastAdjusted: nil),
            StripSortKey(id: "1", displayName: "Discord", isPlaying: true, lastAdjusted: nil),
            StripSortKey(id: "2", displayName: "Safari", isPlaying: true, lastAdjusted: nil),
        ]
        #expect(StripOrdering.sorted(keys).map(\.displayName) == ["Discord", "music", "Safari"])
    }

    @Test func fullExample() {
        let keys = [
            StripSortKey(id: "c", displayName: "Charlie", isPlaying: false, lastAdjusted: newer),
            StripSortKey(id: "b", displayName: "Bravo", isPlaying: true, lastAdjusted: nil),
            StripSortKey(id: "a", displayName: "Alpha", isPlaying: true, lastAdjusted: older),
            StripSortKey(id: "d", displayName: "Delta", isPlaying: true, lastAdjusted: newer),
            StripSortKey(id: "e", displayName: "Echo", isPlaying: true, lastAdjusted: nil),
        ]
        #expect(StripOrdering.sorted(keys).map(\.id) == ["d", "a", "b", "e", "c"])
    }

    @Test func alphabeticalIgnoresPlayingAndAdjustment() {
        let keys = [
            StripSortKey(id: "z", displayName: "Zoom", isPlaying: true, lastAdjusted: newer),
            StripSortKey(id: "a", displayName: "arc", isPlaying: false, lastAdjusted: nil),
            StripSortKey(id: "m", displayName: "Music", isPlaying: true, lastAdjusted: older),
        ]
        #expect(StripOrdering.sorted(keys, mode: .alphabetical).map(\.id) == ["a", "m", "z"])
    }

    @Test func alphabeticalUsesFinderNumberOrderThenID() {
        let keys = [
            StripSortKey(id: "10", displayName: "App 10", isPlaying: true, lastAdjusted: nil),
            StripSortKey(id: "2b", displayName: "App 2", isPlaying: true, lastAdjusted: nil),
            StripSortKey(id: "2a", displayName: "App 2", isPlaying: false, lastAdjusted: nil),
        ]
        #expect(StripOrdering.sorted(keys, mode: .alphabetical).map(\.id) == ["2a", "2b", "10"])
    }

    @Test func activityModeIsTheDefaultOrdering() {
        let keys = [
            StripSortKey(id: "paused", displayName: "Aardvark", isPlaying: false, lastAdjusted: newer),
            StripSortKey(id: "playing", displayName: "Zebra", isPlaying: true, lastAdjusted: nil),
        ]
        #expect(StripOrdering.sorted(keys, mode: .activity) == StripOrdering.sorted(keys))
    }
}

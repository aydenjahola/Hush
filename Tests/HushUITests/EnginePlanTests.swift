import HushAudio
import HushCore
import Testing

@testable import HushUI

@Suite(.timeLimit(.minutes(1))) struct EnginePlanTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var muted: Bool
        var percent: Int
        var playing: Bool
        var popover: Bool
        var meters: Bool
        var expected: EngineMode?
        var testDescription: String {
            "muted=\(muted) percent=\(percent) playing=\(playing) popover=\(popover) meters=\(meters)"
        }
    }

    nonisolated static let cases: [Case] = [
        // Muted, lowered or boosted playing apps are controlled, regardless of the popover.
        Case(muted: true, percent: 100, playing: true, popover: false, meters: false, expected: .control),
        Case(muted: false, percent: 40, playing: true, popover: false, meters: true, expected: .control),
        Case(muted: false, percent: 150, playing: true, popover: true, meters: true, expected: .control),
        // An idle app gets no engine, even muted (a muted tap nothing reads doesn't silence it).
        Case(muted: true, percent: 100, playing: false, popover: true, meters: true, expected: nil),
        // Default-level playing apps are only metered, and only while the popover shows meters.
        Case(muted: false, percent: 100, playing: true, popover: true, meters: true, expected: .meterOnly),
        Case(muted: false, percent: 100, playing: true, popover: false, meters: true, expected: nil),
        Case(muted: false, percent: 100, playing: true, popover: true, meters: false, expected: nil),
        Case(muted: false, percent: 100, playing: false, popover: true, meters: true, expected: nil),
    ]

    @Test(arguments: cases)
    func desiredMode(_ c: Case) {
        let setting = AppVolumeSetting(percent: c.percent, isMuted: c.muted)
        #expect(
            EnginePlan.desiredMode(
                setting: setting, isPlaying: c.playing, isPopoverVisible: c.popover, showLevelMeters: c.meters)
                == c.expected)
    }
}

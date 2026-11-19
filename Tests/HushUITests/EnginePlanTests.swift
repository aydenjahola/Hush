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

    // MARK: Ducking

    @Test func aDuckedPlayingAppIsControlledEvenAt100Percent() {
        let plain = AppVolumeSetting()
        #expect(
            EnginePlan.desiredMode(
                setting: plain, isPlaying: true, isPopoverVisible: false, showLevelMeters: true, isDucked: true)
                == .control)
        #expect(
            EnginePlan.desiredMode(
                setting: plain, isPlaying: false, isPopoverVisible: true, showLevelMeters: true, isDucked: true)
                == nil, "an idle ducked app needs no engine")
        #expect(
            EnginePlan.desiredMode(
                setting: plain, isPlaying: true, isPopoverVisible: true, showLevelMeters: true, isDucked: false)
                == .meterOnly, "after the fade back up it falls back to the usual rule")
    }

    @Test func duckedAppsArePolledWithThePopoverClosed() {
        let apps = [
            AudioApp(id: "music", displayName: "Music", processObjectIDs: [1, 2], isPlaying: false),
            AudioApp(id: "other", displayName: "Other", processObjectIDs: [3], isPlaying: true),
        ]
        #expect(
            EnginePlan.polling(
                isPopoverVisible: false, controlsEnabled: true, apps: apps, settings: [:], duckedApps: ["music"])
                == .objects([1, 2]))
        #expect(
            EnginePlan.polling(
                isPopoverVisible: false, controlsEnabled: false, apps: apps, settings: [:], duckedApps: ["music"])
                == .off)
        #expect(EnginePlan.polling(isPopoverVisible: false, controlsEnabled: true, apps: apps, settings: [:]) == .off)
    }

    @Test func inputIsTrackedOnlyWhileDuckingIsOnAndPermitted() {
        let apps = [
            AudioApp(id: "us.zoom.xos", displayName: "Zoom", processObjectIDs: [7], isPlaying: false),
            AudioApp(id: "music", displayName: "Music", processObjectIDs: [1], isPlaying: true),
            AudioApp(id: HushIdentity.bundleID, displayName: "Hush", processObjectIDs: [9], isPlaying: false),
        ]
        let on = DuckingSettings(isEnabled: true)
        #expect(EnginePlan.inputPolling(controlsEnabled: true, ducking: on, allApps: apps) == .objects([7]))
        #expect(EnginePlan.inputPolling(controlsEnabled: true, ducking: on, allApps: []) == .off)
        #expect(EnginePlan.inputPolling(controlsEnabled: false, ducking: on, allApps: apps) == nil)
        #expect(EnginePlan.inputPolling(controlsEnabled: true, ducking: DuckingSettings(), allApps: apps) == nil)
    }
}

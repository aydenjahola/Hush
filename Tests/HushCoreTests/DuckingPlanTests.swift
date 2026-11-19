import Foundation
import Testing

@testable import HushCore

@Suite struct DuckingPlanTests {
    private var settings: DuckingSettings {
        var settings = DuckingSettings(isEnabled: true)
        settings.addException(DuckingApp(bundleID: "com.example.podcast", displayName: "Podcast"))
        return settings
    }

    // MARK: Which apps are ducked

    @Test func everyAppExceptCallAppsExceptionsAndHushIsDuckable() {
        #expect(DuckingPlan.isDuckable("com.spotify.client", settings: settings))
        #expect(!DuckingPlan.isDuckable("us.zoom.xos", settings: settings))
        #expect(!DuckingPlan.isDuckable("com.example.podcast", settings: settings))
        #expect(!DuckingPlan.isDuckable(HushIdentity.bundleID, settings: settings))
    }

    @Test func aCallAppThatIsNotInACallIsStillNotDucked() {
        // Safari playing music while Zoom is in a call: Safari is a call app (Meet), so it's left alone.
        #expect(!DuckingPlan.isDuckable("com.apple.Safari", settings: settings))
    }

    @Test func duckedAppsAreThePlayingDuckableOnes() {
        let playing = ["com.spotify.client", "us.zoom.xos", "com.example.podcast", "com.apple.Music"]
        #expect(
            DuckingPlan.duckedApps(playing: playing, settings: settings)
                == ["com.spotify.client", "com.apple.Music"])
    }

    @Test func nothingIsDuckedWhileDuckingIsOff() {
        var off = settings
        off.isEnabled = false
        #expect(DuckingPlan.duckedApps(playing: ["com.spotify.client"], settings: off).isEmpty)
        #expect(!DuckingPlan.isDuckable("com.spotify.client", settings: off))
    }

    // MARK: Call apps in a call

    @Test func onlyListedCallAppsThatCaptureCount() {
        let capturing = ["us.zoom.xos", "com.example.recorder", HushIdentity.bundleID]
        #expect(DuckingPlan.capturingCallApps(capturing, settings: settings) == ["us.zoom.xos"])
    }

    @Test func hushNeverCountsEvenIfListed() {
        var listed = settings
        listed.addCallApp(DuckingApp(bundleID: HushIdentity.bundleID, displayName: "Hush"))
        #expect(DuckingPlan.capturingCallApps([HushIdentity.bundleID], settings: listed).isEmpty)
    }

    @Test func noCallAppCountsWhileDuckingIsOff() {
        var off = settings
        off.isEnabled = false
        #expect(DuckingPlan.capturingCallApps(["us.zoom.xos"], settings: off).isEmpty)
    }

    // MARK: Combined gain

    @Test func theMultiplierScalesTheAppsOwnGain() {
        let own = AppVolumeSetting(percent: 50)
        #expect(DuckingPlan.gain(own: own, multiplier: 0.09) == own.effectiveGain * 0.09)
        let boosted = AppVolumeSetting(percent: 200)
        #expect(DuckingPlan.gain(own: boosted, multiplier: 0.5) == 1)
        #expect(DuckingPlan.gain(own: AppVolumeSetting(), multiplier: 1) == 1)
    }

    @Test func aMutedAppStaysMuted() {
        let muted = AppVolumeSetting(percent: 80, isMuted: true)
        #expect(DuckingPlan.gain(own: muted, multiplier: 0.3) == 0)
    }
}

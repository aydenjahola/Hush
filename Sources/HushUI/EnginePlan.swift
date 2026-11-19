import CoreAudio
import HushAudio
import HushCore

/// The pure decisions behind engine reconciliation and polling. Nothing here touches an engine or
/// a source, so the rules that decide what is muted can be read (and tested) on their own.
enum EnginePlan {
    /// Section 4.3 of the spec: muted, lowered or boosted playing apps get a `.control` engine
    /// (gain 0 when muted), other playing apps a `.meterOnly` engine while the popover is open and
    /// meters are on, the rest none.
    ///
    /// A playing app that ducking is lowering, or is still fading back up (`isDucked`), also gets
    /// a `.control` engine, even at 100%. Once the fade back up has finished it falls back to the
    /// rule above.
    ///
    /// Muting is a control engine at gain 0: a `.muted` tap that nothing reads doesn't silence the
    /// app (confirmed live), so idle apps get no engine at all.
    static func desiredMode(
        setting: AppVolumeSetting,
        isPlaying: Bool,
        isPopoverVisible: Bool,
        showLevelMeters: Bool,
        isDucked: Bool = false
    ) -> EngineMode? {
        if (setting.needsEngine || isDucked) && isPlaying {
            .control
        } else if isPlaying && isPopoverVisible && showLevelMeters {
            .meterOnly
        } else {
            nil
        }
    }

    /// Polls only what decisions depend on:
    /// - every process while the popover is open (live strips);
    /// - otherwise the objects of every present muted, lowered or boosted app, playing or not. Its
    ///   control engine starts only once Hush sees it play and stops once Hush sees it stop. The HAL
    ///   often skips both notifications (a browser pausing and resuming), so the poll catches a
    ///   missed start (audio unprocessed) and a missed stop (an IOProc running on silence keeps the
    ///   output device and Bluetooth awake).
    /// - the same for every present app in `duckedApps` (duckable while ducking is on or still
    ///   fading), since each of those needs a control engine while it plays;
    /// - nothing otherwise; the HAL listeners still give best-effort updates.
    static func polling(
        isPopoverVisible: Bool,
        controlsEnabled: Bool,
        apps: [AudioApp],
        settings: [String: AppVolumeSetting],
        duckedApps: Set<String> = []
    ) -> ProcessPolling {
        if isPopoverVisible { return .all }
        var objects: Set<AudioObjectID> = []
        if controlsEnabled {
            for app in apps where settings[app.id]?.needsEngine ?? false || duckedApps.contains(app.id) {
                objects.formUnion(app.processObjectIDs)
            }
        }
        return objects.isEmpty ? .off : .objects(objects)
    }

    /// Microphone tracking for ducking. nil (no input tracking at all) while ducking is off or
    /// controls are disabled, so nothing changes from a Hush without ducking. Otherwise every
    /// process gets an input listener, and the call apps' processes (hidden apps included, since
    /// a hidden call app still counts) are polled too, so a call starting or ending is seen with
    /// the popover closed even when the HAL skips the notification.
    static func inputPolling(
        controlsEnabled: Bool,
        ducking: DuckingSettings,
        allApps: [AudioApp]
    ) -> ProcessPolling? {
        guard controlsEnabled, ducking.isEnabled else { return nil }
        var objects: Set<AudioObjectID> = []
        for app in allApps where app.id != HushIdentity.bundleID && ducking.isCallApp(app.id) {
            objects.formUnion(app.processObjectIDs)
        }
        return objects.isEmpty ? .off : .objects(objects)
    }
}

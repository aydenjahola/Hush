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
    /// Muting is a control engine at gain 0: a `.muted` tap that nothing reads doesn't silence the
    /// app (confirmed live), so idle apps get no engine at all.
    static func desiredMode(
        setting: AppVolumeSetting,
        isPlaying: Bool,
        isPopoverVisible: Bool,
        showLevelMeters: Bool
    ) -> EngineMode? {
        if setting.needsEngine && isPlaying {
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
    /// - nothing otherwise; the HAL listeners still give best-effort updates.
    static func polling(
        isPopoverVisible: Bool,
        controlsEnabled: Bool,
        apps: [AudioApp],
        settings: [String: AppVolumeSetting]
    ) -> ProcessPolling {
        if isPopoverVisible { return .all }
        var objects: Set<AudioObjectID> = []
        if controlsEnabled {
            for app in apps where settings[app.id]?.needsEngine ?? false {
                objects.formUnion(app.processObjectIDs)
            }
        }
        return objects.isEmpty ? .off : .objects(objects)
    }
}

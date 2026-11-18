import AppKit
import HushCore
import SwiftUI

extension EnvironmentValues {
    /// True inside the Settings sample, whose controls must not take keyboard focus.
    @Entry var isMixerPreview = false
}

/// A small static picture of the chosen layout with sample apps, for Settings → Appearance.
/// Uses the real strip views, so it always matches the popover.
struct AppearancePreview: View {
    let appearance: MixerAppearance
    let maxPercent: Int

    var body: some View {
        content
            .padding(12)
            .frame(width: 340)
            .environment(\.mixerAppearance, appearance)
            .environment(\.isMixerPreview, true)
            .allowsHitTesting(false)
            .scaleEffect(scale, anchor: .top)
            .frame(width: 340 * scale, height: height * scale, alignment: .top)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
    }

    private var scale: CGFloat { 0.75 }

    @ViewBuilder
    private var content: some View {
        let samples = SampleStrips.make(maxPercent: maxPercent)
        switch appearance.layout {
        case .channelStrips:
            HStack(alignment: .top, spacing: 8) {
                ForEach(samples) { sample in
                    ChannelStrip(strip: sample.strip, meter: sample.meter, maxPercent: maxPercent,
                                 isEnabled: true, actions: sample.actions)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .classicRows, .tiles:
            VStack(spacing: appearance.layout == .tiles ? 6 : 2) {
                ForEach(samples) { sample in
                    StripListRow(layout: appearance.layout, strip: sample.strip, meter: sample.meter,
                                 maxPercent: maxPercent, isEnabled: true, actions: sample.actions)
                }
            }
        }
    }

    private var height: CGFloat {
        let compact = appearance.isCompact
        return switch appearance.layout {
        case .channelStrips: (compact ? 200 : 250) + 24
        case .classicRows: (compact ? 3 * 26 : 3 * 30 + 4) + 24
        case .tiles: (compact ? 3 * 32 + 12 : 3 * 40 + 12) + 24
        }
    }

    private var accessibilityDescription: String {
        let name = switch appearance.layout {
        case .channelStrips: "channel strips"
        case .classicRows: "classic rows"
        case .tiles: "tiles"
        }
        return "Preview of the \(name) layout"
    }
}

/// Sample apps for the preview (and the layout renders in tests): one playing normally, one
/// boosted, one muted.
@MainActor
enum SampleStrips {
    struct Sample: Identifiable {
        let strip: MixerStore.Strip
        let meter: StripMeter
        var id: String { strip.id }
        let actions: StripActions
    }

    private static var meters: [String: StripMeter] = [:]

    static func make(maxPercent: Int) -> [Sample] {
        [
            sample("com.apple.Music", "Music", percent: 70, level: 0.5),
            sample("com.apple.Safari", "Safari", percent: min(140, maxPercent), level: 0.3),
            sample("com.apple.MobileSMS", "Messages", percent: 100, muted: true, level: 0),
        ]
    }

    private static func sample(_ id: String, _ name: String, percent: Int, muted: Bool = false, level: Float) -> Sample {
        var setting = AppVolumeSetting(percent: percent)
        setting.isMuted = muted
        let meter = meters[id] ?? StripMeter()
        meter.update(level: level)
        meters[id] = meter
        return Sample(
            strip: MixerStore.Strip(
                id: id, displayName: name, icon: icon(id), isPlaying: true, isRunning: true,
                setting: setting, engineError: nil),
            meter: meter,
            actions: StripActions(target: InertStripActions.shared, id: id))
    }

    private static var icons: [String: NSImage?] = [:]

    private static func icon(_ bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let image = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
        icons[bundleID] = image
        return image
    }
}

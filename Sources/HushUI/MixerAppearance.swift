import AppKit
import HushCore
import SwiftUI

/// The Appearance settings as the mixer views need them, passed down through the environment.
struct MixerAppearance: Equatable {
    var layout: MixerLayout = .channelStrips
    var showMeters = true
    var density: MixerDensity = .comfortable
    var showPercentages = true
    var accent: AccentChoice = .amber

    init(
        layout: MixerLayout = .channelStrips,
        showMeters: Bool = true,
        density: MixerDensity = .comfortable,
        showPercentages: Bool = true,
        accent: AccentChoice = .amber
    ) {
        self.layout = layout
        self.showMeters = showMeters
        self.density = density
        self.showPercentages = showPercentages
        self.accent = accent
    }

    init(_ preferences: AppearancePreferences) {
        self.init(
            layout: preferences.layout,
            showMeters: preferences.showLevelMeters,
            density: preferences.density,
            showPercentages: preferences.showPercentages,
            accent: preferences.accent)
    }

    var isCompact: Bool { density == .compact }

    /// Strips: a plain scroll over a fader sets the volume. Rows and tiles live in a scrolling
    /// list, so there only Option + scroll does.
    var scrollNeedsOption: Bool { layout != .channelStrips }
}

extension EnvironmentValues {
    @Entry var mixerAppearance = MixerAppearance()
}

/// What a strip's controls do. Equatable by target and app, so views holding it compare equal
/// across re-renders and SwiftUI can skip them (fresh closures never compare equal).
struct StripActions: Equatable {
    let target: any StripActionTarget
    let id: String

    @MainActor func setPercent(_ percent: Int) { target.setPercent(percent, for: id) }
    @MainActor func reset() { target.resetVolume(for: id) }
    @MainActor func toggleMute() { target.toggleMute(for: id) }

    static func == (lhs: StripActions, rhs: StripActions) -> Bool {
        lhs.id == rhs.id && lhs.target === rhs.target
    }
}

@MainActor
protocol StripActionTarget: AnyObject {
    func setPercent(_ percent: Int, for id: String)
    func resetVolume(for id: String)
    func toggleMute(for id: String)
}

extension MixerStore: StripActionTarget {}

/// For previews and the Settings sample: controls that do nothing.
final class InertStripActions: StripActionTarget {
    static let shared = InertStripActions()
    func setPercent(_ percent: Int, for id: String) {}
    func resetVolume(for id: String) {}
    func toggleMute(for id: String) {}
}

extension Palette {
    /// Boost (> 100%) fill and percent label. Always amber, whatever the accent: boost keeps one
    /// meaning, and a red system accent can't be mistaken for the red used for Muted.
    static func boost(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast) -> Color {
        amber(scheme, contrast)
    }

    /// The system accent when chosen, else nil (callers then use their neutral).
    static func systemAccentIfChosen(_ accent: AccentChoice, _ scheme: ColorScheme, _ contrast: ColorSchemeContrast)
        -> Color?
    {
        accent == .system ? systemAccent(scheme, contrast) : nil
    }

    /// The normal (up to 100%) fill: white or near-black, or the system accent if chosen.
    static func level(_ accent: AccentChoice, _ scheme: ColorScheme, _ contrast: ColorSchemeContrast) -> Color {
        switch accent {
        case .amber: neutralFill(scheme, contrast)
        case .system: systemAccent(scheme, contrast)
        }
    }

    /// The user's accent colour, darkened in light mode (and further with Increase Contrast) so a
    /// pale accent such as yellow still reads as a mark and as text on the light popover.
    static func systemAccent(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast) -> Color {
        let base = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        let adjusted: NSColor =
            switch (scheme, contrast) {
            case (.dark, .increased): base.blended(withFraction: 0.25, of: .white) ?? base
            case (.dark, _): base
            case (_, .increased): base.blended(withFraction: 0.5, of: .black) ?? base
            default: base.blended(withFraction: 0.3, of: .black) ?? base
            }
        return Color(nsColor: adjusted)
    }
}

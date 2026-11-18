import AppKit
import HushCore

/// The menu bar item's image: the speaker SF Symbol or the fader glyph (Settings → Appearance),
/// optionally with an "update available" dot.
/// The dot is drawn into the same template image (with a knocked-out ring around it), so the
/// whole icon is tinted by the menu bar and works in light, dark and tinted menu bars.
@MainActor
package enum MenuBarIcon {
    static let badgeRadius: CGFloat = 2.75
    static let badgeGap: CGFloat = 1.25
    private static let pointSize: CGFloat = 14
    private static var cache: [Key: NSImage] = [:]

    private struct Key: Hashable {
        var style: MenuBarIconStyle
        var attenuated: Bool
        var badged: Bool
    }

    package static func image(style: MenuBarIconStyle = .speaker, attenuated: Bool, badged: Bool) -> NSImage {
        let key = Key(style: style, attenuated: attenuated, badged: badged)
        if let cached = cache[key] { return cached }
        let image = switch style {
        case .speaker: render(symbolName: attenuated ? "speaker.wave.1.fill" : "speaker.wave.2.fill", badged: badged)
        case .fader: renderFaders(attenuated: attenuated, badged: badged)
        }
        cache[key] = image
        return image
    }

    /// The dot's center, in points from the image's top-left corner.
    static func badgeCenter(in size: NSSize) -> CGPoint {
        CGPoint(x: size.width - badgeRadius, y: badgeRadius)
    }

    private static func render(symbolName: String, badged: Bool) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: String(localized: L10n.appName))?
            .withSymbolConfiguration(configuration)
        else { return NSImage() }
        // A little room on the trailing side so the dot only clips the symbol's outer edge.
        // Both states use the same canvas, so the item doesn't change width when the dot appears.
        let size = NSSize(width: ceil(symbol.size.width + badgeRadius), height: symbol.size.height)
        return templateImage(size: size, badged: badged) {
            symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
        }
    }

    /// Knob heights (0 = bottom, 1 = top) for the three faders, as in the app icon.
    static func faderLevels(attenuated: Bool) -> [CGFloat] {
        attenuated ? [0.38, 0.6, 0.48] : [0.55, 0.95, 0.75]
    }

    /// The app icon's fader trio as a template glyph: faint tracks, solid level fills and knobs.
    /// The attenuated variant has its knobs lower (short fills, not just caps), like the speaker's fewer waves.
    private static func renderFaders(attenuated: Bool, badged: Bool) -> NSImage {
        let glyph = NSSize(width: 17.5, height: 14)
        let size = NSSize(width: ceil(glyph.width + badgeRadius), height: glyph.height)
        let levels = faderLevels(attenuated: attenuated)
        return templateImage(size: size, badged: badged) {
            let trackWidth: CGFloat = 1.5, fillWidth: CGFloat = 2.25, knob = NSSize(width: 4.5, height: 3.5)
            let top: CGFloat = 1.5, bottom = glyph.height - 1.5
            for (index, level) in levels.enumerated() {
                let centerX = 3 + CGFloat(index) * 5.75
                let knobY = bottom - level * (bottom - top)
                let track = NSRect(x: centerX - trackWidth / 2, y: top, width: trackWidth, height: bottom - top)
                NSColor.black.withAlphaComponent(0.45).setFill()
                NSBezierPath(roundedRect: track, xRadius: trackWidth / 2, yRadius: trackWidth / 2).fill()
                NSColor.black.setFill()
                let fill = NSRect(x: centerX - fillWidth / 2, y: knobY, width: fillWidth, height: bottom - knobY)
                NSBezierPath(roundedRect: fill, xRadius: fillWidth / 2, yRadius: fillWidth / 2).fill()
                let cap = NSRect(x: centerX - knob.width / 2, y: knobY - knob.height / 2, width: knob.width, height: knob.height)
                NSBezierPath(roundedRect: cap, xRadius: 1.25, yRadius: 1.25).fill()
            }
        }
    }

    /// Draws `content` (in flipped coordinates) into a template image, then the badge if asked.
    private static func templateImage(size: NSSize, badged: Bool, content: @escaping () -> Void) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            content()
            guard badged else { return true }
            let center = badgeCenter(in: size)
            let context = NSGraphicsContext.current
            context?.compositingOperation = .clear
            circle(center, radius: badgeRadius + badgeGap).fill()
            context?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            circle(center, radius: badgeRadius).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = String(localized: L10n.menuBarLabel(updateAvailable: badged))
        return image
    }

    private static func circle(_ center: CGPoint, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

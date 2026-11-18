import AppKit

/// The menu bar item's image: the speaker SF Symbol, optionally with an "update available" dot.
/// The dot is drawn into the same template image (with a knocked-out ring around it), so the
/// whole icon is tinted by the menu bar and works in light, dark and tinted menu bars.
@MainActor
public enum MenuBarIcon {
    static let badgeRadius: CGFloat = 2.75
    static let badgeGap: CGFloat = 1.25
    private static let pointSize: CGFloat = 14
    private static var cache: [Key: NSImage] = [:]

    private struct Key: Hashable {
        var attenuated: Bool
        var badged: Bool
    }

    public static func image(attenuated: Bool, badged: Bool) -> NSImage {
        let key = Key(attenuated: attenuated, badged: badged)
        if let cached = cache[key] { return cached }
        let image = render(symbolName: attenuated ? "speaker.wave.1.fill" : "speaker.wave.2.fill", badged: badged)
        cache[key] = image
        return image
    }

    /// The dot's center, in points from the image's top-left corner.
    static func badgeCenter(in size: NSSize) -> CGPoint {
        CGPoint(x: size.width - badgeRadius, y: badgeRadius)
    }

    private static func render(symbolName: String, badged: Bool) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Hush")?
            .withSymbolConfiguration(configuration)
        else { return NSImage() }
        // A little room on the trailing side so the dot only clips the symbol's outer edge.
        // Both states use the same canvas, so the item doesn't change width when the dot appears.
        let size = NSSize(width: ceil(symbol.size.width + badgeRadius), height: symbol.size.height)
        let image = NSImage(size: size, flipped: true) { _ in
            symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
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
        image.accessibilityDescription = badged ? "Hush, update available" : "Hush"
        return image
    }

    private static func circle(_ center: CGPoint, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

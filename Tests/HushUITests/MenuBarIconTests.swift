import AppKit
import Testing
@testable import HushUI

@MainActor
@Suite(.timeLimit(.minutes(1))) struct MenuBarIconTests {
    /// Alpha (0...1) at a point given in image points from the top-left, rendered at 2×.
    private func alpha(of image: NSImage, atX x: CGFloat, y: CGFloat) throws -> CGFloat {
        let scale: CGFloat = 2
        let width = Int(image.size.width * scale), height = Int(image.size.height * scale)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        let color = try #require(rep.colorAt(x: Int(x * scale), y: Int(y * scale)))
        return color.alphaComponent
    }

    @Test(arguments: [false, true])
    func iconsAreTemplateImagesSoTheyFollowTheMenuBarAppearance(attenuated: Bool) {
        #expect(MenuBarIcon.image(attenuated: attenuated, badged: false).isTemplate)
        #expect(MenuBarIcon.image(attenuated: attenuated, badged: true).isTemplate)
    }

    @Test func badgeAddsAnOpaqueDotAtTheTopTrailingCorner() throws {
        let plain = MenuBarIcon.image(attenuated: false, badged: false)
        let badged = MenuBarIcon.image(attenuated: false, badged: true)
        #expect(badged.size == plain.size, "no width jump when the badge appears")

        let dot = MenuBarIcon.badgeCenter(in: badged.size)
        // badgeCenter is in flipped (top-left) coordinates, matching NSBitmapImageRep.colorAt.
        #expect(try alpha(of: badged, atX: dot.x, y: dot.y) > 0.9)
        #expect(try alpha(of: plain, atX: dot.x, y: dot.y) < 0.9)
    }

    @Test func badgeIsSeparatedFromTheSymbolByAClearRing() throws {
        let badged = MenuBarIcon.image(attenuated: false, badged: true)
        let dot = MenuBarIcon.badgeCenter(in: badged.size)
        let ring = MenuBarIcon.badgeRadius + MenuBarIcon.badgeGap / 2
        // Just left of the dot, inside the knocked-out ring.
        #expect(try alpha(of: badged, atX: dot.x - ring, y: dot.y) < 0.1)
    }

    @Test func imagesAreCached() {
        #expect(MenuBarIcon.image(attenuated: true, badged: true) === MenuBarIcon.image(attenuated: true, badged: true))
    }
}

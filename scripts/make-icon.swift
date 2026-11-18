// Draws Hush's "fader trio" app icon at every size macOS needs.
//
// Usage:  make icon
//    or:  swift scripts/make-icon.swift <out-dir>
//         iconutil -c icns <out-dir>/AppIcon.iconset -o Resources/Hush.icns
//
// Writes <out-dir>/AppIcon.iconset (16-1024 px), favicon-32.png and logo-512.png
// (for the website), and preview.png (all sizes on light and dark backgrounds).
// Resources/Hush.icns is committed, so normal builds don't need to run this.

import AppKit
import CoreGraphics

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func col(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, a])!
}
func white(_ a: CGFloat) -> CGColor { CGColor(colorSpace: cs, components: [1, 1, 1, a])! }

// Continuous-curve squircle (superellipse) in rect.
func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = r.midX + r.width / 2 * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = r.midY + r.height / 2 * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}
func rrect(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: min(rad, r.width / 2), cornerHeight: min(rad, r.height / 2), transform: nil)
}

func drawIcon(_ px: Int) -> CGContext {
    let S = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    let tiny = px <= 32
    let small = px <= 64
    // Body size: full Apple grid at large sizes, relaxed at small sizes so it stays legible.
    let bodyFrac: CGFloat = px >= 128 ? 824.0 / 1024 : (px >= 64 ? 0.88 : 0.94)
    let B = S * bodyFrac
    let body = CGRect(x: (S - B) / 2, y: (S - B) / 2, width: B, height: B)
    let path = squircle(body)

    // Drop shadow
    if px >= 64 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.025, color: col(0x000000, 0.45))
        ctx.addPath(path); ctx.setFillColor(col(0x1C1C1E)); ctx.fillPath()
        ctx.restoreGState()
    }

    // Body gradient
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: cs, colors: [col(0x3A3A3C), col(0x1C1C1E)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    if !tiny {
        // faint top highlight
        let h = CGGradient(colorsSpace: cs, colors: [white(0.12), white(0)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(h, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.maxY - B * 0.45), options: [])
        // hairline rim highlight
        ctx.addPath(path); ctx.setStrokeColor(white(0.14)); ctx.setLineWidth(max(1, S * 0.003) * 2); ctx.strokePath()
    }
    ctx.restoreGState()

    // Faders, coordinates relative to body.
    let trackW: CGFloat = tiny ? 0.125 : (small ? 0.105 : 0.088)
    let knobW: CGFloat = tiny ? 0.27 : (small ? 0.235 : 0.215)
    let knobH: CGFloat = tiny ? 0.17 : (small ? 0.15 : 0.13)
    let yLo: CGFloat = tiny ? 0.16 : 0.17, yHi: CGFloat = tiny ? 0.84 : 0.83
    let xs: [CGFloat] = [0.25, 0.5, 0.75]
    let levels: [CGFloat] = [0.35, 0.70, 0.50]
    let amberIdx = 1
    let amber = col(0xFF9F0A)

    for i in 0..<3 {
        let cx = body.minX + xs[i] * B
        let tw = trackW * B
        let top = body.minY + yHi * B, bot = body.minY + yLo * B
        let ky = bot + levels[i] * (top - bot)
        let isA = i == amberIdx
        // track
        ctx.addPath(rrect(CGRect(x: cx - tw / 2, y: bot, width: tw, height: top - bot), tw / 2))
        ctx.setFillColor(white(tiny ? 0.2 : 0.14)); ctx.fillPath()
        // level fill below knob
        ctx.addPath(rrect(CGRect(x: cx - tw / 2, y: bot, width: tw, height: ky - bot), tw / 2))
        ctx.setFillColor(isA ? col(0xFF9F0A, 0.9) : white(tiny ? 0.7 : 0.62)); ctx.fillPath()
        // knob
        let kw = knobW * B, kh = knobH * B
        let kr = CGRect(x: cx - kw / 2, y: ky - kh / 2, width: kw, height: kh)
        ctx.saveGState()
        if !tiny { ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.006), blur: S * 0.014, color: col(0x000000, 0.5)) }
        ctx.addPath(rrect(kr, kh * 0.32))
        ctx.setFillColor(isA ? amber : col(0xFFFFFF)); ctx.fillPath()
        ctx.restoreGState()
        if !tiny {
            // grip line on the cap
            let gh = max(1, kh * 0.09)
            ctx.addPath(rrect(CGRect(x: kr.minX + kw * 0.2, y: ky - gh / 2, width: kw * 0.6, height: gh), gh / 2))
            ctx.setFillColor(isA ? col(0x8A4A00, 0.55) : col(0x000000, 0.22)); ctx.fillPath()
        }
    }
    return ctx
}

func writePNG(_ ctx: CGContext, _ url: URL) {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(drawIcon(base), iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(drawIcon(base * 2), iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
writePNG(drawIcon(32), outDir.appendingPathComponent("favicon-32.png"))
writePNG(drawIcon(512), outDir.appendingPathComponent("logo-512.png"))

// Preview
let pw = 1400, panelH = 620
let pv = CGContext(data: nil, width: pw, height: panelH * 2, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let panels: [(UInt32, Int)] = [(0xF5F5F7, 0), (0x1E1E1E, panelH)]
for (bg, y0) in panels {
    pv.setFillColor(col(bg)); pv.fill(CGRect(x: 0, y: CGFloat(2 * panelH - y0 - panelH), width: CGFloat(pw), height: CGFloat(panelH)))
    func place(_ px: Int, _ x: Int, _ cy: Int, scale: Int = 1, nearest: Bool = false) {
        let img = drawIcon(px).makeImage()!
        let d = px * scale
        pv.interpolationQuality = nearest ? .none : .high
        pv.draw(img, in: CGRect(x: x, y: 2 * panelH - y0 - cy - d / 2, width: d, height: d))
    }
    let cy = panelH / 2
    place(512, 40, cy)
    place(128, 600, cy)
    place(64, 760, cy)
    place(32, 856, cy)
    place(16, 920, cy)
    place(32, 980, cy, scale: 4, nearest: true)
    place(16, 1130, cy, scale: 4, nearest: true)
}
writePNG(pv, outDir.appendingPathComponent("preview.png"))

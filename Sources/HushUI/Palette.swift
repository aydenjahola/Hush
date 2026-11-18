import AppKit
import SwiftUI

enum Palette {
    static let mutedRed = Color(nsColor: .systemRed)
    /// Decorative tint only (e.g. the permission banner's wash); not for marks or text.
    static let amberTint = Color(nsColor: .systemOrange)

    /// Boost (> 100%) fill and percent label. systemOrange is only about 2.2:1 on a light
    /// background, so light mode uses a darker amber that clears 4.5:1 (text) even on grey glass.
    static func amber(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast) -> Color {
        switch (scheme, contrast) {
        case (.dark, _): Color(nsColor: .systemOrange)
        case (_, .increased): Color(red: 0x7A / 255, green: 0x3D / 255, blue: 0)  // #7A3D00
        default: Color(red: 0xA6 / 255, green: 0x53 / 255, blue: 0)  // #A65300
        }
    }
}

import HushCore
import SwiftUI

/// 3 pt vertical level bar. Green, turning yellow in the top 30%. `nil` hides it.
struct LevelMeter: View {
    let level: Float?

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geometry in
            let fraction = CGFloat(MeterBallistics.fraction(forLevel: level ?? 0))
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.primary.opacity(contrast == .increased ? 0.3 : 0.1))
                Capsule()
                    .fill(LinearGradient(
                        stops: [
                            .init(color: .green, location: 0),
                            .init(color: .green, location: 0.7),
                            .init(color: .yellow, location: 0.7),
                            .init(color: .yellow, location: 1),
                        ],
                        startPoint: .bottom,
                        endPoint: .top))
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: geometry.size.height * fraction)
                    }
            }
        }
        .frame(width: 3)
        .opacity(level == nil ? 0 : 1)
        .accessibilityHidden(true)
    }
}

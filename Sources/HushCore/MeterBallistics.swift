import Foundation

/// Display ballistics for the level meters: instant attack, 20 dB/s release.
public enum MeterBallistics {
    public static let decayDecibelsPerSecond: Double = 20
    public static let floorDecibels: Float = -60

    /// The next displayed linear level given the latest engine peak.
    public static func next(displayed: Float, peak: Float, elapsed: Double) -> Float {
        let decayFactor = Float(pow(10, -decayDecibelsPerSecond * elapsed / 20))
        let value = max(peak, displayed * decayFactor)
        return value < 0.000_1 ? 0 : value
    }

    /// Maps a linear level to 0...1 on a -60...0 dB scale.
    public static func fraction(forLevel level: Float) -> Float {
        guard level > 0 else { return 0 }
        let decibels = 20 * log10(level)
        return min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
    }
}

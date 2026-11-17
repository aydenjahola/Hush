/// Converts the percent shown on a fader into a linear gain factor.
///
/// Up to 100% the curve is quadratic so the fader feels perceptually even
/// (50% is about -12 dB). Above 100% it is linear, so 150% means 1.5x.
public enum VolumeCurve {
    public static func gain(percent: Int) -> Float {
        let fraction = Float(max(percent, 0)) / 100
        return percent <= 100 ? fraction * fraction : fraction
    }
}

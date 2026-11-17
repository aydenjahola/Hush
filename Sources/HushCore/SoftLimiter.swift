import Foundation

/// Per-sample soft clipper used only when gain is above unity.
///
/// Below the threshold samples pass unchanged; above it they are bent with
/// tanh into the remaining headroom. Float tanh saturates to exactly 1.0 for
/// large inputs, so the result is capped just below 1.0 to keep the spec's
/// "output magnitude is always < 1.0" guarantee.
public enum SoftLimiter {
    public static let threshold: Float = 0.9
    private static let ceiling: Float = Float(1).nextDown

    public static func process(_ x: Float) -> Float {
        let magnitude = abs(x)
        guard magnitude > threshold else { return x }
        let knee = 1 - threshold
        let shaped = min(threshold + knee * tanh((magnitude - threshold) / knee), ceiling)
        return x < 0 ? -shaped : shaped
    }
}

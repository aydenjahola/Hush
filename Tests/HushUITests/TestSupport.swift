func isApproximatelyEqual(_ a: Float, _ b: Float, tolerance: Float = 1e-5) -> Bool {
    abs(a - b) <= tolerance
}

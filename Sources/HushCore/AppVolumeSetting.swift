import Foundation

/// One app's saved volume state. `percent` is clamped on every write.
public struct AppVolumeSetting: Codable, Equatable, Sendable {
    public static let absoluteMaxPercent = 200

    public private(set) var percent: Int
    public var isMuted: Bool
    public var lastAdjusted: Date

    public init(
        percent: Int = 100,
        isMuted: Bool = false,
        lastAdjusted: Date = .distantPast,
        maxPercent: Int = AppVolumeSetting.absoluteMaxPercent
    ) {
        self.percent = Self.clamp(percent, maxPercent: maxPercent)
        self.isMuted = isMuted
        self.lastAdjusted = lastAdjusted
    }

    public mutating func setPercent(_ value: Int, maxPercent: Int) {
        percent = Self.clamp(value, maxPercent: maxPercent)
    }

    /// True when the app's audio must be routed through an engine.
    public var needsEngine: Bool { isMuted || percent != 100 }

    /// True when this setting equals the default (100%, unmuted) and need not be stored.
    public var isDefault: Bool { !needsEngine }

    public var effectiveGain: Float { isMuted ? 0 : VolumeCurve.gain(percent: percent) }

    static func clamp(_ value: Int, maxPercent: Int) -> Int {
        min(max(value, 0), min(maxPercent, absoluteMaxPercent))
    }

    private enum CodingKeys: String, CodingKey {
        case percent, isMuted, lastAdjusted
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawPercent = try container.decode(Int.self, forKey: .percent)
        percent = Self.clamp(rawPercent, maxPercent: Self.absoluteMaxPercent)
        isMuted = try container.decode(Bool.self, forKey: .isMuted)
        lastAdjusted = try container.decode(Date.self, forKey: .lastAdjusted)
    }
}

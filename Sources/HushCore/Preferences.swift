/// The allowed maximum boost values shown in Settings.
public enum BoostLimit: Int, Codable, CaseIterable, Sendable, Identifiable {
    case percent100 = 100
    case percent150 = 150
    case percent200 = 200

    public var id: Int { rawValue }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var maxBoostPercent: BoostLimit
    public var showInactiveApps: Bool

    public init(maxBoostPercent: BoostLimit = .percent200, showInactiveApps: Bool = false) {
        self.maxBoostPercent = maxBoostPercent
        self.showInactiveApps = showInactiveApps
    }

    private enum CodingKeys: String, CodingKey {
        case maxBoostPercent, showInactiveApps
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxBoostPercent = try container.decodeIfPresent(BoostLimit.self, forKey: .maxBoostPercent) ?? .percent200
        showInactiveApps = try container.decodeIfPresent(Bool.self, forKey: .showInactiveApps) ?? false
    }
}

import Foundation

/// An app in one of the ducking lists (call apps or never-duck exceptions).
package struct DuckingApp: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// The same key as `SettingsDocument.apps`: the bundle ID, or the executable name when the
    /// app has no bundle ID.
    package var bundleID: String
    /// The name shown in Settings, so the list reads well while the app isn't running or installed.
    package var displayName: String

    package var id: String { bundleID }

    package init(bundleID: String, displayName: String) {
        self.bundleID = bundleID
        self.displayName = displayName
    }
}

extension [DuckingApp] {
    /// One entry per ID (the first wins), sorted by name the way Finder sorts.
    package func normalizedDuckingList() -> [DuckingApp] {
        var seen: Set<String> = []
        return filter { seen.insert($0.bundleID).inserted }
            .sorted { lhs, rhs in
                let order = lhs.displayName.localizedStandardCompare(rhs.displayName)
                return order == .orderedSame ? lhs.bundleID < rhs.bundleID : order == .orderedAscending
            }
    }

    fileprivate func adding(_ app: DuckingApp) -> [DuckingApp] {
        (filter { $0.bundleID != app.bundleID } + [app]).normalizedDuckingList()
    }

    fileprivate func removing(_ id: String) -> [DuckingApp] {
        filter { $0.bundleID != id }
    }
}

/// "Lower other apps during calls": while a call app captures from a microphone, every other
/// playing app is lowered to `percent` of its own level, then restored when the call ends.
///
/// Ducking is a runtime multiplier. It is never written into an app's level, a preset or a
/// device's saved levels; only these settings are saved.
package struct DuckingSettings: Codable, Equatable, Sendable {
    package static let percentRange = 0...90
    package static let percentStep = 5
    package static let defaultPercent = 30

    /// Apps that count as call apps out of the box. Browsers are listed for calls in a web page
    /// (Google Meet and the web versions of the others). FaceTime's call audio runs in the
    /// `avconferenced` agent rather than the FaceTime app, so that is listed too.
    package static let defaultCallApps: [DuckingApp] = [
        DuckingApp(bundleID: "us.zoom.xos", displayName: "Zoom"),
        DuckingApp(bundleID: "com.apple.FaceTime", displayName: "FaceTime"),
        DuckingApp(bundleID: "com.apple.avconferenced", displayName: "FaceTime Calls"),
        DuckingApp(bundleID: "com.microsoft.teams2", displayName: "Microsoft Teams"),
        DuckingApp(bundleID: "com.microsoft.teams", displayName: "Microsoft Teams (classic)"),
        DuckingApp(bundleID: "com.hnc.Discord", displayName: "Discord"),
        DuckingApp(bundleID: "com.tinyspeck.slackmacgap", displayName: "Slack"),
        DuckingApp(bundleID: "Cisco-Systems.Spark", displayName: "Webex"),
        DuckingApp(bundleID: "com.apple.Safari", displayName: "Safari"),
        DuckingApp(bundleID: "com.google.Chrome", displayName: "Google Chrome"),
        DuckingApp(bundleID: "company.thebrowser.Browser", displayName: "Arc"),
        DuckingApp(bundleID: "com.microsoft.edgemac", displayName: "Microsoft Edge"),
        DuckingApp(bundleID: "org.mozilla.firefox", displayName: "Firefox"),
    ].normalizedDuckingList()

    /// Off by default: ducking changes other apps' volume on its own, so the user opts in.
    package var isEnabled: Bool
    /// "Lower other apps to N%", in `percentRange`, a multiple of `percentStep`.
    package private(set) var percent: Int
    /// The user's call app list, or nil while it's the default list. Keeping nil on disk means
    /// call apps added to the defaults in a later version reach existing users.
    private var customCallApps: [DuckingApp]?
    private var storedExceptions: [DuckingApp]

    package init(isEnabled: Bool = false, percent: Int = DuckingSettings.defaultPercent) {
        self.isEnabled = isEnabled
        self.percent = Self.validated(percent)
        self.customCallApps = nil
        self.storedExceptions = []
    }

    /// The apps whose microphone use starts ducking. Assigning the default list (in any order)
    /// goes back to following the defaults.
    package var callApps: [DuckingApp] {
        get { customCallApps ?? Self.defaultCallApps }
        set {
            let list = newValue.normalizedDuckingList()
            customCallApps = list == Self.defaultCallApps ? nil : list
        }
    }

    /// Apps that are never lowered, besides the call apps.
    package var exceptions: [DuckingApp] {
        get { storedExceptions }
        set { storedExceptions = newValue.normalizedDuckingList() }
    }

    package var usesDefaultCallApps: Bool { customCallApps == nil }

    /// True when nothing differs from a fresh install, so the settings file need not store it.
    package var isDefault: Bool { self == DuckingSettings() }

    /// The multiplier ducking applies to each lowered app's own gain: the volume curve at `percent`,
    /// so "30%" lowers an app the same way its fader at 30% would.
    package var duckedGain: Float { VolumeCurve.gain(percent: percent) }

    package mutating func setPercent(_ value: Int) {
        percent = Self.validated(value)
    }

    package func isCallApp(_ id: String) -> Bool { callApps.contains { $0.bundleID == id } }
    package func isException(_ id: String) -> Bool { storedExceptions.contains { $0.bundleID == id } }

    /// Adds `app` to the call apps, or refreshes its name when it's already there.
    package mutating func addCallApp(_ app: DuckingApp) { callApps = callApps.adding(app) }
    package mutating func removeCallApp(_ id: String) { callApps = callApps.removing(id) }
    package mutating func restoreDefaultCallApps() { customCallApps = nil }

    /// Adds `app` to the exceptions, or refreshes its name when it's already there.
    package mutating func addException(_ app: DuckingApp) { exceptions = exceptions.adding(app) }
    package mutating func removeException(_ id: String) { exceptions = exceptions.removing(id) }

    /// Clamps to `percentRange` and rounds to the nearest `percentStep` (halves round up).
    private static func validated(_ value: Int) -> Int {
        let clamped = min(max(value, percentRange.lowerBound), percentRange.upperBound)
        let snapped = Int((Double(clamped) / Double(percentStep)).rounded(.toNearestOrAwayFromZero)) * percentStep
        return min(snapped, percentRange.upperBound)
    }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case isEnabled, percent, callApps, exceptions
    }

    /// Each field falls back to its default when it's missing or malformed, and list entries
    /// that don't decode are dropped, so one bad value never loses the rest.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: (try? container.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? false,
            percent: (try? container.decodeIfPresent(Int.self, forKey: .percent)) ?? Self.defaultPercent)
        if let list = try? container.decodeIfPresent(LossyAppList.self, forKey: .callApps) {
            callApps = list.apps
        }
        if let list = try? container.decodeIfPresent(LossyAppList.self, forKey: .exceptions) {
            exceptions = list.apps
        }
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(percent, forKey: .percent)
        try container.encodeIfPresent(customCallApps, forKey: .callApps)
        if !storedExceptions.isEmpty { try container.encode(storedExceptions, forKey: .exceptions) }
    }

    /// Decodes a JSON array of apps, skipping entries that don't decode.
    private struct LossyAppList: Decodable {
        var apps: [DuckingApp] = []

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            while !container.isAtEnd {
                if let app = try? container.decode(DuckingApp.self) {
                    apps.append(app)
                } else if (try? container.decode(Skipped.self)) == nil {
                    break  // Couldn't step past the bad entry; keep what decoded so far.
                }
            }
        }

        private struct Skipped: Decodable {
            init(from decoder: any Decoder) throws {}
        }
    }
}

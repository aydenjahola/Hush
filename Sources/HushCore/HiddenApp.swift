import Foundation

/// An app the user hid from the mixer. Hush never adjusts a hidden app: it plays at its normal
/// volume and gets no strip, engine or meter until the user shows it again from Settings.
package struct HiddenApp: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// The same key as `SettingsDocument.apps`: the bundle ID, or the executable name when the
    /// app has no bundle ID.
    package var bundleID: String
    /// The name the mixer showed when the app was hidden, so Settings can list it while the app
    /// isn't running or installed.
    package var displayName: String

    package var id: String { bundleID }

    package init(bundleID: String, displayName: String) {
        self.bundleID = bundleID
        self.displayName = displayName
    }
}

extension [HiddenApp] {
    /// The IDs in the list, for filtering.
    package var ids: Set<String> { Set(map(\.bundleID)) }

    /// The list with `app` added (or its name refreshed when it's already there), sorted by name.
    package func hiding(_ app: HiddenApp) -> [HiddenApp] {
        (filter { $0.bundleID != app.bundleID } + [app]).sortedByName()
    }

    /// The list without the app whose ID is `id`.
    package func showing(_ id: String) -> [HiddenApp] {
        filter { $0.bundleID != id }
    }

    /// One entry per ID (the first wins), sorted by name the way Finder sorts.
    package func normalized() -> [HiddenApp] {
        var seen: Set<String> = []
        return filter { seen.insert($0.bundleID).inserted }.sortedByName()
    }

    private func sortedByName() -> [HiddenApp] {
        sorted { lhs, rhs in
            let order = lhs.displayName.localizedStandardCompare(rhs.displayName)
            return order == .orderedSame ? lhs.bundleID < rhs.bundleID : order == .orderedAscending
        }
    }
}

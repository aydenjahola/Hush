import Foundation

/// One output device's saved app levels, used when "Remember levels for each output device" is on.
package struct DeviceLevels: Codable, Equatable, Sendable {
    /// The device's name when the levels were last saved, so Settings can list it while the
    /// device isn't connected. Empty when unknown; Settings then shows the UID.
    package var name: String
    /// Keyed like `SettingsDocument.apps`. Only apps that aren't at 100% and unmuted are kept; an
    /// empty set still matters, because it means "every app at 100%" on this device.
    package var apps: [String: AppVolumeSetting]

    package init(name: String, apps: [String: AppVolumeSetting] = [:]) {
        self.name = name
        self.apps = apps
    }

    private enum CodingKeys: String, CodingKey {
        case name, apps
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        apps = try container.decode([String: AppVolumeSetting].self, forKey: .apps)
    }
}

/// The pure rules behind remembering app levels per output device. Each device, keyed by its UID,
/// has its own set of levels; the mixer's current levels always belong to one device.
///
/// When the output changes to another device, the current levels are stored as the old device's
/// set. If the new device has a saved set, it becomes the current levels; if it doesn't, the
/// current levels carry over as its starting point, so the first switch changes nothing audible.
/// Hidden apps are never stored or loaded.
package struct DeviceLevelBook: Equatable, Sendable {
    /// The device a set belongs to.
    package struct Device: Equatable, Sendable {
        package var uid: String
        package var name: String

        package init(uid: String, name: String) {
            self.uid = uid
            self.name = name
        }
    }

    /// Keyed by device UID.
    package private(set) var sets: [String: DeviceLevels]

    package init(sets: [String: DeviceLevels] = [:]) {
        self.sets = sets.filter { !$0.key.isEmpty }
    }

    package var isEmpty: Bool { sets.isEmpty }

    package func levels(for uid: String) -> DeviceLevels? {
        sets[uid]
    }

    /// Every device with a saved set, sorted by name the way Finder sorts (by UID when a name is
    /// missing or two names match).
    package var devices: [Device] {
        sets.map { Device(uid: $0.key, name: $0.value.name) }
            .sorted { lhs, rhs in
                let order = Self.label(lhs).localizedStandardCompare(Self.label(rhs))
                return order == .orderedSame ? lhs.uid < rhs.uid : order == .orderedAscending
            }
    }

    /// Stores `settings` as `device`'s set, replacing any earlier one and refreshing its name.
    /// Turning the feature on seeds the current device this way. Does nothing for an empty UID.
    package mutating func store(
        _ settings: [String: AppVolumeSetting],
        for device: Device,
        maxPercent: Int = AppVolumeSetting.absoluteMaxPercent,
        excluding hidden: Set<String> = []
    ) {
        guard !device.uid.isEmpty else { return }
        sets[device.uid] = DeviceLevels(
            name: device.name,
            apps: Self.cleaned(settings, maxPercent: maxPercent, excluding: hidden))
    }

    /// Switching the output from `old` (nil when no device's levels are current yet) to `new`.
    /// Returns the new current levels and the updated book: `current` is stored as `old`'s set,
    /// then `new`'s saved set is loaded, or `current` carries over and becomes `new`'s set.
    /// The same UID, or an empty one, switches nothing.
    package func switching(
        from old: Device?,
        to new: Device,
        current: [String: AppVolumeSetting],
        maxPercent: Int,
        excluding hidden: Set<String> = []
    ) -> (settings: [String: AppVolumeSetting], book: DeviceLevelBook) {
        guard !new.uid.isEmpty, old?.uid != new.uid else { return (current, self) }
        var book = self
        if let old { book.store(current, for: old, maxPercent: maxPercent, excluding: hidden) }
        let settings: [String: AppVolumeSetting]
        if let saved = book.sets[new.uid] {
            settings = Self.cleaned(saved.apps, maxPercent: maxPercent, excluding: hidden)
        } else {
            settings = Self.cleaned(current, maxPercent: maxPercent, excluding: hidden)
        }
        book.store(settings, for: new, maxPercent: maxPercent, excluding: hidden)
        return (settings, book)
    }

    /// Drops a device's saved set.
    package mutating func forget(_ uid: String) {
        sets[uid] = nil
    }

    /// Drops every device's saved set.
    package mutating func reset() {
        sets = [:]
    }

    /// Every set clamped to `maxPercent`, without default entries or apps in `hidden`.
    package func normalized(maxPercent: Int, excluding hidden: Set<String> = []) -> DeviceLevelBook {
        var copy = self
        for (uid, set) in sets {
            copy.sets[uid]?.apps = Self.cleaned(set.apps, maxPercent: maxPercent, excluding: hidden)
        }
        return copy
    }

    /// `settings` clamped to `maxPercent`, without default entries or apps in `hidden`: what may be
    /// stored or applied as levels.
    package static func cleaned(
        _ settings: [String: AppVolumeSetting],
        maxPercent: Int,
        excluding hidden: Set<String> = []
    ) -> [String: AppVolumeSetting] {
        var result: [String: AppVolumeSetting] = [:]
        for (id, setting) in settings where !hidden.contains(id) {
            var clamped = setting
            clamped.setPercent(setting.percent, maxPercent: maxPercent)
            if !clamped.isDefault { result[id] = clamped }
        }
        return result
    }

    private static func label(_ device: Device) -> String {
        device.name.isEmpty ? device.uid : device.name
    }
}

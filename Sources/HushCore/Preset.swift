import Foundation

/// A named snapshot of every app's level and mute state, such as "Call", "Focus" or "Gaming".
///
/// A preset only stores the apps that weren't at the default (100%, unmuted) when it was saved.
/// Applying it reproduces the snapshot exactly: the apps it holds get their saved levels and every
/// other app goes back to 100% and unmuted.
package struct Preset: Codable, Equatable, Sendable, Identifiable {
    /// One app's saved level in a preset.
    package struct Level: Codable, Equatable, Sendable {
        /// The app's name when the preset was saved, for showing the preset while the app isn't running.
        package var displayName: String
        package private(set) var percent: Int
        package var isMuted: Bool

        package init(displayName: String, percent: Int, isMuted: Bool = false) {
            self.displayName = displayName
            self.percent = AppVolumeSetting.clamp(percent, maxPercent: AppVolumeSetting.absoluteMaxPercent)
            self.isMuted = isMuted
        }

        /// True when this level is 100% and unmuted, which a preset doesn't need to store.
        package var isDefault: Bool { percent == 100 && !isMuted }

        private enum CodingKeys: String, CodingKey {
            case displayName, percent, isMuted
        }

        package init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                displayName: try container.decode(String.self, forKey: .displayName),
                percent: try container.decode(Int.self, forKey: .percent),
                isMuted: try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false)
        }
    }

    package var id: UUID
    package var name: String
    /// Keyed by bundle ID, or executable name when there is no bundle ID (as in `SettingsDocument.apps`).
    package var apps: [String: Level]

    package init(id: UUID = UUID(), name: String, apps: [String: Level]) {
        self.id = id
        self.name = name
        self.apps = apps
    }

    /// The levels to store for `settings`: every app that isn't at 100% and unmuted.
    package static func levels(
        from settings: [String: AppVolumeSetting],
        displayName: (String) -> String
    ) -> [String: Level] {
        var levels: [String: Level] = [:]
        for (id, setting) in settings where !setting.isDefault {
            levels[id] = Level(displayName: displayName(id), percent: setting.percent, isMuted: setting.isMuted)
        }
        return levels
    }

    /// The settings after applying this preset to `settings`. Apps in the preset get its level
    /// (clamped to `maxPercent`); every other app goes back to the default, so it has no entry.
    /// An app whose level doesn't change keeps its `lastAdjusted`; the others get `now`.
    /// Apps in `hidden` never get a level (hidden apps always play at 100%), so a preset that
    /// holds a hidden app still applies to the rest.
    package func applied(
        to settings: [String: AppVolumeSetting],
        maxPercent: Int,
        now: Date,
        excluding hidden: Set<String> = []
    ) -> [String: AppVolumeSetting] {
        var result: [String: AppVolumeSetting] = [:]
        for (id, level) in apps where !hidden.contains(id) {
            var setting = AppVolumeSetting(percent: level.percent, isMuted: level.isMuted, maxPercent: maxPercent)
            guard !setting.isDefault else { continue }
            if let current = settings[id], current.percent == setting.percent, current.isMuted == setting.isMuted {
                setting.lastAdjusted = current.lastAdjusted
            } else {
                setting.lastAdjusted = now
            }
            result[id] = setting
        }
        return result
    }

    /// True when `settings` are exactly what applying this preset would give (ignoring when each
    /// app was last adjusted). Apps in `hidden` are left out on both sides, so a preset holding a
    /// hidden app can still be active.
    package func matches(
        _ settings: [String: AppVolumeSetting],
        maxPercent: Int,
        excluding hidden: Set<String> = []
    ) -> Bool {
        let target = applied(to: settings, maxPercent: maxPercent, now: .distantPast, excluding: hidden)
        let current = settings.filter { !$0.value.isDefault && !hidden.contains($0.key) }
        guard target.count == current.count else { return false }
        return target.allSatisfy { id, setting in
            guard let other = current[id] else { return false }
            return other.percent == setting.percent && other.isMuted == setting.isMuted
        }
    }
}

/// The user's presets, in the order they were saved, with the rules for naming them.
///
/// Names are trimmed and unique ignoring case. There are at most `maxCount` presets.
package struct PresetLibrary: Equatable, Sendable {
    package static let maxCount = 20

    /// What a proposed name would do.
    package enum NameCheck: Equatable, Sendable {
        /// Nothing but whitespace.
        case empty
        /// Free to use; the trimmed name.
        case available(String)
        /// Another preset already has this name (ignoring case). Saving replaces it; renaming can't use it.
        case taken(Preset)
        /// The name is new, but the library already holds `maxCount` presets.
        case limitReached
    }

    package private(set) var presets: [Preset]

    /// Loads `presets`, dropping what the rules don't allow: blank or repeated names (the first
    /// wins), default levels, and anything past `maxCount`. Names are trimmed.
    package init(presets: [Preset] = []) {
        var kept: [Preset] = []
        for var preset in presets {
            preset.name = Self.trimmed(preset.name)
            preset.apps = preset.apps.filter { !$0.value.isDefault }
            guard !preset.name.isEmpty, !kept.contains(where: { Self.sameName($0.name, preset.name) }),
                !kept.contains(where: { $0.id == preset.id })
            else { continue }
            kept.append(preset)
            if kept.count == Self.maxCount { break }
        }
        self.presets = kept
    }

    package var isEmpty: Bool { presets.isEmpty }
    package var isFull: Bool { presets.count >= Self.maxCount }

    package func preset(_ id: Preset.ID) -> Preset? {
        presets.first { $0.id == id }
    }

    /// Checks `name` for saving a preset, or for renaming the preset `renaming`.
    package func check(name: String, renaming: Preset.ID? = nil) -> NameCheck {
        let name = Self.trimmed(name)
        guard !name.isEmpty else { return .empty }
        if let existing = presets.first(where: { $0.id != renaming && Self.sameName($0.name, name) }) {
            return .taken(existing)
        }
        if renaming == nil, isFull { return .limitReached }
        return .available(name)
    }

    /// Saves `apps` under `name`: replaces the preset with that name (keeping its place and ID,
    /// taking the new spelling) or adds a new one at the end. Returns nil, changing nothing, when
    /// the name is empty or the library is full.
    @discardableResult
    package mutating func save(name: String, apps: [String: Preset.Level], id: UUID = UUID()) -> Preset? {
        let apps = apps.filter { !$0.value.isDefault }
        switch check(name: name) {
        case .empty, .limitReached:
            return nil
        case .taken(let existing):
            guard let index = presets.firstIndex(where: { $0.id == existing.id }) else { return nil }
            presets[index].name = Self.trimmed(name)
            presets[index].apps = apps
            return presets[index]
        case .available(let trimmed):
            let preset = Preset(id: id, name: trimmed, apps: apps)
            presets.append(preset)
            return preset
        }
    }

    /// Renames a preset. Returns false, changing nothing, when the name is empty, another preset
    /// has it, or there is no such preset.
    @discardableResult
    package mutating func rename(_ id: Preset.ID, to name: String) -> Bool {
        guard case .available(let trimmed) = check(name: name, renaming: id),
            let index = presets.firstIndex(where: { $0.id == id })
        else { return false }
        presets[index].name = trimmed
        return true
    }

    package mutating func delete(_ id: Preset.ID) {
        presets.removeAll { $0.id == id }
    }

    /// The first preset that `settings` match exactly, ignoring apps in `hidden`, if any.
    /// Computed, never stored.
    package func activePreset(
        for settings: [String: AppVolumeSetting],
        maxPercent: Int,
        excluding hidden: Set<String> = []
    ) -> Preset? {
        presets.first { $0.matches(settings, maxPercent: maxPercent, excluding: hidden) }
    }

    private static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sameName(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive]) == .orderedSame
    }
}

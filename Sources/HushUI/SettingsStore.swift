import Foundation
import HushCore
import os

/// Settings access for `MixerStore`. Writes go through `update` so they change only the parts
/// they own: the update checker shares the same file.
package protocol SettingsPersisting: AnyObject {
    func load() -> SettingsDocument
    func update(_ change: (inout SettingsDocument) -> Void)
    /// The document as last loaded or written, reading the file only if nothing is in memory yet.
    func latest() -> SettingsDocument
}

extension SettingsPersisting {
    package func latest() -> SettingsDocument { load() }
}

/// Settings access for `UpdateChecker`: only the "updates" section.
package protocol UpdateSettingsPersisting: AnyObject {
    func loadUpdateSettings() -> UpdateSettings
    func saveUpdateSettings(_ settings: UpdateSettings)
}

/// Reads and writes settings.json. A corrupt or unknown-version file is moved aside.
/// Keeps the last loaded or written document in memory, so each writer's `update` starts from
/// the other writers' latest changes. Used on the main actor only.
package final class SettingsStore: SettingsPersisting, UpdateSettingsPersisting {
    package static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "Hush/settings.json")
    }

    private let fileURL: URL
    private let now: () -> Date
    private let logger = Logger(subsystem: HushIdentity.bundleID, category: "settings")
    private var current: SettingsDocument?

    package init(fileURL: URL = SettingsStore.defaultFileURL, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
    }

    package func load() -> SettingsDocument {
        let document = readFile()
        current = document
        return document
    }

    package func latest() -> SettingsDocument {
        current ?? load()
    }

    package func update(_ change: (inout SettingsDocument) -> Void) {
        var document = current ?? load()
        change(&document)
        save(document)
    }

    package func loadUpdateSettings() -> UpdateSettings {
        (current ?? load()).updates
    }

    package func saveUpdateSettings(_ settings: UpdateSettings) {
        update { $0.updates = settings }
    }

    package func save(_ document: SettingsDocument) {
        current = document
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try document.encoded().write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not save settings: \(String(describing: error), privacy: .public)")
        }
    }

    private func readFile() -> SettingsDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return SettingsDocument() }
        do {
            let data = try Data(contentsOf: fileURL)
            return try SettingsDocument.decode(from: data)
        } catch {
            logger.error("Settings unreadable, starting with defaults: \(String(describing: error), privacy: .public)")
            moveAside()
            return SettingsDocument()
        }
    }

    private func moveAside() {
        let stamp = Int(now().timeIntervalSince1970)
        let destination = fileURL.deletingLastPathComponent().appending(path: "settings.corrupt-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: destination)
        } catch {
            logger.error("Could not move corrupt settings aside: \(String(describing: error), privacy: .public)")
        }
    }
}

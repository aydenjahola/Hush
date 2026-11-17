import Foundation
import HushCore
import os

public protocol SettingsPersisting: AnyObject {
    func load() -> SettingsDocument
    func save(_ document: SettingsDocument)
}

/// Reads and writes settings.json. A corrupt or unknown-version file is moved aside.
public final class SettingsStore: SettingsPersisting {
    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "Hush/settings.json")
    }

    private let fileURL: URL
    private let now: () -> Date
    private let logger = Logger(subsystem: HushIdentity.bundleID, category: "settings")

    public init(fileURL: URL = SettingsStore.defaultFileURL, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
    }

    public func load() -> SettingsDocument {
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

    public func save(_ document: SettingsDocument) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try document.encoded().write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not save settings: \(String(describing: error), privacy: .public)")
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

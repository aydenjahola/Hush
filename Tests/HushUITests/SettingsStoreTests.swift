import Foundation
import HushCore
import Testing
@testable import HushUI

@Suite(.timeLimit(.minutes(1))) struct SettingsStoreTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "HushTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func missingFileLoadsDefaults() throws {
        let file = try makeDirectory().appending(path: "settings.json")
        let store = SettingsStore(fileURL: file)
        #expect(store.load() == SettingsDocument())
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func savesAndLoadsCreatingFolders() throws {
        let file = try makeDirectory().appending(path: "Hush/settings.json")
        let store = SettingsStore(fileURL: file)
        let document = SettingsDocument(apps: [
            "com.example.player": AppVolumeSetting(percent: 62, lastAdjusted: Date(timeIntervalSince1970: 1_794_924_180)),
        ])
        store.save(document)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(store.load() == document)
    }

    @Test func corruptFileIsMovedAsideAndDefaultsUsed() throws {
        let directory = try makeDirectory()
        let file = directory.appending(path: "settings.json")
        try Data("{oops".utf8).write(to: file)
        let store = SettingsStore(fileURL: file, now: { Date(timeIntervalSince1970: 1_800_000_000) })

        #expect(store.load() == SettingsDocument())
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let aside = directory.appending(path: "settings.corrupt-1800000000.json")
        #expect(FileManager.default.fileExists(atPath: aside.path))
    }

    @Test func unknownVersionIsMovedAside() throws {
        let directory = try makeDirectory()
        let file = directory.appending(path: "settings.json")
        try Data(#"{"version": 9, "preferences": {}, "apps": {}}"#.utf8).write(to: file)
        let store = SettingsStore(fileURL: file, now: { Date(timeIntervalSince1970: 42) })

        #expect(store.load() == SettingsDocument())
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "settings.corrupt-42.json").path))
    }

    @Test func levelAndUpdateWritesMergeInsteadOfClobbering() throws {
        let file = try makeDirectory().appending(path: "settings.json")
        let store = SettingsStore(fileURL: file)
        _ = store.load()
        let level = AppVolumeSetting(percent: 62, lastAdjusted: Date(timeIntervalSince1970: 1_794_924_180))

        store.update { $0.apps = ["com.example.player": level] }
        store.saveUpdateSettings(UpdateSettings(skippedVersion: "0.3.0"))
        store.update { $0.preferences.showInactiveApps = true }

        let reloaded = SettingsStore(fileURL: file).load()
        #expect(reloaded.apps["com.example.player"] == level)
        #expect(reloaded.preferences.showInactiveApps)
        #expect(reloaded.updates.skippedVersion == "0.3.0")
        #expect(SettingsStore(fileURL: file).loadUpdateSettings().skippedVersion == "0.3.0")
    }

    @Test func updateWithoutAnEarlierLoadStartsFromTheFile() throws {
        let file = try makeDirectory().appending(path: "settings.json")
        SettingsStore(fileURL: file).saveUpdateSettings(UpdateSettings(automaticUpdateChecks: false))

        let store = SettingsStore(fileURL: file)
        store.update { $0.preferences.maxBoostPercent = .percent150 }

        let reloaded = SettingsStore(fileURL: file).load()
        #expect(!reloaded.updates.automaticUpdateChecks)
        #expect(reloaded.preferences.maxBoostPercent == .percent150)
    }
}

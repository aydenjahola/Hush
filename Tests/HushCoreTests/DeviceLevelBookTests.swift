import Foundation
import Testing

@testable import HushCore

@Suite struct DeviceLevelBookTests {
    private let date = Date(timeIntervalSince1970: 1_794_924_180)
    private let speakers = DeviceLevelBook.Device(uid: "built-in", name: "MacBook Pro Speakers")
    private let headphones = DeviceLevelBook.Device(uid: "airpods", name: "AirPods Pro")

    private func level(_ percent: Int, muted: Bool = false) -> AppVolumeSetting {
        AppVolumeSetting(percent: percent, isMuted: muted, lastAdjusted: date)
    }

    @Test func firstVisitCarriesTheCurrentLevelsOver() {
        let current = ["music": level(40)]
        let result = DeviceLevelBook().switching(from: speakers, to: headphones, current: current, maxPercent: 200)
        #expect(result.settings == current)
        #expect(result.book.levels(for: "built-in") == DeviceLevels(name: "MacBook Pro Speakers", apps: current))
        #expect(result.book.levels(for: "airpods") == DeviceLevels(name: "AirPods Pro", apps: current))
    }

    @Test func switchingLoadsTheNewDevicesSetAndStoresTheOld() {
        var book = DeviceLevelBook()
        book.store(["music": level(150)], for: headphones)
        let result = book.switching(
            from: speakers, to: headphones, current: ["music": level(40), "chat": level(100, muted: true)],
            maxPercent: 200)
        #expect(result.settings == ["music": level(150)])
        #expect(result.book.levels(for: "built-in")?.apps == ["music": level(40), "chat": level(100, muted: true)])

        let back = result.book.switching(
            from: headphones, to: speakers, current: result.settings, maxPercent: 200)
        #expect(back.settings == ["music": level(40), "chat": level(100, muted: true)])
    }

    @Test func anEmptySetMeansEveryAppAtFullVolume() {
        var book = DeviceLevelBook()
        book.store([:], for: headphones)
        let result = book.switching(from: speakers, to: headphones, current: ["music": level(40)], maxPercent: 200)
        #expect(result.settings.isEmpty)
    }

    @Test func theSameOrAnEmptyUIDSwitchesNothing() {
        var book = DeviceLevelBook()
        book.store(["music": level(10)], for: speakers)
        let renamed = DeviceLevelBook.Device(uid: "built-in", name: "Speakers")
        let same = book.switching(from: speakers, to: renamed, current: ["music": level(40)], maxPercent: 200)
        #expect(same.settings == ["music": level(40)])
        #expect(same.book == book)

        let blank = DeviceLevelBook.Device(uid: "", name: "Unknown")
        let none = book.switching(from: speakers, to: blank, current: ["music": level(40)], maxPercent: 200)
        #expect(none.settings == ["music": level(40)])
        #expect(none.book == book)
    }

    @Test func withNoCurrentDeviceNothingIsStoredForIt() {
        let result = DeviceLevelBook().switching(from: nil, to: speakers, current: ["a": level(40)], maxPercent: 200)
        #expect(result.settings == ["a": level(40)])
        #expect(result.book.devices == [speakers])
    }

    @Test func hiddenAppsAreNeverStoredOrLoaded() {
        var book = DeviceLevelBook()
        book.store(["hidden": level(20), "music": level(150)], for: headphones)
        #expect(book.levels(for: "airpods")?.apps.keys.sorted() == ["hidden", "music"], "stored before it was hidden")

        let result = book.switching(
            from: speakers, to: headphones, current: ["hidden": level(30), "chat": level(60)], maxPercent: 200,
            excluding: ["hidden"])
        #expect(result.settings == ["music": level(150)])
        #expect(result.book.levels(for: "built-in")?.apps == ["chat": level(60)])
        #expect(result.book.levels(for: "airpods")?.apps == ["music": level(150)])
    }

    @Test func loadedLevelsAreClampedAndDefaultsDropped() {
        var book = DeviceLevelBook()
        book.store(["loud": level(200), "plain": level(100)], for: headphones)
        #expect(book.levels(for: "airpods")?.apps == ["loud": level(200)])
        let result = book.switching(from: speakers, to: headphones, current: [:], maxPercent: 150)
        #expect(result.settings["loud"]?.percent == 150)
        #expect(book.normalized(maxPercent: 100).levels(for: "airpods")?.apps.isEmpty == true)
    }

    @Test func seedingReplacesTheSetAndRefreshesTheName() {
        var book = DeviceLevelBook()
        book.store(["a": level(10)], for: speakers)
        book.store(["b": level(20)], for: DeviceLevelBook.Device(uid: "built-in", name: "Speakers"))
        #expect(book.levels(for: "built-in") == DeviceLevels(name: "Speakers", apps: ["b": level(20)]))
        book.store(["c": level(30)], for: DeviceLevelBook.Device(uid: "", name: "No UID"))
        #expect(book.devices.map(\.uid) == ["built-in"])
    }

    @Test func forgetAndReset() {
        var book = DeviceLevelBook()
        book.store(["a": level(10)], for: speakers)
        book.store(["a": level(20)], for: headphones)
        book.forget("built-in")
        #expect(book.devices == [headphones])
        book.forget("unknown")
        #expect(book.devices == [headphones])
        book.reset()
        #expect(book.isEmpty)
    }

    @Test func devicesAreSortedByNameWithTheUIDAsFallback() {
        let book = DeviceLevelBook(sets: [
            "z": DeviceLevels(name: "Studio Display"),
            "a": DeviceLevels(name: "AirPods Pro"),
            "m-uid": DeviceLevels(name: ""),
            "": DeviceLevels(name: "Dropped"),
        ])
        #expect(book.devices.map(\.uid) == ["a", "m-uid", "z"])
    }
}

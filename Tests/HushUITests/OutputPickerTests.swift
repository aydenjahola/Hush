import AppKit
import CoreAudio
import Foundation
import HushAudio
import HushCore
import SwiftUI
import Testing

@testable import HushUI

private let speakers = OutputDevice(
    id: 1, uid: "built-in", name: "MacBook Pro Speakers", transport: .builtInSpeakers)
private let airPods = OutputDevice(id: 2, uid: "airpods", name: "AirPods Pro", transport: .bluetooth)
private let blackHole = OutputDevice(id: 3, uid: "BlackHole2ch_UID", name: "BlackHole 2ch", transport: .virtual)
private let display = OutputDevice(id: 4, uid: "lg", name: "LG UltraFine", transport: .displayPort)

@MainActor
@Suite(.timeLimit(.minutes(1))) struct OutputPickerStoreTests {
    @Test func deviceListPublishes() {
        let h = Harness()
        #expect(h.store.outputDevices.isEmpty)
        h.output.emitDevices([airPods, speakers, blackHole])
        #expect(h.store.outputDevices == [airPods, speakers, blackHole])
    }

    @Test func liveAddAndRemoveUpdateTheList() {
        let h = Harness()
        h.output.emitDevices([speakers])
        h.output.emitDevices([airPods, speakers])
        #expect(h.store.outputDevices.map(\.id) == [2, 1])
        h.output.emitDevices([speakers])
        #expect(h.store.outputDevices.map(\.id) == [1])
    }

    @Test func selectingADeviceAsksTheSourceAndWaitsForItToConfirm() {
        let h = Harness()
        h.output.emitDevices([airPods, speakers])
        h.store.selectOutput(airPods)
        #expect(h.output.selections == [2])
        // Not optimistic: the checkmark stays on the real default until the source reports the change.
        #expect(h.store.outputDevice?.id == 1)
        h.output.emit(airPods)
        #expect(h.store.outputDevice?.id == 2)
        #expect(h.store.outputSelectionError == nil)
    }

    @Test func confirmedSwitchRebuildsAdjustedAppsThroughTheOutputChangePath() throws {
        let h = Harness()
        h.processes.emit([makeApp("a")])
        h.store.setPercent(50, for: "a")
        let engine = try #require(h.factory.live("a"))
        h.store.selectOutput(airPods)
        #expect(engine.rebuiltDeviceIDs.isEmpty)
        h.output.emit(airPods)
        #expect(engine.rebuiltDeviceIDs == [2])
    }

    @Test func failureShowsAnErrorAndLeavesTheCheckmark() {
        let h = Harness()
        h.output.emitDevices([airPods, speakers])
        h.output.selectionError = FakeError()
        h.store.selectOutput(airPods)
        #expect(h.output.selections == [2])
        #expect(h.store.outputDevice?.id == 1)
        #expect(h.store.outputSelectionError == "Couldn't switch to AirPods Pro")
    }

    @Test func nextSuccessClearsTheError() {
        let h = Harness()
        h.output.selectionError = FakeError()
        h.store.selectOutput(airPods)
        #expect(h.store.outputSelectionError != nil)
        h.output.selectionError = nil
        h.store.selectOutput(blackHole)
        #expect(h.store.outputSelectionError == nil)
    }

    @Test func errorClearsItselfAfterAFewSeconds() async throws {
        let h = Harness(outputErrorDuration: .milliseconds(10))
        h.output.selectionError = FakeError()
        h.store.selectOutput(airPods)
        #expect(h.store.outputSelectionError != nil)
        let task = try #require(h.store.outputErrorTask)
        await task.value
        #expect(h.store.outputSelectionError == nil)
    }

    @Test func reselectingTheCurrentDeviceIsANoOp() {
        let h = Harness()
        h.output.emitDevices([airPods, speakers])
        h.store.selectOutput(speakers)
        #expect(h.output.selections.isEmpty)
        #expect(h.store.outputSelectionError == nil)
    }

    @Test func sourcesWithoutPickerSupportReportAFailure() {
        let source = MinimalOutputSource()
        #expect(throws: OutputSelectionUnsupported.self) { try source.setDefaultOutput(2) }
        var lists: [[OutputDevice]] = []
        source.observeDevices { lists.append($0) }
        #expect(lists.isEmpty)
    }
}

/// A conformer that only implements `start`, as written before the picker existed.
@MainActor
private final class MinimalOutputSource: OutputDeviceSource {
    func start(onChange: @escaping @MainActor (OutputDevice?) -> Void) { onChange(nil) }
}

@MainActor
@Suite(.timeLimit(.minutes(1))) struct OutputPickerViewTests {
    @Test func everyTransportHasARealSymbol() {
        for transport in OutputTransport.allCases {
            #expect(
                NSImage(systemSymbolName: transport.symbolName, accessibilityDescription: nil) != nil,
                "\(transport) → \(transport.symbolName)")
        }
    }

    @Test func transportSymbols() {
        #expect(OutputTransport.builtInSpeakers.symbolName == "speaker.wave.2.fill")
        #expect(OutputTransport.builtInHeadphones.symbolName == "headphones")
        #expect(OutputTransport.bluetooth.symbolName == "headphones")
        #expect(OutputTransport.usb.symbolName == "cable.connector")
        #expect(OutputTransport.hdmi.symbolName == "display")
        #expect(OutputTransport.displayPort.symbolName == "display")
        #expect(OutputTransport.airPlay.symbolName == "airplay.audio")
        #expect(OutputTransport.virtual.symbolName == "waveform")
        #expect(OutputTransport.other.symbolName == "hifispeaker.fill")
    }

    /// VoiceOver adds "pop-up button" itself, so the label is just the device.
    @Test func accessibilityLabelNamesTheDevice() {
        #expect(String(localized: L10n.outputDevice(named: "AirPods Pro")) == "Output: AirPods Pro")
        #expect(String(localized: L10n.outputDevice(named: nil)) == "Output: none")
        #expect(String(localized: L10n.soundSettings) == "Sound Settings…")
    }

    @Test func soundSettingsOpensTheSoundPane() {
        #expect(OutputPicker.soundSettingsURL.absoluteString == "x-apple.systempreferences:com.apple.preference.sound")
    }

    /// The header with several devices renders at the same height as before, and the error line
    /// only adds height while it's showing.
    @Test func headerWithSeveralDevicesRenders() throws {
        let h = Harness()
        h.processes.emit([makeApp("a"), makeApp("b", objects: [43])])
        let plain = try renderedHeight(h.store)
        h.output.emitDevices([airPods, speakers, blackHole, display])
        #expect(try renderedHeight(h.store) == plain)
        h.output.selectionError = FakeError()
        h.store.selectOutput(airPods)
        #expect(try renderedHeight(h.store) > plain)
    }

    @Test func currentDeviceIsAlwaysInTheMenu() {
        // Listed: no duplicate.
        #expect(OutputMenuItems.items(devices: [airPods, speakers], current: speakers).map(\.id) == [2, 1])
        // Missing from the list (not enumerable, or the list hasn't caught up): appended so it's checked.
        #expect(OutputMenuItems.items(devices: [airPods, blackHole], current: speakers).map(\.id) == [2, 3, 1])
        #expect(OutputMenuItems.items(devices: [], current: speakers).map(\.id) == [1])
        #expect(OutputMenuItems.items(devices: [airPods], current: nil).map(\.id) == [2])
    }

    @Test func longDeviceNameTruncatesAndLeavesTheTitleRoom() {
        let long = String(repeating: "Very Long Bluetooth Speaker Name ", count: 4)
        let pill = NSHostingView(rootView: OutputPill(name: long))
        let short = NSHostingView(rootView: OutputPill(name: "AirPods Pro"))
        #expect(pill.fittingSize.width < OutputPill.maxNameWidth + 60)
        #expect(short.fittingSize.width < pill.fittingSize.width)

        let h = Harness()
        h.output.emit(OutputDevice(id: 9, uid: "long", name: long, transport: .bluetooth))
        let header = NSHostingView(rootView: MixerPopover(store: h.store, updates: UpdateHarness().checker))
        header.frame = CGRect(x: 0, y: 0, width: 340, height: 600)
        header.layoutSubtreeIfNeeded()
        #expect(header.fittingSize.width <= 340)
    }

    @Test func menuItemsRender() {
        let host = NSHostingView(
            rootView: VStack(alignment: .leading) {
                OutputMenuItems(devices: [airPods, speakers, blackHole], current: speakers, select: { _ in })
                OutputMenuItems(devices: [], current: speakers, select: { _ in })
            })
        host.frame = CGRect(x: 0, y: 0, width: 260, height: 200)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height > 40)
    }

    private func renderedHeight(_ store: MixerStore) throws -> CGFloat {
        let host = NSHostingView(rootView: MixerPopover(store: store, updates: UpdateHarness().checker))
        host.frame = CGRect(x: 0, y: 0, width: 340, height: 600)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return host.fittingSize.height
    }
}

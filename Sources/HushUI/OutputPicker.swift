import AppKit
import HushAudio
import SwiftUI

extension OutputTransport {
    /// The SF Symbol for a device connected this way, in the output menu.
    var symbolName: String {
        switch self {
        case .builtInSpeakers, .builtIn: "speaker.wave.2.fill"
        case .builtInHeadphones, .bluetooth: "headphones"
        case .usb, .thunderbolt: "cable.connector"
        case .hdmi, .displayPort: "display"
        case .airPlay: "airplay.audio"
        case .virtual: "waveform"
        case .aggregate: "square.stack.3d.up.fill"
        case .other: "hifispeaker.fill"
        }
    }
}

/// The header's output pill: a menu of output devices, the current one checked, then Sound Settings.
struct OutputPicker: View {
    let store: MixerStore

    static let soundSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.sound")!

    var body: some View {
        Menu {
            OutputMenuItems(
                devices: store.outputDevices, current: store.outputDevice, select: store.selectOutput)
            Divider()
            Button(L10n.soundSettings) { NSWorkspace.shared.open(Self.soundSettingsURL) }
        } label: {
            OutputPill(name: store.outputDevice?.name)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text(L10n.outputDevice(named: store.outputDevice?.name)))
    }
}

/// The glass pill: speaker, device name and a small chevron.
struct OutputPill: View {
    let name: String?

    var body: some View {
        Label {
            HStack(spacing: 4) {
                if let name { Text(verbatim: name) } else { Text(L10n.noOutput) }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .accessibilityHidden(true)
            }
        } icon: {
            Image(systemName: "hifispeaker.fill")
        }
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(.capsule)
        .glassEffect(.regular, in: .capsule)
    }
}

/// One checkable item per device. If the source lists nothing (it can't enumerate devices), the
/// current output still appears, checked.
struct OutputMenuItems: View {
    let devices: [OutputDevice]
    let current: OutputDevice?
    let select: (OutputDevice) -> Void

    var body: some View {
        ForEach(items) { device in
            Toggle(
                isOn: Binding(
                    get: { device.id == current?.id },
                    set: { _ in select(device) })
            ) {
                Label {
                    Text(verbatim: device.name)
                } icon: {
                    Image(systemName: device.transport.symbolName)
                }
            }
        }
    }

    private var items: [OutputDevice] {
        if devices.isEmpty, let current { [current] } else { devices }
    }
}

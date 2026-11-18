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
        .accessibilityLabel(Text(L10n.outputDevice(named: store.outputDevice?.name)))
    }
}

/// The glass pill: speaker, device name and a small chevron.
struct OutputPill: View {
    /// Longer device names truncate, so the header title always has room.
    static let maxNameWidth: CGFloat = 160

    let name: String?

    var body: some View {
        Label {
            HStack(spacing: 4) {
                Group {
                    if let name { Text(verbatim: name) } else { Text(L10n.noOutput) }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                // Hug the name up to the cap: a bare maxWidth frame would stretch to 160pt and
                // leave a gap before the chevron for shorter names.
                .frame(maxWidth: Self.maxNameWidth, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
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

/// One checkable item per device. The current output is always there and checked, even if the
/// source can't list devices or its list hasn't caught up yet.
struct OutputMenuItems: View {
    let devices: [OutputDevice]
    let current: OutputDevice?
    let select: (OutputDevice) -> Void

    var body: some View {
        ForEach(Self.items(devices: devices, current: current)) { device in
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

    static func items(devices: [OutputDevice], current: OutputDevice?) -> [OutputDevice] {
        guard let current, !devices.contains(where: { $0.id == current.id }) else { return devices }
        return devices + [current]
    }
}

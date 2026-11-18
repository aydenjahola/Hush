import HushCore
import SwiftUI

/// Settings → Levels: the "Remember levels for each output device" toggle and, while it's on, the
/// devices with saved levels, each with a Forget button. Devices are listed by the name saved with
/// their levels (the UID when there is none), so a device doesn't need to be connected to appear.
struct DeviceLevelsSettings: View {
    @Bindable var store: MixerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // VoiceOver reads the explanation as the toggle's hint, so the caption isn't read twice.
            Toggle(L10n.rememberLevelsPerDevice, isOn: $store.rememberLevelsPerDevice)
                .accessibilityHint(Text(L10n.rememberLevelsPerDeviceExplanation))
            Text(L10n.rememberLevelsPerDeviceExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        if store.rememberLevelsPerDevice {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.devicesWithSavedLevels)
                let devices = store.savedLevelDevices
                if devices.isEmpty {
                    Text(L10n.noDevicesWithSavedLevels)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(devices, id: \.uid) { device in
                        row(device)
                    }
                }
            }
        }
    }

    private func row(_ device: DeviceLevelBook.Device) -> some View {
        let label = device.name.isEmpty ? device.uid : device.name
        return HStack(spacing: 8) {
            Text(verbatim: label)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(Text(verbatim: label))
            Spacer(minLength: 8)
            Button(L10n.forget) { store.forgetLevels(forDevice: device.uid) }
                .accessibilityLabel(Text(L10n.forgetDeviceLevels(label)))
                .help(Text(L10n.forgetDeviceLevelsHelp))
        }
    }
}

import AppKit
import HushCore
import SwiftUI

package struct SettingsView: View {
    @Bindable var store: MixerStore
    @Bindable var updates: UpdateChecker

    @State private var launchAtLogin = LaunchAtLoginModel()
    let navigator: SettingsNavigator

    @State private var confirmingReset = false
    @State private var presetSheet: PresetSheet?

    package init(store: MixerStore, updates: UpdateChecker, navigator: SettingsNavigator) {
        self.store = store
        self.updates = updates
        self.navigator = navigator
    }

    package var body: some View {
        Form {
            Section(L10n.general) {
                Toggle(
                    L10n.launchAtLogin,
                    isOn: Binding(get: { launchAtLogin.state.isOn }, set: { launchAtLogin.setEnabled($0) })
                )
                .disabled(!launchAtLogin.state.isEnabled)
                .help(launchAtLogin.state.isEnabled ? Text(verbatim: "") : Text(L10n.launchAtLoginUnavailableHelp))
                if launchAtLogin.state.showsApprovalHint {
                    Text(L10n.launchAtLoginApprovalHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(L10n.openLoginItems) { launchAtLogin.openLoginItemsSettings() }
                }
                if let message = launchAtLogin.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker(L10n.maximumBoost, selection: $store.maxBoost) {
                    ForEach(BoostLimit.allCases) { limit in
                        Text(L10n.percent(limit.rawValue)).tag(limit)
                    }
                }
                .pickerStyle(.segmented)
                Toggle(L10n.showInactiveApps, isOn: $store.showInactiveApps)
                KeyboardShortcutRow()
            }

            AppearanceSettingsSection(store: store)

            PresetsSettingsSection(store: store, sheet: $presetSheet)

            Section(L10n.levels) {
                DeviceLevelsSettings(store: store)
                HiddenAppsList(store: store)
                Button(L10n.resetAllLevelsButton, role: .destructive) {
                    confirmingReset = true
                }
                .confirmationDialog(L10n.resetAllLevelsTitle, isPresented: $confirmingReset) {
                    Button(L10n.resetAllLevels, role: .destructive) { store.resetAllLevels() }
                } message: {
                    Text(
                        store.deviceLevelBook.isEmpty ? L10n.resetAllLevelsMessage : L10n.resetAllLevelsDeviceMessage)
                }
            }

            Section(L10n.updates) {
                Toggle(L10n.checkAutomatically, isOn: $updates.automaticChecks)
                HStack(spacing: 8) {
                    Button(L10n.checkNow) {
                        Task { await updates.checkNow() }
                    }
                    .disabled(updates.checkStatus == .checking)
                    updateStatus
                    Spacer(minLength: 0)
                }
            }

            Section(L10n.about) {
                LabeledContent(L10n.version, value: Self.version)
                Link(L10n.sourceCode, destination: URL(string: "https://github.com/aydenjahola/Hush")!)
                Text(L10n.licence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .modifier(PresetsNavigation(store: store, navigator: navigator, sheet: $presetSheet))
        .onAppear { launchAtLogin.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updates.checkStatus {
        case .idle:
            if let lastCheck = updates.lastUpdateCheck {
                statusText(L10n.lastChecked(lastCheck.formatted(.relative(presentation: .named))))
            }
        case .checking:
            ProgressView().controlSize(.small)
            statusText(L10n.checking)
        case .upToDate:
            statusText(L10n.upToDate)
        case .available(let version):
            statusText(L10n.updateAvailable(version.description))
            Button(L10n.download) { updates.download() }
                .buttonStyle(.link)
        case .failed:
            statusText(L10n.checkFailed)
        }
    }

    private func statusText(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private static var version: String {
        let build = BuildInfo.current
        let version = build.version ?? "dev"
        return build.isLocal ? String(localized: L10n.localVersion(version, commit: build.commit)) : version
    }
}

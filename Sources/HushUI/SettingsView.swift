import HushCore
import ServiceManagement
import SwiftUI

package struct SettingsView: View {
    @Bindable var store: MixerStore
    @Bindable var updates: UpdateChecker

    /// Read from SMAppService in onAppear, not as a `@State` initial value (evaluated on every init).
    @State private var launchAtLogin = false
    @State private var launchError: String?
    @State private var confirmingReset = false

    package init(store: MixerStore, updates: UpdateChecker) {
        self.store = store
        self.updates = updates
    }

    package var body: some View {
        Form {
            Section(L10n.general) {
                Toggle(L10n.launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError)
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
            }

            AppearanceSettingsSection(store: store)

            Section(L10n.levels) {
                Button(L10n.resetAllLevelsButton, role: .destructive) {
                    confirmingReset = true
                }
                .confirmationDialog(L10n.resetAllLevelsTitle, isPresented: $confirmingReset) {
                    Button(L10n.resetAllLevels, role: .destructive) { store.resetAllLevels() }
                } message: {
                    Text(L10n.resetAllLevelsMessage)
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
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
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

    private func setLaunchAtLogin(_ enabled: Bool) {
        // Skip echoes from reverting the toggle after a failure; they would clobber the error.
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

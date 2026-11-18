import HushCore
import ServiceManagement
import SwiftUI

public struct SettingsView: View {
    @Bindable var store: MixerStore
    @Bindable var updates: UpdateChecker

    /// Read from SMAppService in onAppear, not as a `@State` initial value (evaluated on every init).
    @State private var launchAtLogin = false
    @State private var launchError: String?
    @State private var confirmingReset = false

    public init(store: MixerStore, updates: UpdateChecker) {
        self.store = store
        self.updates = updates
    }

    public var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Maximum boost", selection: $store.maxBoost) {
                    ForEach(BoostLimit.allCases) { limit in
                        Text("\(limit.rawValue)%").tag(limit)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Show apps that aren't playing", isOn: $store.showInactiveApps)
            }

            Section("Levels") {
                Button("Reset All Levels…", role: .destructive) {
                    confirmingReset = true
                }
                .confirmationDialog("Reset all app levels?", isPresented: $confirmingReset) {
                    Button("Reset All Levels", role: .destructive) { store.resetAllLevels() }
                } message: {
                    Text("Every app goes back to 100% and unmuted.")
                }
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $updates.automaticChecks)
                HStack(spacing: 8) {
                    Button("Check Now") {
                        Task { await updates.checkNow() }
                    }
                    .disabled(updates.checkStatus == .checking)
                    updateStatus
                    Spacer(minLength: 0)
                }
            }

            Section("About") {
                LabeledContent("Version", value: Self.version)
                Link("Source code on GitHub", destination: URL(string: "https://github.com/aydenjahola/Hush")!)
                Text("Hush is free software, released under the GNU General Public License v3.0. It comes with ABSOLUTELY NO WARRANTY.")
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
                statusText("Last checked \(lastCheck.formatted(.relative(presentation: .named)))")
            }
        case .checking:
            ProgressView().controlSize(.small)
            statusText("Checking…")
        case .upToDate:
            statusText("Hush is up to date")
        case .available(let version):
            statusText("Hush \(version.description) is available")
            Button("Download") { updates.download() }
                .buttonStyle(.link)
        case .failed:
            statusText("Couldn't check for updates")
        }
    }

    private func statusText(_ text: String) -> some View {
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

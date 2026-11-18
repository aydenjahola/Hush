import HushCore
import ServiceManagement
import SwiftUI

public struct SettingsView: View {
    @Bindable var store: MixerStore

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var confirmingReset = false

    public init(store: MixerStore) {
        self.store = store
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

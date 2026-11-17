import HushCore
import ServiceManagement
import SwiftUI

/// Replaces `@State` (SwiftUI macro plugin unavailable under CLT).
@MainActor
final class SettingsModel: ObservableObject {
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var launchError: String?
    @Published var confirmingReset = false

    func refresh() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
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
}

public struct SettingsView: View {
    let store: MixerStore

    @StateObject private var model = SettingsModel()

    public init(store: MixerStore) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                    .onChange(of: model.launchAtLogin) { _, enabled in model.setLaunchAtLogin(enabled) }
                if let launchError = model.launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Maximum boost", selection: Binding(
                    get: { store.preferences.maxBoostPercent },
                    set: { store.setMaxBoost($0) }
                )) {
                    ForEach(BoostLimit.allCases) { limit in
                        Text("\(limit.rawValue)%").tag(limit)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Show apps that aren't playing", isOn: Binding(
                    get: { store.preferences.showInactiveApps },
                    set: { store.setShowInactiveApps($0) }))
            }

            Section("Levels") {
                Button("Reset All Levels…", role: .destructive) {
                    model.confirmingReset = true
                }
                .confirmationDialog("Reset all app levels?", isPresented: $model.confirmingReset) {
                    Button("Reset All Levels", role: .destructive) { store.resetAllLevels() }
                } message: {
                    Text("Every app goes back to 100% and unmuted.")
                }
            }

            Section("About") {
                LabeledContent("Version", value: Self.version)
                Link("Source code on GitHub", destination: URL(string: "https://github.com/hush-mixer/hush")!)
                Text("Hush is free software, released under the GNU General Public License v3.0. It comes with ABSOLUTELY NO WARRANTY.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear { model.refresh() }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

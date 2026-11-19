import AppKit
import HushCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Ducking: the on/off toggle, how far to lower other apps, the call apps (collapsed,
/// since the default list is long) and the apps that are never lowered.
struct DuckingSettingsSection: View {
    @Bindable var store: MixerStore

    var body: some View {
        Section(L10n.ducking) {
            VStack(alignment: .leading, spacing: 4) {
                // VoiceOver reads the explanation as the toggle's hint, so the caption isn't read twice.
                Toggle(L10n.lowerOtherAppsDuringCalls, isOn: $store.duckingEnabled)
                    .accessibilityHint(Text(L10n.duckingExplanation))
                Text(L10n.duckingExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            amountSlider
            DisclosureGroup {
                DuckingAppList(
                    store: store,
                    apps: store.duckingSettings.callApps,
                    emptyText: nil,
                    remove: store.removeCallApp,
                    add: store.addCallApp)
                Button(L10n.restoreDefaults) { store.restoreDefaultCallApps() }
                    .disabled(store.duckingSettings.usesDefaultCallApps)
                Text(L10n.callAppsExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } label: {
                LabeledContent {
                    Text(verbatim: "\(store.duckingSettings.callApps.count)")
                        .foregroundStyle(.secondary)
                } label: {
                    Text(L10n.callApps)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.neverLower)
                DuckingAppList(
                    store: store,
                    apps: store.duckingSettings.exceptions,
                    emptyText: L10n.noNeverLowerApps,
                    remove: store.removeDuckingException,
                    add: store.addDuckingException)
            }
        }
    }

    private var amountSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.lowerOtherAppsTo(store.duckingPercent))
                .monospacedDigit()
            Slider(
                value: Binding(
                    get: { Double(store.duckingPercent) },
                    set: { store.duckingPercent = Int($0.rounded()) }),
                in: Double(DuckingSettings.percentRange.lowerBound)...Double(DuckingSettings.percentRange.upperBound),
                step: Double(DuckingSettings.percentStep)
            ) {
                Text(L10n.lowerOtherAppsTo(store.duckingPercent))
            }
            .labelsHidden()
            .accessibilityValue(Text(L10n.percent(store.duckingPercent)))
        }
        .disabled(!store.duckingEnabled)
    }
}

/// One of the ducking lists: a row per app with a Remove button, then an Add App menu offering
/// the running apps not on either list and a panel to choose any app.
private struct DuckingAppList: View {
    let store: MixerStore
    let apps: [DuckingApp]
    let emptyText: LocalizedStringResource?
    let remove: (String) -> Void
    let add: (DuckingApp) -> Void

    var body: some View {
        if apps.isEmpty, let emptyText {
            Text(emptyText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        ForEach(apps) { app in
            HStack(spacing: 8) {
                Image(nsImage: store.icon(forDuckingApp: app.bundleID) ?? FallbackAppIcon.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(verbatim: app.displayName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(Text(verbatim: "\(app.displayName) (\(app.bundleID))"))
                Spacer(minLength: 8)
                Button(L10n.remove) { remove(app.bundleID) }
                    .accessibilityLabel(Text(L10n.removeApp(app.displayName)))
            }
        }
        Menu(L10n.addApp) {
            let candidates = store.duckingCandidates(excluding: listedIDs)
            if candidates.isEmpty {
                Button(L10n.noOtherRunningApps) {}
                    .disabled(true)
            }
            ForEach(candidates) { candidate in
                Button {
                    add(candidate)
                } label: {
                    Text(verbatim: candidate.displayName)
                }
            }
            Divider()
            Button(L10n.chooseAppEllipsis) {
                if let chosen = Self.chooseApp() { add(chosen) }
            }
        }
        .fixedSize()
    }

    /// Apps on either list: a call app can't also be an exception, and vice versa.
    private var listedIDs: Set<String> {
        let settings = store.duckingSettings
        return Set((settings.callApps + settings.exceptions).map(\.bundleID))
    }

    /// An open panel in /Applications for choosing one app; nil if cancelled or it has no bundle ID.
    private static func chooseApp() -> DuckingApp? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
            let bundleID = bundle.bundleIdentifier
        else { return nil }
        let name =
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return DuckingApp(bundleID: bundleID, displayName: name)
    }
}

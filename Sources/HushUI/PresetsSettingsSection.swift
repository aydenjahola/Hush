import HushCore
import SwiftUI

/// Which naming sheet Settings → Presets is showing.
enum PresetSheet: Identifiable, Equatable {
    case save
    case rename(Preset.ID)

    var id: String {
        switch self {
        case .save: "save"
        case .rename(let id): "rename-\(id.uuidString)"
        }
    }
}

/// Settings → Presets: the saved presets (name, app count, a checkmark on the active one) with
/// Apply, Rename and Delete, and a button that saves the current levels as a new preset.
struct PresetsSettingsSection: View {
    /// The section's scroll anchor, so the quick menu's "Manage Presets…" can bring it into view.
    static let anchor = "presets"

    let store: MixerStore
    @Binding var sheet: PresetSheet?

    @State private var deleting: Preset?

    var body: some View {
        Section {
            if store.presets.isEmpty {
                Text(L10n.noPresetsYet)
                    .foregroundStyle(.secondary)
            }
            ForEach(store.presets) { preset in
                row(preset, isActive: preset.id == store.activePresetID)
            }
            Button(L10n.saveCurrentLevelsAsPreset) { sheet = .save }
                .disabled(!store.controlsEnabled)
        } header: {
            Text(L10n.presets)
        } footer: {
            Text(L10n.presetsExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .id(Self.anchor)
        .confirmationDialog(
            deleting.map { L10n.deletePresetTitle($0.name) } ?? L10n.presets,
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { preset in
            Button(L10n.deletePreset, role: .destructive) { store.deletePreset(preset.id) }
            Button(L10n.cancel, role: .cancel) {}
        } message: { _ in
            Text(L10n.deletePresetMessage)
        }
    }

    private func row(_ preset: Preset, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tint)
                .opacity(isActive ? 1 : 0)
                .accessibilityLabel(Text(L10n.activePreset))
                .accessibilityHidden(!isActive)
                .help(isActive ? Text(L10n.activePreset) : Text(verbatim: ""))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: preset.name)
                Text(L10n.presetAppCount(preset.apps.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(L10n.applyPreset) { store.applyPreset(preset.id) }
                .disabled(!store.controlsEnabled)
            Menu {
                actions(for: preset)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text(L10n.presetActions))
        }
        .accessibilityElement(children: .contain)
        .contextMenu {
            Button(L10n.applyPreset) { store.applyPreset(preset.id) }
                .disabled(!store.controlsEnabled)
            actions(for: preset)
        }
    }

    @ViewBuilder
    private func actions(for preset: Preset) -> some View {
        Button(L10n.renamePresetEllipsis) { sheet = .rename(preset.id) }
        Button(L10n.deletePresetEllipsis, role: .destructive) { deleting = preset }
    }
}

/// Shows the naming sheet, and answers the quick menu's preset requests: scrolls Settings to the
/// Presets section and, for "Save Current Levels as Preset…", opens the save sheet.
struct PresetsNavigation: ViewModifier {
    let store: MixerStore
    let navigator: SettingsNavigator
    @Binding var sheet: PresetSheet?

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onChange(of: navigator.pending, initial: true) {
                    guard let destination = navigator.take() else { return }
                    if destination == .savePreset { sheet = .save }
                    // A window that's just opening lays out first, so scroll on the next turn.
                    Task { @MainActor in
                        withAnimation { proxy.scrollTo(PresetsSettingsSection.anchor, anchor: .top) }
                    }
                }
                .sheet(item: $sheet) { mode in
                    PresetNameSheet(store: store, mode: mode)
                }
        }
    }
}

/// Names a new preset, or renames one. Saving with an existing preset's name asks before
/// replacing it; renaming to a name another preset has is refused.
struct PresetNameSheet: View {
    let store: MixerStore
    let mode: PresetSheet

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var replacing: Preset?

    init(store: MixerStore, mode: PresetSheet) {
        self.store = store
        self.mode = mode
        let initial: String =
            if case .rename(let id) = mode { store.presetLibrary.preset(id)?.name ?? "" } else { "" }
        _name = State(initialValue: initial)
    }

    private var renaming: Preset.ID? {
        if case .rename(let id) = mode { id } else { nil }
    }

    private var check: PresetLibrary.NameCheck {
        store.checkPresetName(name, renaming: renaming)
    }

    private var canCommit: Bool {
        switch check {
        case .available: true
        case .taken: renaming == nil
        case .empty, .limitReached: false
        }
    }

    private var message: LocalizedStringResource? {
        switch check {
        case .taken(let existing):
            renaming == nil ? L10n.presetWillReplace(existing.name) : L10n.presetNameTaken(existing.name)
        case .limitReached:
            L10n.presetLimitReached(PresetLibrary.maxCount)
        case .empty, .available:
            nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(renaming == nil ? L10n.savePresetTitle : L10n.renamePresetTitle)
                .font(.headline)
            TextField(L10n.presetName, text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
            Text(message ?? L10n.presetName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(message == nil ? 0 : 1)
                .accessibilityHidden(message == nil)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L10n.cancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(renaming == nil ? L10n.savePreset : L10n.renamePreset, action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCommit)
            }
        }
        .padding(20)
        .frame(width: 340)
        .alert(
            replacing.map { L10n.replacePresetTitle($0.name) } ?? L10n.presets,
            isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } }),
            presenting: replacing
        ) { _ in
            Button(L10n.replacePreset, role: .destructive) {
                store.saveCurrentLevelsAsPreset(named: name)
                dismiss()
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: { _ in
            Text(L10n.replacePresetMessage)
        }
    }

    private func commit() {
        guard canCommit else { return }
        if let renaming {
            store.renamePreset(renaming, to: name)
            dismiss()
            return
        }
        if case .taken(let existing) = check {
            replacing = existing
            return
        }
        store.saveCurrentLevelsAsPreset(named: name)
        dismiss()
    }
}

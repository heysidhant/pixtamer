import PixtamerKit
import SwiftUI

/// Screen E: create, rename, duplicate, apply, update and delete presets.
struct PresetManagerView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?
    @State private var nameSheet: NameSheet?
    @State private var pendingDelete: ExportPreset?

    enum NameSheet: Identifiable {
        case create
        case rename(ExportPreset)
        var id: String {
            switch self {
            case .create: "create"
            case .rename(let p): "rename-\(p.id)"
            }
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(model.presetLibrary.presets, selection: $selection) { preset in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(preset.name).lineLimit(1)
                            if preset.id == model.appliedPresetID {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor).accessibilityLabel("Applied")
                            }
                        }
                        Text(preset.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.vertical, 2)
                    .tag(preset.id)
                    .contextMenu { contextMenu(for: preset) }
                }
                .overlay {
                    if model.presetLibrary.presets.isEmpty {
                        ContentUnavailableView("No Presets", systemImage: "slider.horizontal.3", description: Text("Save the current export settings to reuse them later."))
                    }
                }
                Divider()
                HStack(spacing: 4) {
                    Button { nameSheet = .create } label: { Image(systemName: "plus") }
                        .help("New preset from the current batch settings")
                        .accessibilityLabel("New preset")
                    Button { if let preset = selectedPreset { pendingDelete = preset } } label: { Image(systemName: "minus") }
                        .disabled(selectedPreset == nil)
                        .help("Delete preset")
                        .accessibilityLabel("Delete preset")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)

            Group {
                if let preset = selectedPreset {
                    PresetDetail(preset: preset, rename: { nameSheet = .rename(preset) }, delete: { pendingDelete = preset })
                } else {
                    ContentUnavailableView("Select a Preset", systemImage: "slider.horizontal.3", description: Text("Presets store format, quality, size, naming, subfolder, metadata and collision settings."))
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Presets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { nameSheet = .create } label: { Label("New Preset", systemImage: "plus") }
                    .help("Save the current batch settings as a preset")
            }
        }
        .onAppear { if selection == nil { selection = model.appliedPresetID ?? model.presetLibrary.presets.first?.id } }
        .sheet(item: $nameSheet) { sheet in
            switch sheet {
            case .create:
                PresetNameSheet(
                    title: "New Preset from Current Settings",
                    actionTitle: "Save",
                    initialName: "",
                    validate: { model.presetLibrary.validateName($0) },
                    commit: { name in selection = (try? model.saveCurrentSettingsAsPreset(named: name))?.id }
                )
            case .rename(let preset):
                PresetNameSheet(
                    title: "Rename Preset",
                    actionTitle: "Rename",
                    initialName: preset.name,
                    validate: { model.presetLibrary.validateName($0, excluding: preset.id) },
                    commit: { try? model.renamePreset(preset.id, to: $0) }
                )
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { preset in
            Button("Delete Preset", role: .destructive) {
                model.deletePreset(preset.id)
                if selection == preset.id { selection = model.presetLibrary.presets.first?.id }
            }
        } message: { _ in
            Text("Exported files are not affected.")
        }
    }

    private var selectedPreset: ExportPreset? {
        selection.flatMap { model.presetLibrary.preset($0) }
    }

    @ViewBuilder
    private func contextMenu(for preset: ExportPreset) -> some View {
        Button("Apply to Batch") { model.applyPreset(preset.id) }
        Button("Duplicate") { selection = model.duplicatePreset(preset.id)?.id }
        Button("Rename…") { nameSheet = .rename(preset) }
        Divider()
        Button("Delete…", role: .destructive) { pendingDelete = preset }
    }
}

private struct PresetDetail: View {
    @Environment(AppModel.self) private var model
    let preset: ExportPreset
    let rename: () -> Void
    let delete: () -> Void
    @State private var confirmUpdate = false

    var body: some View {
        let s = preset.settings
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.name).font(.title2.weight(.semibold))
                    Text("Updated \(preset.updatedAt.formatted(date: .abbreviated, time: .shortened))" + (preset.lastUsedAt.map { " · Last used \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let capabilities = model.capabilities, !capabilities.isAvailable(s.format) {
                    Label("\(s.format.displayName) export isn’t available on this Mac.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section("Recipe") {
                LabeledContent("Format", value: s.formatSummary)
                LabeledContent("Size", value: s.resize.summary)
                if s.resize.mode != .original {
                    LabeledContent("Upscaling", value: s.resize.allowUpscale ? "Allowed" : "Off")
                }
                LabeledContent("File names", value: namingSummary(s.naming))
                LabeledContent("Subfolder", value: s.subfolder.mode == .custom ? s.subfolder.customName : s.subfolder.mode.displayName)
                LabeledContent("If a file exists", value: s.collisionPolicy.displayName)
                LabeledContent("Metadata", value: s.effectiveMetadata.displayName)
            }
            Section {
                HStack {
                    Button("Apply to Batch") {
                        model.applyPreset(preset.id)
                        model.sidebarSelection = .batch
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Update from Current Settings…") { confirmUpdate = true }
                        .disabled(model.settings == preset.settings)
                        .help("Replace this preset’s recipe with the settings currently in the batch inspector")
                }
                HStack {
                    Button("Duplicate") { model.duplicatePreset(preset.id) }
                    Button("Rename…", action: rename)
                    Button("Set as Default") { model.setPresetAsDefault(preset.id) }
                        .disabled(model.preferences.defaultExportSettings == preset.settings)
                        .help("Use this recipe for new batches when Pixtamer opens")
                    Spacer()
                    Button("Delete…", role: .destructive, action: delete)
                }
            }
            if model.presetsReadOnly {
                Label("Presets were saved by a newer version of Pixtamer. Changes won’t be saved.", systemImage: "lock")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Replace the recipe in “\(preset.name)”?", isPresented: $confirmUpdate) {
            Button("Update Preset") { model.updatePresetFromCurrentSettings(preset.id) }
        } message: {
            Text("The preset will use the settings currently in the batch inspector: \(model.settings.summary).")
        }
    }

    private func namingSummary(_ rule: FilenameRule) -> String {
        let base: String = switch rule.mode {
        case .original: "Original name"
        case .suffix: "Suffix “\(rule.suffix)”"
        case .template: rule.template
        }
        return rule.webSafe ? "\(base), web-safe" : base
    }
}

import PixtamerKit
import SwiftUI

/// Screen C: the export recipe for the whole batch.
struct ExportInspectorView: View {
    @Environment(AppModel.self) private var model
    @State private var isSavingPreset = false

    var body: some View {
        @Bindable var model = model
        let issues = model.validationIssues
        Form {
            if let selected = singleSelection {
                SelectedImageSection(item: selected)
            }

            PresetSection(isSavingPreset: $isSavingPreset)

            Section("Format") {
                if model.availableFormats.isEmpty {
                    LabeledContent("Format") { ProgressView().controlSize(.small) }
                } else {
                    Picker("Format", selection: $model.settings.format) {
                        ForEach(model.availableFormats) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Caption(model.settings.format.summary)
                if model.settings.format == .webp {
                    Toggle("Lossless", isOn: $model.settings.webpLossless)
                }
                if model.settings.format.usesQuality(webpLossless: model.settings.webpLossless) {
                    QualityControl(quality: $model.settings.quality)
                } else {
                    Caption("Lossless: every pixel is kept. Quality doesn’t apply.")
                }
                IssueList(issues: issues.messages(for: .format) + issues.messages(for: .quality))
            }

            ResizeSection(issues: issues.messages(for: .resize) + issues.messages(for: .widths))

            NamingSection(issues: issues.messages(for: .naming))

            DestinationSection(issues: issues.messages(for: .subfolder))

            Section("Metadata") {
                Picker("Metadata", selection: $model.settings.metadata) {
                    ForEach(MetadataPolicy.allCases) { Text($0.displayName).tag($0) }
                }
                .disabled(!model.settings.format.supportsMetadata)
                if model.settings.format.supportsMetadata {
                    Caption(model.settings.metadata.explanation)
                } else {
                    Caption("\(model.settings.format.displayName) export always removes metadata in this version. Colours are converted to sRGB.")
                }
                IssueList(issues: issues.messages(for: .metadata).filter { _ in model.settings.format.supportsMetadata })
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isSavingPreset) {
            PresetNameSheet(
                title: "Save as Preset",
                actionTitle: "Save",
                initialName: "",
                validate: { model.presetLibrary.validateName($0) },
                commit: { _ = try? model.saveCurrentSettingsAsPreset(named: $0) }
            )
        }
    }

    private var singleSelection: QueueItem? {
        guard model.batch.selection.count == 1, let id = model.batch.selection.first else { return nil }
        return model.batch.item(id)
    }
}

// MARK: - Sections

private struct SelectedImageSection: View {
    @Environment(AppModel.self) private var model
    let item: QueueItem

    var body: some View {
        Section("Selected Image") {
            HStack(alignment: .top, spacing: 10) {
                ThumbnailView(url: item.input.url, side: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.input.fileName).font(.headline).lineLimit(2).truncationMode(.middle)
                    Text("\(item.input.typeDisplayName) · \(item.input.pixelSize.description) · \(Formatting.bytes(item.input.fileSize))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    if let profile = item.input.colorProfileName {
                        Text(profile).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(item.input.warnings, id: \.self) { warning in
                Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button("Preview…") { model.previewItemID = item.id }
        }
    }
}

private struct PresetSection: View {
    @Environment(AppModel.self) private var model
    @Binding var isSavingPreset: Bool

    var body: some View {
        Section("Preset") {
            HStack {
                Menu {
                    ForEach(model.presetLibrary.presets) { preset in
                        Button {
                            model.applyPreset(preset.id)
                        } label: {
                            Text(preset.name)
                            Text(preset.summary)
                        }
                    }
                    if model.presetLibrary.presets.isEmpty {
                        Text("No presets yet")
                    }
                    Divider()
                    Button("Reset to Default Settings") { model.resetBatchSettingsToDefaults() }
                } label: {
                    Text(presetLabel).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Apply preset. Current: \(presetLabel)")
                Spacer()
                Button("Save…") { isSavingPreset = true }
                    .help("Save these settings as a new preset")
            }
        }
    }

    private var presetLabel: String {
        guard let preset = model.appliedPreset else { return "Custom settings" }
        return model.settingsDifferFromAppliedPreset ? "\(preset.name) (edited)" : preset.name
    }
}

private struct QualityControl: View {
    @Binding var quality: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Quality") {
                HStack {
                    Slider(value: Binding(get: { Double(quality) }, set: { quality = Int($0.rounded()) }), in: 1...100)
                        .accessibilityValue("\(quality)")
                    Text("\(quality)")
                        .monospacedDigit()
                        .frame(width: 28, alignment: .trailing)
                }
            }
            Caption("Higher keeps more detail. The size saved depends on each image.")
        }
    }
}

private struct ResizeSection: View {
    @Environment(AppModel.self) private var model
    let issues: [ValidationIssue]

    var body: some View {
        @Bindable var model = model
        Section("Size") {
            Picker("Resize", selection: $model.settings.resize.mode) {
                ForEach(ResizeSettings.Mode.allCases) { Text($0.displayName).tag($0) }
            }
            switch model.settings.resize.mode {
            case .original:
                Caption("Pixel dimensions stay the same.")
            case .fit:
                OptionalPixelField(title: "Max width", value: $model.settings.resize.maxWidth)
                OptionalPixelField(title: "Max height", value: $model.settings.resize.maxHeight)
                Caption("Scales down to fit. Aspect ratio is always kept. Leave a field empty for no limit.")
            case .exact:
                PixelField(title: "Width", value: $model.settings.resize.exactWidth)
                PixelField(title: "Height", value: $model.settings.resize.exactHeight)
                Toggle("Preserve aspect ratio", isOn: $model.settings.resize.preserveAspectRatio)
                Caption(model.settings.resize.preserveAspectRatio
                    ? "Fills the size and crops the overflow from the centre."
                    : "Stretches each image to exactly this size.")
            case .widths:
                WidthsEditor(widths: $model.settings.resize.widths)
                Caption("Each image is exported once per width. Heights follow the aspect ratio.")
            }
            if model.settings.resize.mode != .original {
                Toggle("Do not upscale", isOn: Binding(
                    get: { !model.settings.resize.allowUpscale },
                    set: { model.settings.resize.allowUpscale = !$0 }
                ))
                .help("When on, outputs are never larger than the source. Sizes that would need upscaling are skipped and reported.")
            }
            if let note = upscaleNote {
                Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
            IssueList(issues: issues)
        }
    }

    /// Explains skipped variants for the current queue, before export.
    private var upscaleNote: String? {
        guard !model.batch.isEmpty, !model.settings.resize.allowUpscale else { return nil }
        var skipped = 0
        for item in model.batch.items {
            skipped += ResizePlanner.variants(for: item.input.pixelSize, settings: model.settings.resize).filter {
                if case .skip = $0 { true } else { false }
            }.count
        }
        guard skipped > 0 else { return nil }
        return "\(Formatting.count(skipped, "output")) will be skipped because the source is too small."
    }
}

private struct NamingSection: View {
    @Environment(AppModel.self) private var model
    let issues: [ValidationIssue]

    var body: some View {
        @Bindable var model = model
        Section("File Names") {
            Picker("Name", selection: $model.settings.naming.mode) {
                ForEach(FilenameRule.Mode.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            switch model.settings.naming.mode {
            case .original:
                EmptyView()
            case .suffix:
                TextField("Suffix", text: $model.settings.naming.suffix, prompt: Text("-web"))
            case .template:
                HStack {
                    TextField("Template", text: $model.settings.naming.template, prompt: Text("{name}-{width}w"))
                        .font(.body.monospaced())
                    Menu {
                        ForEach(FilenameToken.allCases, id: \.self) { token in
                            Button("\(token.placeholder) — \(token.help)") {
                                model.settings.naming.template += token.placeholder
                            }
                        }
                    } label: {
                        Image(systemName: "curlybraces")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Insert a token")
                    .accessibilityLabel("Insert token")
                }
            }
            Toggle("Web-safe names", isOn: $model.settings.naming.webSafe)
                .help("Lowercase letters, numbers and hyphens only, e.g. “Product Photo.JPG” → “product-photo.webp”.")
            if model.settings.resize.mode == .widths && model.settings.naming.mode != .template {
                Caption("The width is added to each name, e.g. -960w.")
            }
            FilenamePreview()
            IssueList(issues: issues)
        }
    }
}

private struct DestinationSection: View {
    @Environment(AppModel.self) private var model
    let issues: [ValidationIssue]

    var body: some View {
        @Bindable var model = model
        Section("Destination") {
            LabeledContent("Folder") {
                HStack {
                    if let name = model.destination.displayName {
                        Label(name, systemImage: "folder.fill")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(model.destination.url?.path ?? "")
                    } else {
                        Text("Not chosen").foregroundStyle(.secondary)
                    }
                    Button("Choose…") { model.chooseDestination() }
                }
            }
            Picker("Subfolder", selection: $model.settings.subfolder.mode) {
                ForEach(SubfolderRule.Mode.allCases) { Text($0.displayName).tag($0) }
            }
            if model.settings.subfolder.mode == .custom {
                TextField("Subfolder name", text: $model.settings.subfolder.customName)
            }
            Picker("If a file exists", selection: $model.settings.collisionPolicy) {
                ForEach(CollisionPolicy.allCases) { Text($0.displayName).tag($0) }
            }
            Caption(model.settings.collisionPolicy.explanation)
            IssueList(issues: issues)
        }
    }
}

// MARK: - Small components

struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct IssueList: View {
    let issues: [ValidationIssue]

    var body: some View {
        ForEach(issues) { issue in
            Label(issue.message, systemImage: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(issue.severity == .error ? .red : .orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("\(issue.severity == .error ? "Error" : "Warning"): \(issue.message)")
        }
    }
}

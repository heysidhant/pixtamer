import PixtamerKit
import SwiftUI

/// Screen H: defaults and preferences. Used both in the sidebar and the Settings window (⌘,).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Format", selection: defaults(\.format)) {
                    ForEach(model.availableFormats.isEmpty ? OutputFormat.allCases : model.availableFormats) { Text($0.displayName).tag($0) }
                }
                if model.preferences.defaultExportSettings.format.usesQuality(webpLossless: model.preferences.defaultExportSettings.webpLossless) {
                    LabeledContent("Quality") {
                        HStack {
                            Slider(value: Binding(
                                get: { Double(model.preferences.defaultExportSettings.quality) },
                                set: { model.preferences.defaultExportSettings.quality = Int($0.rounded()); model.savePreferences() }
                            ), in: 1...100)
                            Text("\(model.preferences.defaultExportSettings.quality)").monospacedDigit().frame(width: 28, alignment: .trailing)
                        }
                    }
                }
                Picker("Resize", selection: defaults(\.resize.mode)) {
                    ForEach(ResizeSettings.Mode.allCases) { Text($0.displayName).tag($0) }
                }
                if model.preferences.defaultExportSettings.resize.mode == .fit {
                    OptionalPixelField(title: "Max width", value: defaults(\.resize.maxWidth))
                }
                Toggle("Do not upscale", isOn: Binding(
                    get: { !model.preferences.defaultExportSettings.resize.allowUpscale },
                    set: { model.preferences.defaultExportSettings.resize.allowUpscale = !$0; model.savePreferences() }
                ))
                Picker("If a file exists", selection: defaults(\.collisionPolicy)) {
                    ForEach(CollisionPolicy.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Metadata", selection: defaults(\.metadata)) {
                    ForEach(MetadataPolicy.allCases) { Text($0.displayName).tag($0) }
                }
                HStack {
                    Button("Use Current Batch Settings") { model.useCurrentSettingsAsDefault() }
                    Button("Apply Defaults to Batch") { model.resetBatchSettingsToDefaults() }
                }
            } header: {
                Text("Defaults for New Batches")
            } footer: {
                Text("Loaded when Pixtamer opens and by “Reset to Default Settings”. Changing them does not alter the current batch.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Export Folder") {
                Picker("When exporting", selection: Binding(
                    get: { model.preferences.destinationBehavior },
                    set: { model.setDestinationBehavior($0) }
                )) {
                    ForEach(AppPreferences.DestinationBehavior.allCases) { Text($0.displayName).tag($0) }
                }
                Caption(model.preferences.destinationBehavior == .rememberLast
                    ? "Pixtamer keeps access to the last folder you chose so it is ready after relaunch. No other folders are accessible."
                    : "You’re asked for a folder on the first export after launch. Pixtamer keeps no access to folders after you quit.")
                if model.preferences.destinationBehavior == .rememberLast, let name = model.destination.displayName {
                    LabeledContent("Remembered folder", value: name)
                }
            }

            Section("Importing") {
                Toggle("Include images in subfolders", isOn: Binding(
                    get: { model.preferences.includeSubfolders },
                    set: { model.preferences.includeSubfolders = $0; model.savePreferences() }
                ))
            }

            Section("Appearance") {
                Picker("Appearance", selection: Binding(
                    get: { model.preferences.appearance },
                    set: { model.setAppearance($0) }
                )) {
                    ForEach(AppPreferences.Appearance.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button("Reset to Defaults…", role: .destructive) { confirmReset = true }
            } footer: {
                Text("Settings are stored on this Mac only. Pixtamer has no account, analytics or network access.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all settings to defaults?", isPresented: $confirmReset) {
            Button("Reset Settings", role: .destructive) { model.resetPreferencesToDefaults() }
        } message: {
            Text("Default export settings, export folder behaviour, import and appearance options are reset. Presets, the current batch and exported files are not affected.")
        }
    }

    /// Binding into the default export settings that saves on every change.
    private func defaults<T>(_ keyPath: WritableKeyPath<ExportSettings, T>) -> Binding<T> {
        Binding(
            get: { model.preferences.defaultExportSettings[keyPath: keyPath] },
            set: {
                model.preferences.defaultExportSettings[keyPath: keyPath] = $0
                model.savePreferences()
            }
        )
    }
}

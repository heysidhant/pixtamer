import Foundation
import PixtamerKit

extension AppModel {
    @discardableResult
    func saveCurrentSettingsAsPreset(named name: String) throws(PresetError) -> ExportPreset {
        let preset = try presetLibrary.create(name: name, settings: settings)
        appliedPresetID = preset.id
        persistPresets()
        return preset
    }

    func applyPreset(_ id: UUID) {
        guard let preset = presetLibrary.preset(id) else { return }
        if let capabilities, !capabilities.isAvailable(preset.settings.format) {
            notice = AppNotice(
                title: "\(preset.settings.format.displayName) isn’t available",
                message: "“\(preset.name)” exports \(preset.settings.format.displayName), which this Mac can’t write. Its other settings were applied; choose another format."
            )
        }
        settings = preset.settings
        appliedPresetID = id
        presetLibrary.markUsed(id)
        persistPresets()
    }

    func renamePreset(_ id: UUID, to name: String) throws(PresetError) {
        try presetLibrary.rename(id, to: name)
        persistPresets()
    }

    @discardableResult
    func duplicatePreset(_ id: UUID) -> ExportPreset? {
        let copy = try? presetLibrary.duplicate(id)
        persistPresets()
        return copy
    }

    func deletePreset(_ id: UUID) {
        presetLibrary.delete(id)
        if appliedPresetID == id { appliedPresetID = nil }
        persistPresets()
    }

    func updatePresetFromCurrentSettings(_ id: UUID) {
        try? presetLibrary.updateSettings(id, settings: settings)
        appliedPresetID = id
        persistPresets()
    }

    func setPresetAsDefault(_ id: UUID) {
        guard let preset = presetLibrary.preset(id) else { return }
        preferences.defaultExportSettings = preset.settings
        savePreferences()
    }

    func persistPresets() {
        guard !presetsReadOnly else { return }
        do {
            try presetStore.save(presetLibrary)
        } catch {
            notice = AppNotice(title: "Presets couldn’t be saved", message: "Your changes are kept until you quit. (\(error.localizedDescription))")
        }
    }
}

extension AppModel {
    func savePreferences() {
        do {
            try preferencesStore.save(preferences)
        } catch {
            notice = AppNotice(title: "Settings couldn’t be saved", message: error.localizedDescription)
        }
    }

    func setDestinationBehavior(_ behavior: AppPreferences.DestinationBehavior) {
        preferences.destinationBehavior = behavior
        switch behavior {
        case .rememberLast:
            preferences.rememberedDestinationBookmark = destination.makeBookmark()
        case .askEachTime:
            // Drop persistent access as soon as it is no longer needed.
            preferences.rememberedDestinationBookmark = nil
        }
        savePreferences()
    }

    func setAppearance(_ appearance: AppPreferences.Appearance) {
        preferences.appearance = appearance
        applyAppearance()
        savePreferences()
    }

    func useCurrentSettingsAsDefault() {
        preferences.defaultExportSettings = settings
        savePreferences()
    }

    func resetBatchSettingsToDefaults() {
        settings = preferences.defaultExportSettings
        appliedPresetID = nil
    }

    func resetPreferencesToDefaults() {
        preferences = AppPreferences()
        applyAppearance()
        savePreferences()
    }

    func clearRecentExports() {
        recents.clear()
        try? recentsStore.save(recents)
    }
}

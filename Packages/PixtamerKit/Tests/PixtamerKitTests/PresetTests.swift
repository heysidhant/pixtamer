import Foundation
import Testing
@testable import PixtamerKit

@Suite("Preset library rules")
struct PresetLibraryTests {
    @Test func createValidatesNames() throws {
        var library = PresetLibrary()
        try library.create(name: "  Shopify  ", settings: ExportSettings())
        #expect(library.presets.map(\.name) == ["Shopify"])
        #expect(throws: PresetError.invalidName(.duplicate)) { try library.create(name: "shopify", settings: ExportSettings()) }
        #expect(throws: PresetError.invalidName(.empty)) { try library.create(name: "   ", settings: ExportSettings()) }
        #expect(throws: PresetError.invalidName(.tooLong(limit: PresetLibrary.maxNameLength))) {
            try library.create(name: String(repeating: "x", count: 61), settings: ExportSettings())
        }
    }

    @Test func renameAllowsSameNameForSamePreset() throws {
        var library = PresetLibrary()
        let a = try library.create(name: "A", settings: ExportSettings())
        try library.create(name: "B", settings: ExportSettings())
        try library.rename(a.id, to: "a")
        #expect(library.preset(a.id)?.name == "a")
        #expect(throws: PresetError.invalidName(.duplicate)) { try library.rename(a.id, to: "B") }
    }

    @Test func duplicateDoesNotMutateOriginal() throws {
        var library = PresetLibrary()
        let original = try library.create(name: "Web", settings: ExportSettings(format: .jpeg, quality: 70))
        let copy = try library.duplicate(original.id)
        let copy2 = try library.duplicate(original.id)
        #expect(copy.name == "Web copy")
        #expect(copy2.name == "Web copy 2")
        #expect(copy.id != original.id)
        try library.updateSettings(copy.id, settings: ExportSettings(format: .png))
        #expect(library.preset(original.id)?.settings.format == .jpeg)
        #expect(library.preset(original.id)?.settings.quality == 70)
    }

    @Test func deleteRemovesOnlyThatPreset() throws {
        var library = PresetLibrary()
        let a = try library.create(name: "A", settings: ExportSettings())
        let b = try library.create(name: "B", settings: ExportSettings())
        library.delete(a.id)
        #expect(library.presets.map(\.id) == [b.id])
    }

    @Test func startersAreValid() {
        let starters = PresetLibrary.starters()
        #expect(starters.presets.count == 3)
        for preset in starters.presets {
            #expect(!preset.settings.validate(availableFormats: OutputFormat.allCases).hasErrors, "\(preset.name)")
        }
    }
}

@Suite("Preset and preference persistence")
struct PersistenceTests {
    @Test func presetsSurviveRelaunch() throws {
        let dir = try FixtureDirectory()
        let first = PresetStore(directory: dir.url).load()
        #expect(first.library.presets.count == 3, "starters on first launch")

        var library = first.library
        let custom = try library.create(name: "Client — Hero", settings: ExportSettings(
            format: .avif, quality: 55,
            resize: ResizeSettings(mode: .widths, widths: [640, 1280]),
            naming: FilenameRule(mode: .template, template: "{name}_{width}"),
            subfolder: SubfolderRule(mode: .width),
            metadata: .keepWithoutLocation,
            collisionPolicy: .skip
        ))
        try PresetStore(directory: dir.url).save(library)

        // A brand-new store instance simulates quitting and relaunching.
        let reloaded = PresetStore(directory: dir.url).load()
        #expect(reloaded.notice == nil)
        // Dates are stored as ISO-8601 (second precision), so compare everything else exactly.
        #expect(reloaded.library.presets.map(\.id) == library.presets.map(\.id))
        #expect(reloaded.library.presets.map(\.name) == library.presets.map(\.name))
        #expect(reloaded.library.presets.map(\.settings) == library.presets.map(\.settings))
        #expect(reloaded.library.preset(custom.id)?.settings.resize.widths == [640, 1280])
    }

    @Test func deletingAllPresetsDoesNotRestoreStarters() throws {
        let dir = try FixtureDirectory()
        let store = PresetStore(directory: dir.url)
        var library = store.load().library
        for preset in library.presets { library.delete(preset.id) }
        try store.save(library)
        #expect(PresetStore(directory: dir.url).load().library.presets.isEmpty)
    }

    @Test func corruptFileIsMovedAsideAndStartersRestored() throws {
        let dir = try FixtureDirectory()
        try Data("{ not json".utf8).write(to: dir.url.appendingPathComponent("presets.json"))
        let loaded = PresetStore(directory: dir.url).load()
        #expect(loaded.library.presets.count == 3)
        #expect(loaded.notice != nil)
        #expect(try dir.contents().contains { $0.hasPrefix("presets.corrupt-") })
    }

    @Test func newerSchemaIsReadOnly() throws {
        let dir = try FixtureDirectory()
        let json = """
        {"schemaVersion": 99, "payload": {"presets": [{"id": "6D2B7C4E-3F1A-4B8E-9C11-0A5E2F7B1D09", "name": "Future", "settings": {"format": "jxl", "quality": 70, "futureField": true}}]}}
        """
        try Data(json.utf8).write(to: dir.url.appendingPathComponent("presets.json"))
        let loaded = PresetStore(directory: dir.url).load()
        #expect(loaded.readOnly)
        #expect(loaded.library.presets.first?.name == "Future")
        #expect(loaded.library.presets.first?.settings.format == ExportSettings().format, "unknown format falls back to default")
        #expect(loaded.library.presets.first?.settings.quality == 70)
    }

    @Test func settingsDecodeWithMissingFields() throws {
        let json = #"{"format": "jpeg"}"#
        let settings = try JSONDecoder().decode(ExportSettings.self, from: Data(json.utf8))
        #expect(settings.format == .jpeg)
        #expect(settings.quality == ExportSettings.defaultQuality)
        #expect(settings.resize == ResizeSettings())
        #expect(settings.collisionPolicy == .rename)
    }

    @Test func preferencesRoundTrip() throws {
        let dir = try FixtureDirectory()
        let store = VersionedJSONStore<AppPreferences>(fileURL: dir.url.appendingPathComponent("preferences.json"), schemaVersion: AppPreferences.schemaVersion)
        var prefs = AppPreferences()
        prefs.appearance = .dark
        prefs.destinationBehavior = .rememberLast
        prefs.defaultExportSettings.format = .png
        try store.save(prefs)
        guard case .loaded(let loaded) = store.load() else { Issue.record("expected loaded"); return }
        #expect(loaded == prefs)
    }

    @Test func recentHistoryIsCapped() {
        var history = RecentExportHistory()
        for i in 0..<40 {
            history.record(RecentExport(date: Date(timeIntervalSince1970: Double(i)), destinationPath: "/x", settingsSummary: "", summary: BatchSummary(), cancelled: false))
        }
        #expect(history.entries.count == RecentExportHistory.limit)
        #expect(history.entries.first?.date == Date(timeIntervalSince1970: 39))
    }
}

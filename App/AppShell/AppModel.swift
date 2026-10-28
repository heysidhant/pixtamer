import AppKit
import Observation
import PixtamerKit
import UniformTypeIdentifiers

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case batch, presets, recents, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .batch: "Batch"
        case .presets: "Presets"
        case .recents: "Recent Exports"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .batch: "photo.stack"
        case .presets: "slider.horizontal.3"
        case .recents: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

/// Alert content shown by the main window.
struct AppNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct PresentedImportReport: Identifiable {
    let id = UUID()
    let report: ImportReport
}

/// Export waiting for the user to confirm replacing existing files.
struct PendingReplacement: Identifiable {
    let id = UUID()
    let plan: ExportPlan
    let count: Int
}

/// Root application state. Owns the stores and composes the smaller models; feature logic lives
/// in the `AppModel+…` extensions.
@MainActor
@Observable
final class AppModel {
    // Persistence
    let presetStore: PresetStore
    let preferencesStore: VersionedJSONStore<AppPreferences>
    let recentsStore: VersionedJSONStore<RecentExportHistory>

    // Processing
    let exporter = BatchExporter()
    let processor = ImageProcessor()

    // State
    private(set) var capabilities: FormatCapabilities?
    let batch = BatchModel()
    let destination = DestinationFolder()
    var settings: ExportSettings
    var appliedPresetID: UUID?
    var presetLibrary: PresetLibrary
    var presetsReadOnly: Bool
    var preferences: AppPreferences
    var recents: RecentExportHistory
    var recentFailures: [ExportFailure] = []

    // Navigation and presentation
    var sidebarSelection: SidebarItem = .batch
    var showInspector = true
    var previewItemID: QueueItem.ID?
    var importReport: PresentedImportReport?
    var importBanner: String?
    var exportSession: ExportSession?
    var pendingReplacement: PendingReplacement?
    var notice: AppNotice?

    init(storageDirectory: URL = StorageLocation.applicationSupport()) {
        presetStore = PresetStore(directory: storageDirectory)
        preferencesStore = VersionedJSONStore(fileURL: storageDirectory.appendingPathComponent("preferences.json"), schemaVersion: AppPreferences.schemaVersion)
        recentsStore = VersionedJSONStore(fileURL: storageDirectory.appendingPathComponent("recent-exports.json"), schemaVersion: RecentExportHistory.schemaVersion)

        let loadedPresets = presetStore.load()
        presetLibrary = loadedPresets.library
        presetsReadOnly = loadedPresets.readOnly

        var startupNotices: [String] = loadedPresets.notice.map { [$0] } ?? []
        let loadedPreferences: AppPreferences
        switch preferencesStore.load() {
        case .loaded(let prefs), .loadedReadOnly(let prefs, _):
            loadedPreferences = prefs
        case .missing:
            loadedPreferences = AppPreferences()
        case .recoveredFromCorruption:
            loadedPreferences = AppPreferences()
            startupNotices.append("Settings were damaged and have been reset to defaults.")
        }
        preferences = loadedPreferences
        switch recentsStore.load() {
        case .loaded(let history), .loadedReadOnly(let history, _): recents = history
        default: recents = RecentExportHistory()
        }
        settings = loadedPreferences.defaultExportSettings

        if !startupNotices.isEmpty {
            notice = AppNotice(title: "Pixtamer restored its data", message: startupNotices.joined(separator: "\n\n"))
        }
        restoreRememberedDestination()
        Task { await loadCapabilities() }
    }

    // MARK: Capabilities

    func loadCapabilities() async {
        guard capabilities == nil else { return }
        let detected = await FormatCapabilities.detected()
        capabilities = detected
        // A preset or default saved on another Mac may name a format unavailable here.
        if !detected.isAvailable(settings.format), let fallback = detected.availableFormats.first {
            settings.format = fallback
        }
    }

    func readyCapabilities() async -> FormatCapabilities {
        if let capabilities { return capabilities }
        await loadCapabilities()
        // loadCapabilities always sets a value; the empty fallback only satisfies the type system.
        return capabilities ?? FormatCapabilities(probes: [], readableTypeIdentifiers: [])
    }

    var availableFormats: [OutputFormat] { capabilities?.availableFormats ?? [] }

    var readableContentTypes: [UTType] {
        (capabilities?.readableTypeIdentifiers ?? []).compactMap { UTType($0) }
    }

    // MARK: Validation

    var validationIssues: [ValidationIssue] {
        settings.validate(availableFormats: capabilities?.availableFormats ?? OutputFormat.allCases)
    }

    /// Reasons export can't start, in priority order. Empty when ready.
    var exportBlockers: [String] {
        var reasons: [String] = []
        if batch.isEmpty { reasons.append("Add images to export.") }
        if capabilities == nil { reasons.append("Checking available formats…") }
        if let error = validationIssues.first(where: { $0.severity == .error }) { reasons.append(error.message) }
        if exportSession?.isRunning == true { reasons.append("An export is already running.") }
        return reasons
    }

    var canStartExport: Bool { exportBlockers.isEmpty }

    /// Number of files the current settings would write for the whole queue.
    var plannedOutputCount: Int {
        batch.items.reduce(0) { count, item in
            count + ResizePlanner.variants(for: item.input.pixelSize, settings: settings.resize).filter {
                if case .render = $0 { true } else { false }
            }.count
        }
    }

    var appliedPreset: ExportPreset? {
        appliedPresetID.flatMap { presetLibrary.preset($0) }
    }

    var settingsDifferFromAppliedPreset: Bool {
        guard let preset = appliedPreset else { return false }
        return preset.settings != settings
    }

    // MARK: Appearance

    func applyAppearance() {
        switch preferences.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: Info

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    var diagnosticsReport: String {
        guard let capabilities else { return "Format detection has not finished yet." }
        return Diagnostics.report(
            appVersion: appVersion,
            build: appBuild,
            capabilities: capabilities,
            lastSummary: recents.entries.first?.summary,
            recentFailures: recentFailures
        )
    }
}

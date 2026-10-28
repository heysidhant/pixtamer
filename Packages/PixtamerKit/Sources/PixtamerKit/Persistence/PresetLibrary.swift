import Foundation

public struct ExportPreset: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var settings: ExportSettings
    public var createdAt: Date
    public var updatedAt: Date
    public var lastUsedAt: Date?

    public init(id: UUID = UUID(), name: String, settings: ExportSettings, createdAt: Date = Date(), updatedAt: Date? = nil, lastUsedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.settings = settings
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.lastUsedAt = lastUsedAt
    }

    enum CodingKeys: String, CodingKey { case id, name, settings, createdAt, updatedAt, lastUsedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        settings = c.decode(.settings, default: ExportSettings())
        createdAt = c.decode(.createdAt, default: Date(timeIntervalSince1970: 0))
        updatedAt = c.decode(.updatedAt, default: createdAt)
        lastUsedAt = c.decode(.lastUsedAt, default: nil)
    }

    /// One-line description, e.g. "WebP 80 · Fit 1600 px wide".
    public var summary: String { settings.summary }
}

public enum PresetNameError: Error, Hashable, Sendable {
    case empty
    case tooLong(limit: Int)
    case duplicate

    public var message: String {
        switch self {
        case .empty: "Enter a name."
        case .tooLong(let limit): "Use \(limit) characters or fewer."
        case .duplicate: "A preset with this name already exists."
        }
    }
}

public enum PresetError: Error, Hashable, Sendable {
    case invalidName(PresetNameError)
    case notFound
}

/// Value-type preset collection with all editing rules. Persistence is handled by `PresetStore`.
public struct PresetLibrary: Codable, Hashable, Sendable {
    public static let schemaVersion = 1
    public static let maxNameLength = 60

    public private(set) var presets: [ExportPreset]

    public init(presets: [ExportPreset] = []) {
        self.presets = presets
    }

    public func preset(_ id: UUID) -> ExportPreset? {
        presets.first { $0.id == id }
    }

    public static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func validateName(_ name: String, excluding id: UUID? = nil) -> PresetNameError? {
        let trimmed = Self.normalizedName(name)
        if trimmed.isEmpty { return .empty }
        if trimmed.count > Self.maxNameLength { return .tooLong(limit: Self.maxNameLength) }
        let clash = presets.contains { $0.id != id && $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        return clash ? .duplicate : nil
    }

    @discardableResult
    public mutating func create(name: String, settings: ExportSettings, now: Date = Date()) throws(PresetError) -> ExportPreset {
        if let error = validateName(name) { throw .invalidName(error) }
        let preset = ExportPreset(name: Self.normalizedName(name), settings: settings, createdAt: now)
        presets.append(preset)
        return preset
    }

    public mutating func rename(_ id: UUID, to name: String, now: Date = Date()) throws(PresetError) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { throw .notFound }
        if let error = validateName(name, excluding: id) { throw .invalidName(error) }
        presets[index].name = Self.normalizedName(name)
        presets[index].updatedAt = now
    }

    /// Replaces the recipe stored in a preset.
    public mutating func updateSettings(_ id: UUID, settings: ExportSettings, now: Date = Date()) throws(PresetError) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { throw .notFound }
        presets[index].settings = settings
        presets[index].updatedAt = now
    }

    /// Copies a preset as "Name copy", "Name copy 2", … The original is not changed.
    @discardableResult
    public mutating func duplicate(_ id: UUID, now: Date = Date()) throws(PresetError) -> ExportPreset {
        guard let original = preset(id) else { throw .notFound }
        let copy = ExportPreset(name: uniqueName(base: "\(original.name) copy"), settings: original.settings, createdAt: now)
        if let index = presets.firstIndex(where: { $0.id == id }) {
            presets.insert(copy, at: index + 1)
        } else {
            presets.append(copy)
        }
        return copy
    }

    public mutating func delete(_ id: UUID) {
        presets.removeAll { $0.id == id }
    }

    public mutating func markUsed(_ id: UUID, now: Date = Date()) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].lastUsedAt = now
    }

    public func uniqueName(base: String) -> String {
        let trimmedBase = String(Self.normalizedName(base).prefix(Self.maxNameLength - 4))
        if validateName(trimmedBase) == nil { return trimmedBase }
        var counter = 2
        while validateName("\(trimmedBase) \(counter)") != nil { counter += 1 }
        return "\(trimmedBase) \(counter)"
    }

    /// Created on first launch only. Every starter preset is covered by an export test.
    public static func starters(now: Date = Date()) -> PresetLibrary {
        PresetLibrary(presets: [
            ExportPreset(
                id: UUID(uuidString: "6D2B7C4E-3F1A-4B8E-9C11-0A5E2F7B1D01")!,
                name: "Web — WebP 1600px",
                settings: ExportSettings(format: .webp, quality: 80, resize: ResizeSettings(mode: .fit, maxWidth: 1600, maxHeight: nil)),
                createdAt: now
            ),
            ExportPreset(
                id: UUID(uuidString: "6D2B7C4E-3F1A-4B8E-9C11-0A5E2F7B1D02")!,
                name: "Product Images — JPEG 1200px",
                settings: ExportSettings(format: .jpeg, quality: 82, resize: ResizeSettings(mode: .fit, maxWidth: 1200, maxHeight: 1200)),
                createdAt: now
            ),
            ExportPreset(
                id: UUID(uuidString: "6D2B7C4E-3F1A-4B8E-9C11-0A5E2F7B1D03")!,
                name: "Responsive — 480/960/1440px",
                settings: ExportSettings(
                    format: .webp,
                    quality: 78,
                    resize: ResizeSettings(mode: .widths, widths: [480, 960, 1440]),
                    naming: FilenameRule(mode: .template, template: "{name}-{width}w")
                ),
                createdAt: now
            ),
        ])
    }
}

/// Loads and saves the preset library as versioned JSON.
public final class PresetStore: Sendable {
    public let store: VersionedJSONStore<PresetLibrary>

    public init(directory: URL = StorageLocation.applicationSupport()) {
        store = VersionedJSONStore(fileURL: directory.appendingPathComponent("presets.json"), schemaVersion: PresetLibrary.schemaVersion)
    }

    public struct Loaded: Sendable {
        public let library: PresetLibrary
        public let readOnly: Bool
        public let notice: String?
    }

    public func load() -> Loaded {
        switch store.load() {
        case .missing:
            let starters = PresetLibrary.starters()
            try? store.save(starters)
            return Loaded(library: starters, readOnly: false, notice: nil)
        case .loaded(let library):
            return Loaded(library: library, readOnly: false, notice: nil)
        case .loadedReadOnly(let library, let version):
            return Loaded(library: library, readOnly: true, notice: "Presets were saved by a newer Pixtamer (format \(version)). Changes won’t be saved in this version.")
        case .recoveredFromCorruption(let backup):
            let note = backup.map { "The preset file was damaged and was moved aside as \($0). Starter presets were restored." }
                ?? "The preset file was damaged. Starter presets were restored."
            let starters = PresetLibrary.starters()
            try? store.save(starters)
            return Loaded(library: starters, readOnly: false, notice: note)
        }
    }

    public func save(_ library: PresetLibrary) throws {
        try store.save(library)
    }
}

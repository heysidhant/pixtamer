import Foundation

public struct AppPreferences: Codable, Hashable, Sendable {
    public static let schemaVersion = 1

    public enum DestinationBehavior: String, Codable, CaseIterable, Sendable, Identifiable {
        /// Choose a folder once per session (asked on the first export). No folder access is
        /// kept after quitting.
        case askEachTime
        /// Remember the last folder with a security-scoped bookmark.
        case rememberLast

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .askEachTime: "Choose a folder each session"
            case .rememberLast: "Remember the last export folder"
            }
        }
    }

    public enum Appearance: String, Codable, CaseIterable, Sendable, Identifiable {
        case system, light, dark
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }
    }

    /// Recipe loaded into the inspector at launch and after Reset.
    public var defaultExportSettings: ExportSettings
    public var destinationBehavior: DestinationBehavior
    public var appearance: Appearance
    public var includeSubfolders: Bool
    /// Security-scoped bookmark; only stored while `destinationBehavior == .rememberLast`.
    public var rememberedDestinationBookmark: Data?

    public init(
        defaultExportSettings: ExportSettings = ExportSettings(),
        destinationBehavior: DestinationBehavior = .askEachTime,
        appearance: Appearance = .system,
        includeSubfolders: Bool = true,
        rememberedDestinationBookmark: Data? = nil
    ) {
        self.defaultExportSettings = defaultExportSettings
        self.destinationBehavior = destinationBehavior
        self.appearance = appearance
        self.includeSubfolders = includeSubfolders
        self.rememberedDestinationBookmark = rememberedDestinationBookmark
    }

    enum CodingKeys: String, CodingKey {
        case defaultExportSettings, destinationBehavior, appearance, includeSubfolders, rememberedDestinationBookmark
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppPreferences()
        defaultExportSettings = c.decode(.defaultExportSettings, default: d.defaultExportSettings)
        destinationBehavior = c.decode(.destinationBehavior, default: d.destinationBehavior)
        appearance = c.decode(.appearance, default: d.appearance)
        includeSubfolders = c.decode(.includeSubfolders, default: d.includeSubfolders)
        rememberedDestinationBookmark = c.decode(.rememberedDestinationBookmark, default: nil)
    }
}

/// One finished export, kept for the Recent Exports list. Stores counts and the destination
/// folder path only — never image contents.
public struct RecentExport: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var destinationPath: String
    public var settingsSummary: String
    public var summary: BatchSummary
    public var cancelled: Bool

    public init(id: UUID = UUID(), date: Date, destinationPath: String, settingsSummary: String, summary: BatchSummary, cancelled: Bool) {
        self.id = id
        self.date = date
        self.destinationPath = destinationPath
        self.settingsSummary = settingsSummary
        self.summary = summary
        self.cancelled = cancelled
    }

    public var destinationName: String { (destinationPath as NSString).lastPathComponent }
}

public struct RecentExportHistory: Codable, Hashable, Sendable {
    public static let schemaVersion = 1
    public static let limit = 25

    public private(set) var entries: [RecentExport]

    public init(entries: [RecentExport] = []) {
        self.entries = entries
    }

    public mutating func record(_ entry: RecentExport) {
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    public mutating func clear() { entries.removeAll() }
}

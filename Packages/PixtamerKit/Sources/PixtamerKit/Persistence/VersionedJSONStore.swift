import Foundation

/// A Codable payload stored as `{ "schemaVersion": n, "payload": … }` in one JSON file.
///
/// - Missing file: `.missing` (caller supplies defaults).
/// - Unreadable/corrupt file: moved aside to `name.corrupt-<timestamp>.json`, then `.recoveredFromCorruption`.
/// - Newer schema: decoded best-effort and marked read-only so an older build never overwrites it.
public final class VersionedJSONStore<Payload: Codable & Sendable>: Sendable {
    public enum LoadResult: Sendable {
        case missing
        case loaded(Payload)
        case loadedReadOnly(Payload, fileVersion: Int)
        case recoveredFromCorruption(backupName: String?)
    }

    struct Envelope: Codable {
        let schemaVersion: Int
        let payload: Payload
    }

    struct VersionProbe: Decodable {
        let schemaVersion: Int
    }

    public let fileURL: URL
    public let schemaVersion: Int

    public init(fileURL: URL, schemaVersion: Int) {
        self.fileURL = fileURL
        self.schemaVersion = schemaVersion
    }

    public func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .missing }
        do {
            let data = try Data(contentsOf: fileURL)
            let version = try JSONDecoder().decode(VersionProbe.self, from: data).schemaVersion
            let envelope = try Self.decoder.decode(Envelope.self, from: data)
            if version > schemaVersion {
                return .loadedReadOnly(envelope.payload, fileVersion: version)
            }
            return .loaded(envelope.payload)
        } catch {
            return .recoveredFromCorruption(backupName: moveAsideCorruptFile())
        }
    }

    public func save(_ payload: Payload) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(Envelope(schemaVersion: schemaVersion, payload: payload))
        try data.write(to: fileURL, options: [.atomic])
    }

    private func moveAsideCorruptFile() -> String? {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let base = fileURL.deletingPathExtension().lastPathComponent
        let backup = fileURL.deletingLastPathComponent().appendingPathComponent("\(base).corrupt-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: backup)
            return backup.lastPathComponent
        } catch {
            return nil
        }
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum StorageLocation {
    /// `~/Library/Application Support/Pixtamer` (inside the sandbox container when sandboxed).
    public static func applicationSupport() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Pixtamer", isDirectory: true)
    }
}

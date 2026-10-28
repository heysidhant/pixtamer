import Foundation

/// A source image accepted into the queue. Created by `ImageInspector` from file metadata only;
/// no full-resolution pixels are decoded during import.
public struct ImageInput: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let fileName: String
    public let typeIdentifier: String
    public let typeDisplayName: String
    /// Display-oriented size (EXIF orientation applied).
    public let pixelSize: PixelSize
    public let fileSize: Int64
    public let hasAlpha: Bool
    /// EXIF orientation 1–8 as stored in the file.
    public let orientation: Int
    public let colorProfileName: String?
    public let frameCount: Int
    public let warnings: [ImportWarning]

    public init(
        id: UUID = UUID(),
        url: URL,
        fileName: String,
        typeIdentifier: String,
        typeDisplayName: String,
        pixelSize: PixelSize,
        fileSize: Int64,
        hasAlpha: Bool,
        orientation: Int = 1,
        colorProfileName: String? = nil,
        frameCount: Int = 1,
        warnings: [ImportWarning] = []
    ) {
        self.id = id
        self.url = url
        self.fileName = fileName
        self.typeIdentifier = typeIdentifier
        self.typeDisplayName = typeDisplayName
        self.pixelSize = pixelSize
        self.fileSize = fileSize
        self.hasAlpha = hasAlpha
        self.orientation = orientation
        self.colorProfileName = colorProfileName
        self.frameCount = frameCount
        self.warnings = warnings
    }

    /// File name without its extension; the `{name}` token.
    public var baseName: String {
        let base = (fileName as NSString).deletingPathExtension
        return base.isEmpty ? fileName : base
    }

    /// Key used to detect the same file being imported twice.
    public var identityKey: String { PathKey.make(url) }
}

public enum ImportWarning: Hashable, Sendable {
    case possiblyTruncated
    case multipleFrames(count: Int)

    public var message: String {
        switch self {
        case .possiblyTruncated:
            "The file may be incomplete or damaged. Check the output before using it."
        case .multipleFrames(let count):
            "Contains \(count) frames. Only the first frame is exported."
        }
    }
}

/// A file that was offered for import but not added to the queue.
public struct RejectedFile: Hashable, Sendable, Identifiable {
    public let id = UUID()
    public let fileName: String
    public let reason: ImportRejection

    public init(fileName: String, reason: ImportRejection) {
        self.fileName = fileName
        self.reason = reason
    }
}

public enum ImportRejection: Error, Hashable, Sendable {
    case notAnImage
    case unsupportedImageType(typeName: String)
    case unreadable
    case emptyFile
    case noAccess
    case missing
    case invalidDimensions

    public var message: String {
        switch self {
        case .notAnImage: "Not an image file."
        case .unsupportedImageType(let name): "\(name) images are not supported."
        case .unreadable: "The file could not be read as an image. It may be damaged."
        case .emptyFile: "The file is empty."
        case .noAccess: "Pixtamer does not have permission to read this file."
        case .missing: "The file no longer exists."
        case .invalidDimensions: "The image reports no usable pixel dimensions."
        }
    }
}

enum PathKey {
    /// Case-insensitive, symlink-resolved path used for duplicate and overlap checks. Being
    /// case-insensitive is deliberately conservative: APFS volumes are case-insensitive by default.
    static func make(_ url: URL) -> String {
        let standardized = url.standardizedFileURL
        let directory = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
        return directory.appendingPathComponent(standardized.lastPathComponent).path
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }
}

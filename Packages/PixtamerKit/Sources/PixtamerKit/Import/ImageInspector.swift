import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads image metadata (type, size, orientation, alpha) without decoding pixels.
public struct ImageInspector: Sendable {
    public let readableTypes: [String: String]

    /// - Parameter readableTypes: type identifier → display name for accepted input types.
    public init(readableTypes: [String: String]) {
        self.readableTypes = readableTypes
    }

    public init(capabilities: FormatCapabilities) {
        self.readableTypes = FormatCapabilities.supportedInputTypes.filter { capabilities.readableTypeIdentifiers.contains($0.key) }
    }

    public func inspect(_ url: URL) -> Result<ImageInput, ImportRejection> {
        let fileName = url.lastPathComponent
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isReadableKey])
        guard FileManager.default.fileExists(atPath: url.path) else { return .failure(.missing) }
        if values?.isReadable == false { return .failure(.noAccess) }
        let fileSize = Int64(values?.fileSize ?? 0)
        guard fileSize > 0 else { return .failure(.emptyFile) }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String? else {
            return .failure(Self.looksLikeImage(url) ? .unreadable : .notAnImage)
        }
        guard let typeName = readableTypes[type] else {
            let name = UTType(type)?.localizedDescription ?? type
            return .failure(.unsupportedImageType(typeName: name))
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0, let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .failure(.unreadable)
        }
        guard let size = Self.orientedSize(properties), size.isValid else { return .failure(.invalidDimensions) }

        var warnings: [ImportWarning] = []
        if count > 1 && type == "com.compuserve.gif" { warnings.append(.multipleFrames(count: count)) }
        if TruncationCheck.isPossiblyTruncated(url: url, typeIdentifier: type) { warnings.append(.possiblyTruncated) }

        return .success(ImageInput(
            url: url,
            fileName: fileName,
            typeIdentifier: type,
            typeDisplayName: typeName,
            pixelSize: size,
            fileSize: fileSize,
            hasAlpha: properties[kCGImagePropertyHasAlpha] as? Bool ?? false,
            orientation: properties[kCGImagePropertyOrientation] as? Int ?? 1,
            colorProfileName: properties[kCGImagePropertyProfileName] as? String,
            frameCount: count,
            warnings: warnings
        ))
    }

    /// Pixel size after applying EXIF orientation (5–8 swap width and height).
    static func orientedSize(_ properties: [CFString: Any]) -> PixelSize? {
        guard let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation) ? PixelSize(width: height, height: width) : PixelSize(width: width, height: height)
    }

    static func looksLikeImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}

/// Image I/O decodes truncated JPEG and PNG files without error (missing rows are grey), so
/// check for the format's end marker near the end of the file.
enum TruncationCheck {
    static func isPossiblyTruncated(url: URL, typeIdentifier: String) -> Bool {
        let tailLength = 1024
        guard typeIdentifier == "public.jpeg" || typeIdentifier == "public.png",
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return false }
        let start = end > UInt64(tailLength) ? end - UInt64(tailLength) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let tail = try? handle.readToEnd() else { return false }
        let bytes = [UInt8](tail)
        switch typeIdentifier {
        case "public.jpeg":
            // End Of Image marker FF D9, possibly followed by padding or trailing data.
            return !zip(bytes, bytes.dropFirst()).contains { $0 == 0xFF && $1 == 0xD9 }
        default:
            return !containsSequence(bytes, Array("IEND".utf8))
        }
    }

    private static func containsSequence(_ bytes: [UInt8], _ needle: [UInt8]) -> Bool {
        guard bytes.count >= needle.count else { return false }
        for i in 0...(bytes.count - needle.count) where Array(bytes[i..<(i + needle.count)]) == needle {
            return true
        }
        return false
    }
}

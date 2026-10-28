import Darwin
import Foundation
import ImageIO

/// Writes encoded data safely: temporary file in the destination folder → verify → atomic rename.
/// A final file name only ever appears once its content is complete and has been re-read.
public enum OutputWriter {
    public enum Finalized: Hashable, Sendable {
        case written(url: URL, bytes: Int64, renamedFrom: String?)
        case skippedExisting(fileName: String)
    }

    static let temporaryMarker = ".pixtamer-partial"

    /// Hidden temporary sibling of `final`, so the final rename never crosses volumes.
    static func temporaryURL(for final: URL) -> URL {
        let token = UUID().uuidString.prefix(8)
        return final.deletingLastPathComponent().appendingPathComponent(".\(final.lastPathComponent).\(token)\(temporaryMarker)", isDirectory: false)
    }

    static func write(
        data: Data,
        to final: URL,
        expectedFormat: OutputFormat,
        expectedSize: PixelSize,
        policy: CollisionPolicy,
        protectedPathKeys: Set<String>,
        isCancelled: () -> Bool
    ) throws(ExportFailure) -> Finalized? {
        let directory = final.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ExportFailure(.destinationUnavailable, "Couldn’t create the folder “\(directory.lastPathComponent)”. Check that the destination is writable.")
        }

        let temp = temporaryURL(for: final)
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            try data.write(to: temp, options: [.withoutOverwriting])
        } catch {
            throw ExportFailure(.writeFailed, "Couldn’t write \(final.lastPathComponent): \(Self.describe(error)).")
        }

        try verify(fileURL: temp, displayName: final.lastPathComponent, expectedFormat: expectedFormat, expectedSize: expectedSize)

        if isCancelled() { return nil }
        return try finalize(temp: temp, final: final, policy: policy, protectedPathKeys: protectedPathKeys)
    }

    /// Re-opens the written file and checks type, dimensions and that it decodes.
    static func verify(fileURL: URL, displayName: String, expectedFormat: OutputFormat, expectedSize: PixelSize) throws(ExportFailure) {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else {
            throw ExportFailure(.verificationFailed, "\(displayName) could not be re-opened after writing.")
        }
        let type = CGImageSourceGetType(source) as String?
        guard type == expectedFormat.typeIdentifier else {
            throw ExportFailure(.verificationFailed, "\(displayName) was written as \(type ?? "an unknown type") instead of \(expectedFormat.displayName).")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int
        let height = properties?[kCGImagePropertyPixelHeight] as? Int
        guard width == expectedSize.width, height == expectedSize.height else {
            throw ExportFailure(.verificationFailed, "\(displayName) has unexpected dimensions \(width ?? 0)×\(height ?? 0); expected \(expectedSize).")
        }
        let probe = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 32] as CFDictionary
        guard CGImageSourceCreateThumbnailAtIndex(source, 0, probe) != nil else {
            throw ExportFailure(.verificationFailed, "\(displayName) was written but could not be decoded.")
        }
    }

    static func finalize(temp: URL, final: URL, policy: CollisionPolicy, protectedPathKeys: Set<String>) throws(ExportFailure) -> Finalized {
        if protectedPathKeys.contains(PathKey.make(final)) {
            // Planning already avoids this; refusing here is the last line of defence.
            throw ExportFailure(.protectedSource, "Refused to replace the source image \(final.lastPathComponent).")
        }
        switch policy {
        case .replace:
            if rename(temp.path, final.path) != 0 {
                throw ExportFailure(.writeFailed, "Couldn’t save \(final.lastPathComponent): \(String(cString: strerror(errno))).")
            }
            return .written(url: final, bytes: fileSize(final), renamedFrom: nil)
        case .skip:
            switch exclusiveRename(temp, final) {
            case .success: return .written(url: final, bytes: fileSize(final), renamedFrom: nil)
            case .exists: return .skippedExisting(fileName: final.lastPathComponent)
            case .failure(let code): throw ExportFailure(.writeFailed, "Couldn’t save \(final.lastPathComponent): \(String(cString: strerror(code))).")
            }
        case .rename:
            var candidate = final
            // A file appeared after planning (another app, or a duplicate run). Keep numbering.
            for _ in 0..<10_000 {
                switch exclusiveRename(temp, candidate) {
                case .success:
                    let renamed = candidate == final ? nil : final.lastPathComponent
                    return .written(url: candidate, bytes: fileSize(candidate), renamedFrom: renamed)
                case .exists:
                    candidate = NumberedName.next(after: final) { url in
                        url != candidate && !FileManager.default.fileExists(atPath: url.path) && !protectedPathKeys.contains(PathKey.make(url))
                    }
                case .failure(let code):
                    throw ExportFailure(.writeFailed, "Couldn’t save \(final.lastPathComponent): \(String(cString: strerror(code))).")
                }
            }
            throw ExportFailure(.writeFailed, "Couldn’t find a free name for \(final.lastPathComponent).")
        }
    }

    enum RenameResult { case success, exists, failure(Int32) }

    /// `rename` that fails instead of replacing an existing file (atomic on APFS/HFS+).
    static func exclusiveRename(_ from: URL, _ to: URL) -> RenameResult {
        if renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) == 0 { return .success }
        let code = errno
        return code == EEXIST ? .exists : .failure(code)
    }

    static func fileSize(_ url: URL) -> Int64 {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return 0 }
        return Int64(info.st_size)
    }

    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileWriteOutOfSpaceError: return "the disk is full"
            case NSFileWriteNoPermissionError: return "permission denied"
            case NSFileWriteVolumeReadOnlyError: return "the volume is read-only"
            default: break
            }
        }
        if let posix = (ns.userInfo[NSUnderlyingErrorKey] as? NSError), posix.domain == NSPOSIXErrorDomain {
            return String(cString: strerror(Int32(posix.code)))
        }
        return "error \(ns.code)"
    }
}

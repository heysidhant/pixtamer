import Foundation
import UniformTypeIdentifiers

public struct ImportReport: Hashable, Sendable {
    public var added: [ImageInput] = []
    public var rejected: [RejectedFile] = []
    /// Files already in the queue (same path), not added again.
    public var duplicateCount = 0
    /// Non-image files found while scanning folders (documents, hidden files are not counted).
    public var ignoredNonImageCount = 0

    public init() {}

    public var hasProblems: Bool { !rejected.isEmpty }
}

/// Expands user-chosen files and folders into queue items.
public struct ImageImporter: Sendable {
    public let inspector: ImageInspector

    public init(inspector: ImageInspector) {
        self.inspector = inspector
    }

    /// - Parameters:
    ///   - urls: Files and/or folders chosen by the user (open panel or drag and drop).
    ///   - includeSubfolders: Scan folders recursively.
    ///   - existingKeys: `identityKey`s already in the queue.
    public func importItems(_ urls: [URL], includeSubfolders: Bool, existingKeys: Set<String>) -> ImportReport {
        var report = ImportReport()
        var seen = existingKeys

        func consider(_ url: URL, fromFolder: Bool) {
            let key = PathKey.make(url)
            if seen.contains(key) {
                report.duplicateCount += 1
                return
            }
            if fromFolder && !ImageInspector.looksLikeImage(url) {
                report.ignoredNonImageCount += 1
                return
            }
            switch inspector.inspect(url) {
            case .success(let input):
                seen.insert(key)
                report.added.append(input)
            case .failure(let reason):
                if fromFolder, reason == .notAnImage {
                    report.ignoredNonImageCount += 1
                } else {
                    report.rejected.append(RejectedFile(fileName: url.lastPathComponent, reason: reason))
                }
            }
        }

        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                report.rejected.append(RejectedFile(fileName: url.lastPathComponent, reason: .missing))
                continue
            }
            let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
            if isDirectory.boolValue && !isPackage {
                for file in folderContents(url, recursive: includeSubfolders) {
                    consider(file, fromFolder: true)
                }
            } else {
                consider(url, fromFolder: false)
            }
        }
        return report
    }

    /// Regular, non-hidden files in a folder, sorted by path for a stable queue order.
    func folderContents(_ folder: URL, recursive: Bool) -> [URL] {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        if !recursive { options.insert(.skipsSubdirectoryDescendants) }
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: options) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                files.append(url)
            }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

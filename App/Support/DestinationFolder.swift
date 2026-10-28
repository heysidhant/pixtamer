import Foundation
import Observation

/// The export folder and its sandbox access.
///
/// Folders chosen in an open panel are accessible for the session. A security-scoped bookmark
/// is created only when the user turns on "Remember the last export folder", so access does not
/// outlive the session unless they asked for it.
@MainActor
@Observable
final class DestinationFolder {
    private(set) var url: URL?
    private var accessingURL: URL?

    var displayName: String? { url?.lastPathComponent }

    var exists: Bool {
        guard let url else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// - Parameter securityScoped: true for URLs resolved from a bookmark, which need explicit
    ///   start/stop. Panel and drag-and-drop URLs are accessible for the session already.
    func set(_ newURL: URL, securityScoped: Bool = false) {
        stopAccess()
        url = newURL
        if securityScoped, newURL.startAccessingSecurityScopedResource() {
            accessingURL = newURL
        }
    }

    func clear() {
        stopAccess()
        url = nil
    }

    func makeBookmark() -> Data? {
        try? url?.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves a stored bookmark. Returns a refreshed bookmark when the stored one is stale, or
    /// nil when it could not be resolved (folder deleted or access revoked).
    func restore(from bookmark: Data) -> (restored: Bool, refreshed: Data?) {
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return (false, nil)
        }
        set(resolved, securityScoped: true)
        guard exists else {
            clear()
            return (false, nil)
        }
        return (true, stale ? makeBookmark() : nil)
    }

    private func stopAccess() {
        accessingURL?.stopAccessingSecurityScopedResource()
        accessingURL = nil
    }
}

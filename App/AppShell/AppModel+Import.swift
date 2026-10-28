import AppKit
import PixtamerKit

extension AppModel {
    func addFilesWithPanel() {
        let urls = FilePanels.chooseImages(allowedTypes: readableContentTypes)
        importURLs(urls)
    }

    func addFolderWithPanel() {
        importURLs(FilePanels.chooseFolders())
    }

    /// Imports files and folders from a panel or drag and drop. Metadata is read on a
    /// background queue; only file headers are read, never full pixels.
    func importURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        sidebarSelection = .batch
        batch.isImporting = true
        importBanner = nil
        let includeSubfolders = preferences.includeSubfolders
        let existing = batch.identityKeys
        Task {
            let capabilities = await readyCapabilities()
            let importer = ImageImporter(inspector: ImageInspector(capabilities: capabilities))
            let report = await BlockingWorkQueue.shared.run {
                importer.importItems(urls, includeSubfolders: includeSubfolders, existingKeys: existing)
            }
            batch.add(report.added)
            batch.isImporting = false
            presentImportResult(report)
        }
    }

    private func presentImportResult(_ report: ImportReport) {
        if report.hasProblems {
            importReport = PresentedImportReport(report: report)
            return
        }
        var parts: [String] = []
        if !report.added.isEmpty { parts.append("Added \(Formatting.count(report.added.count, "image")).") }
        if report.duplicateCount > 0 { parts.append("\(Formatting.count(report.duplicateCount, "file")) already in the queue.") }
        if report.ignoredNonImageCount > 0 { parts.append("Ignored \(Formatting.count(report.ignoredNonImageCount, "non-image file")).") }
        if report.added.isEmpty && parts.isEmpty { parts.append("No images were found.") }
        importBanner = parts.joined(separator: " ")
        let banner = importBanner
        Task {
            try? await Task.sleep(for: .seconds(6))
            if importBanner == banner { importBanner = nil }
        }
    }

    func removeSelected() {
        guard exportSession?.isRunning != true else { return }
        batch.remove(batch.selection)
    }

    func remove(_ ids: Set<QueueItem.ID>) {
        guard exportSession?.isRunning != true else { return }
        batch.remove(ids)
    }

    func clearQueue() {
        guard exportSession?.isRunning != true else { return }
        batch.clear()
        importBanner = nil
    }

    func revealInFinder(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

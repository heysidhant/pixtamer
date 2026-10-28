import AppKit
import UniformTypeIdentifiers

/// Native open panels. In the sandbox, anything the user picks here becomes readable (and the
/// destination writable) for the rest of the session without extra permissions.
@MainActor
enum FilePanels {
    static func chooseImages(allowedTypes: [UTType]) -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Add Images"
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = allowedTypes.isEmpty ? [.image] : allowedTypes
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseFolders() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Add Folder"
        panel.prompt = "Add"
        panel.message = "Images in the chosen folders are added. Other files are ignored."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseDestination(startingAt directory: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.prompt = "Choose"
        panel.message = "Exported images are saved here. Originals are never changed."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        return panel.runModal() == .OK ? panel.url : nil
    }
}

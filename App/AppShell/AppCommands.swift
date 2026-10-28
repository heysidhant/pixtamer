import SwiftUI

/// Menu bar commands and keyboard shortcuts.
struct AppCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Images…") { model.addFilesWithPanel() }
                .keyboardShortcut("o")
            Button("Add Folder…") { model.addFolderWithPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Choose Export Folder…") { model.chooseDestination() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
        }

        CommandMenu("Batch") {
            Button("Start Export") {
                model.sidebarSelection = .batch
                model.startExport()
            }
            .keyboardShortcut("e")
            .disabled(!model.canStartExport)

            Button("Preview Selected Image") {
                model.previewItemID = model.batch.selectedOrAll.first?.id
            }
            .keyboardShortcut("y")
            .disabled(model.batch.isEmpty)

            Divider()

            // ⌘⌫ like Finder; the bare Delete key is handled by the queue table itself so it
            // never steals Delete from text fields.
            Button("Remove Selected") { model.removeSelected() }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(model.batch.selection.isEmpty)
            Button("Clear Queue") { model.clearQueue() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(model.batch.isEmpty)

            Divider()

            Button(model.showInspector ? "Hide Export Settings" : "Show Export Settings") {
                model.showInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])

            Button("Reset Settings to Defaults") { model.resetBatchSettingsToDefaults() }
        }

        CommandGroup(after: .sidebar) {
            ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
                Button(item.title) { model.sidebarSelection = item }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
        }

        CommandGroup(replacing: .help) {
            Button("Pixtamer Help") { openWindow(id: WindowID.help) }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}

import PixtamerKit
import SwiftUI

enum WindowID {
    static let main = "main"
    static let help = "help"
}

@main
struct PixtamerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Pixtamer", id: WindowID.main) {
            RootView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 540)
                .onAppear {
                    appDelegate.attach(model)
                    model.applyAppearance()
                }
        }
        .defaultSize(width: 1200, height: 760)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
                .frame(width: 560, height: 620)
        }

        Window("Pixtamer Help", id: WindowID.help) {
            HelpAboutView()
                .environment(model)
                .frame(minWidth: 560, minHeight: 520)
        }
        .defaultSize(width: 680, height: 640)
    }
}

/// Keeps quitting safe while an export is running: cancel, wait for in-flight files to finish
/// or be discarded, then quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    /// Files opened with Pixtamer (Dock icon drop, Open With, `open -a Pixtamer file`).
    /// URLs delivered this way are readable inside the sandbox for the session.
    private var pendingOpenURLs: [URL] = []

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let model {
            model.importURLs(urls)
        } else {
            pendingOpenURLs.append(contentsOf: urls)
        }
    }

    func attach(_ model: AppModel) {
        self.model = model
        if !pendingOpenURLs.isEmpty {
            model.importURLs(pendingOpenURLs)
            pendingOpenURLs.removeAll()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, let session = model.exportSession, session.isRunning else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop the export and quit?"
        alert.informativeText = "Files that are already finished are kept. The image being written now is discarded, so no incomplete files are left behind."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Keep Exporting")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        session.cancel()
        Task { @MainActor in
            while session.isRunning {
                try? await Task.sleep(for: .milliseconds(100))
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

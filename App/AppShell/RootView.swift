import PixtamerKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $model.sidebarSelection) { item in
                Label(item.title, systemImage: item.symbol)
                    .badge(item == .batch && !model.batch.isEmpty ? model.batch.items.count : 0)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            switch model.sidebarSelection {
            case .batch:
                BatchWorkspaceView()
            case .presets:
                PresetManagerView()
            case .recents:
                RecentExportsView()
            case .settings:
                SettingsView()
                    .navigationTitle("Settings")
            }
        }
        .sheet(item: $model.exportSession) { session in
            ExportSheet(session: session)
        }
        .sheet(item: $model.importReport) { presented in
            ImportReportView(report: presented.report) { model.importReport = nil }
        }
        .alert(item: $model.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message))
        }
        .confirmationDialog(
            "Replace \(Formatting.count(model.pendingReplacement?.count ?? 0, "existing file"))?",
            isPresented: Binding(get: { model.pendingReplacement != nil }, set: { if !$0 { model.pendingReplacement = nil } }),
            presenting: model.pendingReplacement
        ) { pending in
            Button("Replace", role: .destructive) { model.confirmReplacement(pending, keepBoth: false) }
            Button("Keep Both") { model.confirmReplacement(pending, keepBoth: true) }
            Button("Cancel", role: .cancel) { model.pendingReplacement = nil }
        } message: { _ in
            Text("Files in “\(model.destination.displayName ?? "the export folder")” have the same names as new outputs. Source images are never replaced.")
        }
    }
}

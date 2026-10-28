import PixtamerKit
import SwiftUI

/// History of finished exports (counts and destination only, never image contents).
struct RecentExportsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClear = false

    var body: some View {
        Group {
            if model.recents.entries.isEmpty {
                ContentUnavailableView("No Exports Yet", systemImage: "clock.arrow.circlepath", description: Text("Finished exports appear here with their totals."))
            } else {
                Table(model.recents.entries) {
                    TableColumn("Date") { entry in
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    }
                    .width(min: 120, ideal: 150)
                    TableColumn("Settings") { entry in
                        Text(entry.settingsSummary).lineLimit(1)
                    }
                    TableColumn("Files") { entry in
                        Text(filesText(entry)).monospacedDigit()
                            .foregroundStyle(entry.summary.failedCount > 0 ? .orange : .primary)
                    }
                    .width(min: 120, ideal: 160)
                    TableColumn("Size") { entry in
                        Text(sizeText(entry.summary)).monospacedDigit()
                    }
                    .width(min: 120, ideal: 170)
                    TableColumn("Folder") { entry in
                        HStack {
                            Text(entry.destinationName).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button {
                                model.revealInFinder([URL(fileURLWithPath: entry.destinationPath, isDirectory: true)])
                            } label: {
                                Image(systemName: "arrow.right.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Show in Finder")
                            .accessibilityLabel("Show \(entry.destinationName) in Finder")
                        }
                    }
                    .width(min: 120, ideal: 180)
                }
            }
        }
        .navigationTitle("Recent Exports")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear History…") { confirmClear = true }
                    .disabled(model.recents.entries.isEmpty)
            }
        }
        .confirmationDialog("Clear export history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { model.clearRecentExports() }
        } message: {
            Text("Only this list is cleared. Exported files are not affected.")
        }
    }

    private func filesText(_ entry: RecentExport) -> String {
        var text = "\(entry.summary.writtenCount) exported"
        if entry.summary.failedCount > 0 { text += ", \(entry.summary.failedCount) failed" }
        if entry.cancelled { text += " (cancelled)" }
        return text
    }

    private func sizeText(_ summary: BatchSummary) -> String {
        guard summary.writtenCount > 0 else { return "—" }
        let change = summary.fractionSaved.map { " (\(Formatting.signedPercent($0)))" } ?? ""
        return "\(Formatting.bytes(summary.outputBytes))\(change)"
    }
}

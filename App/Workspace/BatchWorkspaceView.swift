import PixtamerKit
import SwiftUI

/// Screen B: the main batch workspace (queue, toolbar, inspector, status bar).
struct BatchWorkspaceView: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if model.batch.isEmpty {
                WelcomeView(isDropTargeted: isDropTargeted)
            } else {
                QueueTableView()
                if let banner = model.importBanner {
                    ImportBanner(text: banner) { model.importBanner = nil }
                }
                Divider()
                BatchStatusBar()
            }
        }
        .overlay {
            if model.batch.isImporting {
                ProgressView("Reading images…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .overlay {
            if isDropTargeted && !model.batch.isEmpty {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            model.importURLs(files)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .navigationTitle("Batch")
        .navigationSubtitle(subtitle)
        .toolbar { toolbarContent }
        .inspector(isPresented: $model.showInspector) {
            ExportInspectorView()
                .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
        }
        .sheet(item: Binding(
            get: { model.previewItemID.map(PreviewTarget.init) },
            set: { model.previewItemID = $0?.id }
        )) { target in
            ImagePreviewView(initialItemID: target.id)
        }
    }

    private var subtitle: String {
        guard !model.batch.isEmpty else { return "" }
        return "\(Formatting.count(model.batch.items.count, "image")) · \(Formatting.bytes(model.batch.totalBytes))"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.addFilesWithPanel() } label: {
                Label("Add Images", systemImage: "plus")
            }
            .help("Add image files (⌘O)")
            Button { model.addFolderWithPanel() } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
            .help("Add every image in a folder (⇧⌘O)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.removeSelected() } label: {
                Label("Remove Selected", systemImage: "minus.circle")
            }
            .help("Remove selected images from the queue (⌘⌫). Files on disk are not touched.")
            .disabled(model.batch.selection.isEmpty || model.exportSession?.isRunning == true)

            Button { model.clearQueue() } label: {
                Label("Clear Queue", systemImage: "trash")
            }
            .help("Remove all images from the queue (⇧⌘⌫). Files on disk are not touched.")
            .disabled(model.batch.isEmpty || model.exportSession?.isRunning == true)

            Button {
                model.previewItemID = nil
                model.startExport()
            } label: {
                Label("Start Export", systemImage: "square.and.arrow.up")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .help(model.exportBlockers.first ?? "Export \(Formatting.count(model.plannedOutputCount, "file")) (⌘E)")
            .disabled(!model.canStartExport)
        }
    }
}

private struct PreviewTarget: Identifiable {
    let id: QueueItem.ID
}

/// Transient confirmation after an import without problems.
private struct ImportBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(text).font(.callout)
            Spacer()
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
}

/// Bottom bar: what will be exported, where, and what blocks export.
struct BatchStatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            Label {
                Text("\(Formatting.count(model.batch.items.count, "image")) → \(Formatting.count(model.plannedOutputCount, "file"))")
                    .monospacedDigit()
            } icon: {
                Image(systemName: "photo.on.rectangle")
            }
            Text(model.settings.summary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let blocker = model.exportBlockers.first, !model.batch.isEmpty {
                Label(blocker, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Button {
                model.chooseDestination()
            } label: {
                Label(model.destination.displayName ?? "Choose Export Folder…", systemImage: "folder")
                    .lineLimit(1)
            }
            .buttonStyle(.borderless)
            .help(model.destination.url?.path ?? "Choose where exported files are saved")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

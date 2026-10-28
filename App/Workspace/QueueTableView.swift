import PixtamerKit
import SwiftUI

/// The queue: one row per source image.
struct QueueTableView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var batch = model.batch
        Table(model.batch.items, selection: $batch.selection) {
            TableColumn("Name") { item in
                HStack(spacing: 10) {
                    ThumbnailView(url: item.input.url, side: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.input.fileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(typeLine(item.input))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
                .help(item.input.fileName)
            }
            .width(min: 180, ideal: 280)

            TableColumn("Dimensions") { item in
                Text(item.input.pixelSize.description)
                    .monospacedDigit()
                    .accessibilityLabel("\(item.input.pixelSize.width) by \(item.input.pixelSize.height) pixels")
            }
            .width(min: 80, ideal: 100, max: 130)

            TableColumn("Size") { item in
                Text(Formatting.bytes(item.input.fileSize))
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 75, max: 100)

            TableColumn("Output") { item in
                Text(item.outputSummary(settings: model.settings))
                    .monospacedDigit()
                    .foregroundStyle(item.writtenFiles.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .help(item.writtenFiles.isEmpty ? "Planned output with the current settings" : "Actual output from the last export")
            }
            .width(min: 140, ideal: 220)

            TableColumn("Status") { item in
                StatusLabel(status: item.status)
            }
            .width(min: 90, ideal: 120, max: 200)
        }
        .contextMenu(forSelectionType: QueueItem.ID.self) { ids in
            if !ids.isEmpty {
                Button("Preview") { model.previewItemID = ids.first }
                Button("Show in Finder") {
                    model.revealInFinder(model.batch.items.filter { ids.contains($0.id) }.map(\.input.url))
                }
                let outputs = model.batch.items.filter { ids.contains($0.id) }.flatMap { $0.writtenFiles.map(\.url) }
                if !outputs.isEmpty {
                    Button("Show Exported Files in Finder") { model.revealInFinder(outputs) }
                }
                Divider()
                Button("Remove from Queue", role: .destructive) { model.remove(ids) }
            }
        } primaryAction: { ids in
            model.previewItemID = ids.first
        }
        .onDeleteCommand { model.removeSelected() }
        .onKeyPress(.space) {
            guard let first = model.batch.selectedOrAll.first else { return .ignored }
            model.previewItemID = first.id
            return .handled
        }
        .accessibilityLabel("Image queue")
    }

    private func typeLine(_ input: ImageInput) -> String {
        var parts = [input.typeDisplayName]
        if input.hasAlpha { parts.append("Transparency") }
        if let profile = input.colorProfileName { parts.append(profile) }
        return parts.joined(separator: " · ")
    }
}

struct StatusLabel: View {
    let status: QueueStatus

    var body: some View {
        HStack(spacing: 5) {
            if status == .processing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: status.symbol)
                    .foregroundStyle(status.tint)
            }
            Text(status.title)
                .lineLimit(1)
        }
        .help(status.detail ?? status.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.detail.map { "\(status.title). \($0)" } ?? status.title)
    }
}

/// Small orientation-corrected thumbnail loaded lazily per row.
struct ThumbnailView: View {
    let url: URL
    let side: CGFloat
    @State private var image: CGImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.12))
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
        .task(id: url) {
            let pixels = Int(side * max(scale, 2))
            image = ThumbnailLoader.shared.cached(url, maxPixelSize: pixels)
            if image == nil {
                image = await ThumbnailLoader.shared.thumbnail(for: url, maxPixelSize: pixels)
            }
        }
    }
}

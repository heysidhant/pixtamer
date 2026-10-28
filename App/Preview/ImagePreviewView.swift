import PixtamerKit
import SwiftUI

/// Screen D: original vs output. Output is either the actual exported file or an in-memory
/// estimate produced by the exact export code path, and is always labelled as such.
struct ImagePreviewView: View {
    enum Side: String, CaseIterable, Identifiable {
        case original = "Original"
        case output = "Output"
        var id: String { rawValue }
    }

    enum Zoom { case fit, actual }

    enum OutputSource {
        case actual(WrittenFile)
        case estimate(OutputEstimate)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var currentID: QueueItem.ID
    @State private var side: Side = .original
    @State private var zoom: Zoom = .fit
    @State private var originalImage: CGImage?
    @State private var outputImage: CGImage?
    @State private var output: OutputSource?
    @State private var estimateError: String?
    @State private var isWorking = false

    private static let fitDecodeSize = 2048
    private static let actualDecodeLimit = 4096

    init(initialItemID: QueueItem.ID) {
        _currentID = State(initialValue: initialItemID)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            canvas
            Divider()
            if let item {
                PreviewInfoBar(item: item, output: output, isWorking: isWorking, error: estimateError, estimate: makeEstimate)
            }
        }
        .frame(minWidth: 900, idealWidth: 1040, minHeight: 660, idealHeight: 760)
        .task(id: currentID) { await loadCurrent() }
        .onChange(of: zoom) { Task { await loadImages() } }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
    }

    private var item: QueueItem? { model.batch.item(currentID) }
    private var position: Int? { model.batch.index(of: currentID) }

    private var header: some View {
        HStack(spacing: 12) {
            ControlGroup {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled((position ?? 0) == 0)
                    .accessibilityLabel("Previous image")
                    .help("Previous image (←)")
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled((position ?? 0) >= model.batch.items.count - 1)
                    .accessibilityLabel("Next image")
                    .help("Next image (→)")
            }
            .fixedSize()
            VStack(alignment: .leading, spacing: 0) {
                Text(item?.input.fileName ?? "").font(.headline).lineLimit(1).truncationMode(.middle)
                if let position {
                    Text("\(position + 1) of \(model.batch.items.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer()
            Picker("Show", selection: $side) {
                ForEach(Side.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Picker("Zoom", selection: $zoom) {
                Text("Fit").tag(Zoom.fit)
                Text("100%").tag(Zoom.actual)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Fit the window, or show actual pixels (large images are limited to \(Self.actualDecodeLimit) px)")
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    @ViewBuilder
    private var canvas: some View {
        let image = side == .original ? originalImage : outputImage
        ZStack {
            if showsTransparency {
                CheckerboardBackground()
            } else {
                Color(nsColor: .underPageBackgroundColor)
            }
            if let image {
                switch zoom {
                case .fit:
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(12)
                case .actual:
                    ScrollView([.horizontal, .vertical]) {
                        Image(decorative: image, scale: NSScreen.main?.backingScaleFactor ?? 2)
                    }
                }
            } else if side == .output && output == nil {
                ContentUnavailableView {
                    Label("No output yet", systemImage: "photo.badge.arrow.down")
                } description: {
                    Text("Export this image, or estimate the result with the current settings. Nothing is saved by estimating.")
                } actions: {
                    Button("Estimate Output") { makeEstimate() }
                        .disabled(isWorking)
                }
                .background(.background.opacity(0.85))
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(side == .original ? "Original image" : "Output image")
    }

    /// Checkerboard only where transparency can actually appear.
    private var showsTransparency: Bool {
        guard let input = item?.input, input.hasAlpha else { return false }
        switch (side, output) {
        case (.original, _): return true
        case (.output, .actual(let file)?): return file.format.supportsTransparency
        case (.output, .estimate(let estimate)?): return estimate.format.supportsTransparency
        case (.output, nil): return false
        }
    }

    private func step(_ delta: Int) {
        guard let position else { return }
        let next = position + delta
        guard model.batch.items.indices.contains(next) else { return }
        currentID = model.batch.items[next].id
    }

    private func loadCurrent() async {
        originalImage = nil
        outputImage = nil
        estimateError = nil
        output = item?.writtenFiles.last.map(OutputSource.actual)
        await loadImages()
    }

    private func loadImages() async {
        guard let item else { return }
        let size = zoom == .fit ? Self.fitDecodeSize : min(Self.actualDecodeLimit, item.input.pixelSize.longSide)
        let url = item.input.url
        originalImage = await BlockingWorkQueue.shared.run { Thumbnailer.thumbnail(for: url, maxPixelSize: size) }
        switch output {
        case .actual(let file):
            let fileURL = file.url
            outputImage = await BlockingWorkQueue.shared.run { Thumbnailer.thumbnail(for: fileURL, maxPixelSize: size) }
        case .estimate(let estimate):
            let data = estimate.data
            outputImage = await BlockingWorkQueue.shared.run { Thumbnailer.thumbnail(for: data, maxPixelSize: size) }
        case nil:
            outputImage = nil
        }
    }

    private func makeEstimate() {
        guard let input = item?.input else { return }
        isWorking = true
        estimateError = nil
        side = .output
        let settings = model.settings
        let processor = model.processor
        let requestedID = currentID
        Task {
            let result: Result<OutputEstimate?, ExportFailure> = await BlockingWorkQueue.shared.run {
                do throws(ExportFailure) {
                    return .success(try processor.estimate(input: input, settings: settings))
                } catch {
                    return .failure(error)
                }
            }
            guard requestedID == currentID else { return }
            isWorking = false
            switch result {
            case .success(let estimate?):
                output = .estimate(estimate)
                await loadImages()
            case .success(nil):
                estimateError = "These settings produce no output for this image (it is smaller than the requested size)."
            case .failure(let failure):
                estimateError = failure.message
            }
        }
    }
}

private struct PreviewInfoBar: View {
    let item: QueueItem
    let output: ImagePreviewView.OutputSource?
    let isWorking: Bool
    let error: String?
    let estimate: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            InfoColumn(title: "Original", rows: [
                ("Dimensions", item.input.pixelSize.description),
                ("Size", Formatting.bytes(item.input.fileSize)),
                ("Format", item.input.typeDisplayName),
            ])
            Divider().frame(height: 60)
            switch output {
            case .actual(let file):
                InfoColumn(title: "Output — actual file", badge: "Saved", rows: rows(size: file.pixelSize, bytes: file.bytes, format: file.format) + [("File", file.url.lastPathComponent)])
            case .estimate(let estimate):
                InfoColumn(title: "Output — estimate", badge: "Not saved", rows: rows(size: estimate.pixelSize, bytes: estimate.bytes, format: estimate.format))
            case nil:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Output").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Not exported yet").foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button(output == nil ? "Estimate Output" : "Estimate with Current Settings", action: estimate)
                    .disabled(isWorking)
                if isWorking { ProgressView().controlSize(.small) }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.trailing).frame(maxWidth: 240, alignment: .trailing)
                }
            }
        }
        .padding(12)
    }

    private func rows(size: PixelSize, bytes: Int64, format: OutputFormat) -> [(String, String)] {
        var rows = [("Dimensions", size.description), ("Size", Formatting.bytes(bytes)), ("Format", format.displayName)]
        if let savings = Formatting.savings(Formatting.fraction(original: item.input.fileSize, output: bytes)) {
            rows.append(("Change", savings))
        }
        return rows
    }
}

private struct InfoColumn: View {
    let title: String
    var badge: String?
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(badge == "Saved" ? Color.green.opacity(0.2) : Color.orange.opacity(0.2)))
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
                ForEach(rows, id: \.0) { row in
                    GridRow {
                        Text(row.0).foregroundStyle(.secondary)
                        Text(row.1).monospacedDigit().lineLimit(1).truncationMode(.middle)
                    }
                    .font(.callout)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Neutral checkerboard so transparent areas are visible in both appearances.
struct CheckerboardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 10
            let light = colorScheme == .dark ? Color(white: 0.24) : Color(white: 0.96)
            let dark = colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.86)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(light))
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : cell
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(dark))
                    x += cell * 2
                }
                y += cell
                row += 1
            }
        }
        .accessibilityHidden(true)
    }
}

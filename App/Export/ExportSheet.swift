import PixtamerKit
import SwiftUI

/// Screens F and G: progress while running, then results. Can't be dismissed while running.
struct ExportSheet: View {
    let session: ExportSession

    var body: some View {
        Group {
            if session.isRunning {
                ExportProgressView(session: session)
            } else {
                ExportResultsView(session: session)
            }
        }
        .frame(width: 600, height: 560)
        .interactiveDismissDisabled(session.isRunning)
    }
}

// MARK: - Progress

struct ExportProgressView: View {
    @Environment(AppModel.self) private var model
    let session: ExportSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.state == .cancelling ? "Cancelling…" : (session.isRetry ? "Retrying failed files…" : "Exporting…"))
                    .font(.title2.weight(.semibold))
                ProgressView(value: session.fractionComplete)
                    .accessibilityLabel("Export progress")
                    .accessibilityValue("\(session.completed) of \(session.total) files")
                HStack {
                    Text("\(session.completed) of \(session.total) files")
                        .monospacedDigit()
                    Spacer()
                    if let current = session.currentFileName, session.state == .running {
                        Text(current)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                if session.state == .cancelling {
                    Caption("Finishing the files already being written. Nothing incomplete is kept.")
                }
            }

            JobList(session: session)

            HStack {
                let summary = session.summary
                if summary.failedCount > 0 {
                    Label("\(summary.failedCount) failed", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel", role: .cancel) { model.cancelExport() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(session.state != .running)
            }
        }
        .padding(20)
    }
}

private struct JobList: View {
    let session: ExportSession

    var body: some View {
        List(session.plan.jobs) { job in
            let status = session.status(of: job)
            HStack(spacing: 8) {
                JobStatusIcon(status: status)
                Text(job.input.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(detail(job, status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }
        .listStyle(.bordered)
    }

    private func detail(_ job: PlannedJob, _ status: ExportSession.JobStatus) -> String {
        let results = session.resultsByInput[job.id] ?? []
        switch status {
        case .waiting: return Formatting.count(job.variants.count, "output")
        case .processing: return "Working…"
        case .failed, .partial:
            let first = results.lazy.compactMap { if case .failed(let f) = $0.outcome { f.message } else { nil } }.first
            return first ?? "Failed"
        default:
            let bytes = results.reduce(Int64(0)) { if case .written(let f) = $1.outcome { $0 + f.bytes } else { $0 } }
            return bytes > 0 ? Formatting.bytes(bytes) : ""
        }
    }
}

private struct JobStatusIcon: View {
    let status: ExportSession.JobStatus

    var body: some View {
        Group {
            switch status {
            case .waiting: Image(systemName: "clock").foregroundStyle(.secondary)
            case .processing: ProgressView().controlSize(.small)
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .partial: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            case .skipped: Image(systemName: "arrow.uturn.right.circle").foregroundStyle(.orange)
            case .cancelled: Image(systemName: "stop.circle").foregroundStyle(.secondary)
            }
        }
        .frame(width: 16)
        .accessibilityLabel(String(describing: status))
    }
}

// MARK: - Results

struct ExportResultsView: View {
    @Environment(AppModel.self) private var model
    let session: ExportSession
    @State private var showDetails = false

    var body: some View {
        let summary = session.summary
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: headlineSymbol(summary))
                    .font(.system(size: 34))
                    .foregroundStyle(headlineTint(summary))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline(summary)).font(.title2.weight(.semibold))
                    Text("Finished in \(Formatting.duration(session.elapsed)) · \(session.plan.settings.summary)")
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Stat(title: "Exported", value: "\(summary.writtenCount)", tint: .primary)
                    Stat(title: "Skipped", value: "\(summary.skippedCount)", tint: summary.skippedCount > 0 ? .orange : .secondary)
                    Stat(title: "Failed", value: "\(summary.failedCount)", tint: summary.failedCount > 0 ? .red : .secondary)
                    if summary.cancelledCount > 0 {
                        Stat(title: "Not processed", value: "\(summary.cancelledCount)", tint: .secondary)
                    }
                }
            }

            if summary.writtenCount > 0 {
                SizeComparison(summary: summary)
            }

            LabeledContent("Saved to") {
                Text(session.plan.destination.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            DisclosureGroup("Details (\(session.results.count) files)", isExpanded: $showDetails) {
                ResultList(results: orderedResults)
                    .frame(minHeight: 120, maxHeight: 200)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Start Another Batch") { model.startAnotherBatch() }
                if summary.failedCount > 0 {
                    Button("Retry Failed (\(summary.failedCount))") { model.retryFailed() }
                        .help("Runs only the files that failed, with the same settings and file names.")
                }
                Spacer()
                Button("Show in Finder") { model.openDestinationInFinder(for: session) }
                    .disabled(summary.writtenCount == 0 && !FileManager.default.fileExists(atPath: session.plan.destination.path))
                Button("Done") { model.dismissExport() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onAppear { showDetails = summary.failedCount > 0 || summary.skippedCount > 0 }
    }

    /// Problems first, then everything else in queue order.
    private var orderedResults: [VariantResult] {
        let order = Dictionary(uniqueKeysWithValues: session.plan.variants.enumerated().map { ($1.id, $0) })
        func rank(_ r: VariantResult) -> Int {
            switch r.outcome {
            case .failed: 0
            case .skipped: 1
            case .cancelled: 2
            case .written: 3
            }
        }
        return session.results.sorted { a, b in
            rank(a) != rank(b) ? rank(a) < rank(b) : (order[a.id] ?? 0) < (order[b.id] ?? 0)
        }
    }

    private func headline(_ s: BatchSummary) -> String {
        if session.wasCancelled { return "Export cancelled" }
        if s.writtenCount == 0 && s.failedCount > 0 { return "Export failed" }
        if s.failedCount > 0 { return "Exported with problems" }
        if s.writtenCount == 0 { return "Nothing was exported" }
        return "Export complete"
    }

    private func headlineSymbol(_ s: BatchSummary) -> String {
        if session.wasCancelled { return "stop.circle.fill" }
        if s.failedCount > 0 { return s.writtenCount > 0 ? "exclamationmark.triangle.fill" : "xmark.octagon.fill" }
        return s.writtenCount > 0 ? "checkmark.circle.fill" : "info.circle.fill"
    }

    private func headlineTint(_ s: BatchSummary) -> Color {
        if session.wasCancelled { return .secondary }
        if s.failedCount > 0 { return s.writtenCount > 0 ? .orange : .red }
        return s.writtenCount > 0 ? .green : .secondary
    }
}

private struct Stat: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Before/after bytes, computed from the real file sizes on disk.
private struct SizeComparison: View {
    let summary: BatchSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(Formatting.bytes(summary.originalBytes)).monospacedDigit()
                Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityLabel("to")
                Text(Formatting.bytes(summary.outputBytes)).monospacedDigit().fontWeight(.semibold)
                if let savings = Formatting.savings(summary.fractionSaved) {
                    Text(savings)
                        .foregroundStyle(summary.bytesSaved >= 0 ? .green : .orange)
                        .fontWeight(.medium)
                }
            }
            .font(.title3)
            Text(summary.bytesSaved >= 0
                 ? "\(Formatting.bytes(summary.bytesSaved)) saved. Originals of \(Formatting.count(summary.sourcesExported, "exported image")) compared with every file written."
                 : "Outputs are \(Formatting.bytes(-summary.bytesSaved)) larger than the originals. This is common for PNG photos or upscaled images.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }
}

private struct ResultList: View {
    let results: [VariantResult]

    var body: some View {
        List(results) { result in
            HStack(spacing: 8) {
                icon(result.outcome)
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.outputFileName ?? "\(result.inputFileName) · \(result.label)").lineLimit(1).truncationMode(.middle)
                    Text(detail(result)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if case .written(let file) = result.outcome {
                    Text(Formatting.bytes(file.bytes)).font(.caption).monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
        }
        .listStyle(.bordered)
    }

    @ViewBuilder
    private func icon(_ outcome: VariantOutcome) -> some View {
        switch outcome {
        case .written: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped: Image(systemName: "arrow.uturn.right.circle").foregroundStyle(.orange)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .cancelled: Image(systemName: "stop.circle").foregroundStyle(.secondary)
        }
    }

    private func detail(_ result: VariantResult) -> String {
        var parts: [String] = ["From \(result.inputFileName)"]
        switch result.outcome {
        case .written(let file): parts.append(file.pixelSize.description)
        case .skipped(let reason): parts.append(reason.message)
        case .failed(let failure): parts.append("\(failure.message) [\(failure.code.rawValue)]")
        case .cancelled: parts.append("Not processed because the export was cancelled.")
        }
        parts += result.notes
        return parts.joined(separator: " · ")
    }
}

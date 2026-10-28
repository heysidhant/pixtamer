import PixtamerKit
import SwiftUI

/// One row in the batch queue: the imported source plus its most recent export results.
struct QueueItem: Identifiable, Hashable {
    enum Phase: Hashable { case idle, waiting, processing }

    let input: ImageInput
    var phase: Phase = .idle
    /// Results from the latest export run that included this image.
    var results: [VariantResult] = []

    var id: UUID { input.id }

    var writtenFiles: [WrittenFile] {
        results.compactMap { if case .written(let file) = $0.outcome { file } else { nil } }
    }

    var status: QueueStatus {
        switch phase {
        case .waiting: return .waiting
        case .processing: return .processing
        case .idle: break
        }
        guard !results.isEmpty else {
            return input.warnings.first.map { .warning($0.message) } ?? .ready
        }
        let written = writtenFiles.count
        let failures = results.compactMap { if case .failed(let f) = $0.outcome { f } else { nil } }
        if let failure = failures.first {
            return written > 0 ? .partial("\(failures.count) of \(results.count) failed: \(failure.message)") : .failed(failure.message)
        }
        if results.allSatisfy({ $0.outcome == .cancelled }) { return .cancelled }
        if written == 0 {
            let reason = results.compactMap { if case .skipped(let r) = $0.outcome { r.message } else { nil } }.first
            return .skipped(reason ?? "Nothing was exported.")
        }
        return .done(written: written, total: results.count)
    }
}

enum QueueStatus: Hashable {
    case ready
    case warning(String)
    case waiting
    case processing
    case done(written: Int, total: Int)
    case partial(String)
    case failed(String)
    case skipped(String)
    case cancelled

    var title: String {
        switch self {
        case .ready: "Ready"
        case .warning: "Check"
        case .waiting: "Waiting"
        case .processing: "Exporting"
        case .done(let written, let total): written == total ? "Done" : "Done (\(written) of \(total))"
        case .partial: "Partly failed"
        case .failed: "Failed"
        case .skipped: "Skipped"
        case .cancelled: "Cancelled"
        }
    }

    var detail: String? {
        switch self {
        case .warning(let m), .partial(let m), .failed(let m), .skipped(let m): m
        default: nil
        }
    }

    var symbol: String {
        switch self {
        case .ready: "circle"
        case .warning: "exclamationmark.triangle"
        case .waiting: "clock"
        case .processing: "arrow.triangle.2.circlepath"
        case .done: "checkmark.circle.fill"
        case .partial: "exclamationmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .skipped: "arrow.uturn.right.circle"
        case .cancelled: "stop.circle"
        }
    }

    var tint: Color {
        switch self {
        case .ready, .waiting, .cancelled: .secondary
        case .processing: .accentColor
        case .done: .green
        case .warning, .partial, .skipped: .orange
        case .failed: .red
        }
    }
}

extension QueueItem {
    /// Text for the Output column: the actual result after an export, otherwise the plan.
    func outputSummary(settings: ExportSettings) -> String {
        let files = writtenFiles
        if !files.isEmpty {
            let bytes = files.reduce(0) { $0 + $1.bytes }
            let format = files[0].format.displayName
            if files.count == 1 {
                let change = Formatting.fraction(original: input.fileSize, output: bytes).map { " (\(Formatting.signedPercent($0)))" } ?? ""
                return "\(format) · \(files[0].pixelSize) · \(Formatting.bytes(bytes))\(change)"
            }
            return "\(format) · \(files.count) files · \(Formatting.bytes(bytes))"
        }
        let decisions = ResizePlanner.variants(for: input.pixelSize, settings: settings.resize)
        let renders = decisions.compactMap { if case .render(let plan) = $0 { plan } else { nil } }
        let skipped = decisions.count - renders.count
        let format = settings.format.displayName
        switch renders.count {
        case 0:
            return "Nothing to export (smaller than target)"
        case 1 where decisions.count == 1:
            return "\(format) · \(renders[0].outputSize)"
        default:
            let sizes = Formatting.count(renders.count, "size")
            return skipped > 0 ? "\(format) · \(sizes), \(skipped) skipped" : "\(format) · \(sizes)"
        }
    }
}

import Foundation

public struct WrittenFile: Hashable, Sendable {
    public let url: URL
    public let bytes: Int64
    public let pixelSize: PixelSize
    public let format: OutputFormat
}

public enum VariantOutcome: Hashable, Sendable {
    case written(WrittenFile)
    case skipped(SkipReason)
    case failed(ExportFailure)
    /// Not produced because the export was cancelled. Nothing was written.
    case cancelled

    public var isWritten: Bool { if case .written = self { true } else { false } }
    public var isFailed: Bool { if case .failed = self { true } else { false } }
}

/// Final state of one planned output.
public struct VariantResult: Identifiable, Hashable, Sendable {
    /// Same as the `PlannedVariant.id`, so failed results can be retried.
    public let id: UUID
    public let inputID: UUID
    public let inputFileName: String
    public let sourceBytes: Int64
    public let label: String
    public let plannedFileName: String?
    public let outcome: VariantOutcome
    public let notes: [String]

    public init(id: UUID, inputID: UUID, inputFileName: String, sourceBytes: Int64, label: String, plannedFileName: String?, outcome: VariantOutcome, notes: [String] = []) {
        self.id = id
        self.inputID = inputID
        self.inputFileName = inputFileName
        self.sourceBytes = sourceBytes
        self.label = label
        self.plannedFileName = plannedFileName
        self.outcome = outcome
        self.notes = notes
    }

    public var outputFileName: String? {
        if case .written(let file) = outcome { return file.url.lastPathComponent }
        return plannedFileName
    }
}

/// Totals for an export, computed only from files that were actually written.
public struct BatchSummary: Codable, Hashable, Sendable {
    public var writtenCount: Int
    public var skippedCount: Int
    public var failedCount: Int
    public var cancelledCount: Int
    /// Distinct source images that produced at least one file.
    public var sourcesExported: Int
    /// Sum of the original sizes of `sourcesExported` (each source counted once).
    public var originalBytes: Int64
    /// Sum of the on-disk sizes of every written file, including every responsive variant.
    public var outputBytes: Int64

    public init(writtenCount: Int = 0, skippedCount: Int = 0, failedCount: Int = 0, cancelledCount: Int = 0, sourcesExported: Int = 0, originalBytes: Int64 = 0, outputBytes: Int64 = 0) {
        self.writtenCount = writtenCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
        self.cancelledCount = cancelledCount
        self.sourcesExported = sourcesExported
        self.originalBytes = originalBytes
        self.outputBytes = outputBytes
    }

    /// Positive when outputs are smaller. Negative values are reported as-is.
    public var bytesSaved: Int64 { originalBytes - outputBytes }

    /// Fraction of `originalBytes` saved (0.68 = 68 % smaller). Nil when nothing was written.
    public var fractionSaved: Double? {
        guard originalBytes > 0, writtenCount > 0 else { return nil }
        return Double(bytesSaved) / Double(originalBytes)
    }

    public var totalCount: Int { writtenCount + skippedCount + failedCount + cancelledCount }

    public static func make(_ results: [VariantResult]) -> BatchSummary {
        var summary = BatchSummary()
        var exportedSources: [UUID: Int64] = [:]
        for result in results {
            switch result.outcome {
            case .written(let file):
                summary.writtenCount += 1
                summary.outputBytes += file.bytes
                exportedSources[result.inputID] = result.sourceBytes
            case .skipped: summary.skippedCount += 1
            case .failed: summary.failedCount += 1
            case .cancelled: summary.cancelledCount += 1
            }
        }
        summary.sourcesExported = exportedSources.count
        summary.originalBytes = exportedSources.values.reduce(0, +)
        return summary
    }
}

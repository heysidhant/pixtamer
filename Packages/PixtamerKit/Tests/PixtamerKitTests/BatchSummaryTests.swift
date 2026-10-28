import Foundation
import Testing
@testable import PixtamerKit

@Suite("Export accounting and byte summaries")
struct BatchSummaryTests {
    func result(input: UUID, sourceBytes: Int64, _ outcome: VariantOutcome) -> VariantResult {
        VariantResult(id: UUID(), inputID: input, inputFileName: "x.jpg", sourceBytes: sourceBytes, label: "", plannedFileName: nil, outcome: outcome)
    }

    func written(_ bytes: Int64) -> VariantOutcome {
        .written(WrittenFile(url: URL(fileURLWithPath: "/tmp/x"), bytes: bytes, pixelSize: PixelSize(width: 1, height: 1), format: .webp))
    }

    @Test func countsEveryOutcome() {
        let a = UUID(), b = UUID(), c = UUID()
        let summary = BatchSummary.make([
            result(input: a, sourceBytes: 1000, written(200)),
            result(input: a, sourceBytes: 1000, written(300)),
            result(input: a, sourceBytes: 1000, .skipped(.wouldUpscale(requestedWidth: 1440, sourceWidth: 1000))),
            result(input: b, sourceBytes: 5000, .failed(ExportFailure(.decodeFailed, "bad"))),
            result(input: c, sourceBytes: 800, .cancelled),
        ])
        #expect(summary.writtenCount == 2)
        #expect(summary.skippedCount == 1)
        #expect(summary.failedCount == 1)
        #expect(summary.cancelledCount == 1)
        #expect(summary.totalCount == 5)
        #expect(summary.sourcesExported == 1)
        #expect(summary.originalBytes == 1000, "each exported source counted once; failed sources excluded")
        #expect(summary.outputBytes == 500)
        #expect(summary.bytesSaved == 500)
        #expect(summary.fractionSaved == 0.5)
    }

    @Test func growthIsReportedAsNegativeSavings() {
        let summary = BatchSummary.make([result(input: UUID(), sourceBytes: 100, written(250))])
        #expect(summary.bytesSaved == -150)
        #expect(summary.fractionSaved == -1.5)
    }

    @Test func nothingWrittenHasNoPercentage() {
        let summary = BatchSummary.make([result(input: UUID(), sourceBytes: 100, .failed(ExportFailure(.writeFailed, "x")))])
        #expect(summary.fractionSaved == nil)
        #expect(summary.originalBytes == 0)
        #expect(summary.outputBytes == 0)
    }

    @Test func emptyBatch() {
        let summary = BatchSummary.make([])
        #expect(summary.totalCount == 0)
        #expect(summary.fractionSaved == nil)
    }
}

@Suite("Diagnostics")
struct DiagnosticsTests {
    @Test func redactsHomePaths() {
        let text = Diagnostics.redact("Failed /Users/someone/Pictures/a.jpg and \(NSHomeDirectory())/b.png")
        #expect(!text.contains("/Users/someone"))
        #expect(!text.contains(NSHomeDirectory()))
        #expect(text.contains("a.jpg"))
    }

    @Test func reportListsFormatsAndCodesWithoutPaths() async {
        let capabilities = await FormatCapabilities.detected()
        let report = Diagnostics.report(
            appVersion: "1.0", build: "1",
            capabilities: capabilities,
            lastSummary: BatchSummary(writtenCount: 2, failedCount: 1, sourcesExported: 2, originalBytes: 10, outputBytes: 5),
            recentFailures: [ExportFailure(.sourceMissing, "a.jpg was moved or deleted after it was added.")]
        )
        #expect(report.contains("Pixtamer 1.0"))
        #expect(report.contains("WebP: available"))
        #expect(report.contains("PB-SRC-MISSING"))
        #expect(!report.contains("/Users/"))
    }
}

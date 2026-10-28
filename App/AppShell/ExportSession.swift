import Foundation
import Observation
import PixtamerKit

/// UI state for one export run (progress and results sheet).
@MainActor
@Observable
final class ExportSession: Identifiable {
    enum State: Equatable {
        case running
        case cancelling
        case finished(cancelled: Bool)
    }

    enum JobStatus: Equatable {
        case waiting, processing, done, partial, failed, skipped, cancelled
    }

    let id = UUID()
    let plan: ExportPlan
    let isRetry: Bool
    let startedAt = Date()
    private(set) var finishedAt: Date?
    private(set) var state: State = .running
    private(set) var results: [VariantResult] = []
    private(set) var resultsByInput: [UUID: [VariantResult]] = [:]
    /// Source file names currently being processed, in start order.
    private(set) var activeFiles: [(id: UUID, name: String)] = []
    private var run: ExportRun?

    init(plan: ExportPlan, isRetry: Bool) {
        self.plan = plan
        self.isRetry = isRetry
    }

    var isRunning: Bool {
        if case .finished = state { false } else { true }
    }

    var wasCancelled: Bool { state == .finished(cancelled: true) }

    var total: Int { plan.variants.count }
    var completed: Int { results.count }
    var fractionComplete: Double { total == 0 ? 1 : Double(completed) / Double(total) }
    var summary: BatchSummary { BatchSummary.make(results) }
    var failedResults: [VariantResult] { results.filter(\.outcome.isFailed) }
    var currentFileName: String? { activeFiles.last?.name }
    var elapsed: TimeInterval { (finishedAt ?? Date()).timeIntervalSince(startedAt) }

    func attach(_ run: ExportRun) {
        self.run = run
    }

    func cancel() {
        guard state == .running else { return }
        state = .cancelling
        run?.cancel()
    }

    func apply(_ event: ExportEvent) {
        switch event {
        case .jobStarted(let id, let name):
            activeFiles.append((id, name))
        case .variantFinished(let result):
            results.append(result)
            resultsByInput[result.inputID, default: []].append(result)
        case .jobFinished(let id):
            activeFiles.removeAll { $0.id == id }
        case .finished(let cancelled):
            activeFiles.removeAll()
            finishedAt = Date()
            state = .finished(cancelled: cancelled)
            run = nil
        }
    }

    func status(of job: PlannedJob) -> JobStatus {
        if activeFiles.contains(where: { $0.id == job.id }) { return .processing }
        guard let done = resultsByInput[job.id], done.count == job.variants.count else { return .waiting }
        let written = done.filter(\.outcome.isWritten).count
        let failed = done.filter(\.outcome.isFailed).count
        if failed > 0 { return written > 0 ? .partial : .failed }
        if written > 0 { return .done }
        if done.allSatisfy({ $0.outcome == .cancelled }) { return .cancelled }
        return .skipped
    }

    /// First folder that received output, for "Show in Finder".
    var firstWrittenFile: URL? {
        results.lazy.compactMap { if case .written(let f) = $0.outcome { f.url } else { nil } }.first
    }
}

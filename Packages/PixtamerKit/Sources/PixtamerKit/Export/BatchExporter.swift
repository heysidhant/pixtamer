import Foundation

public enum ExportEvent: Sendable {
    case jobStarted(inputID: UUID, fileName: String)
    case variantFinished(VariantResult)
    case jobFinished(inputID: UUID)
    /// Always the last event. `cancelled` is true when Cancel was requested.
    case finished(cancelled: Bool)
}

/// A running export. Iterate `events` for progress; call `cancel()` to stop scheduling new work.
/// Events keep arriving after cancellation until `.finished`, so every planned output gets a
/// final state.
public final class ExportRun: Sendable {
    public let events: AsyncStream<ExportEvent>
    private let task: Task<Void, Never>

    init(events: AsyncStream<ExportEvent>, task: Task<Void, Never>) {
        self.events = events
        self.task = task
    }

    public func cancel() {
        task.cancel()
    }
}

/// Runs an `ExportPlan` with bounded parallelism (one source image per task).
public struct BatchExporter: Sendable {
    /// Parallel jobs. Each job may hold a decoded full-size image plus one rendered variant, so
    /// this is kept low to bound memory with large photos.
    public static var defaultConcurrency: Int {
        max(1, min(4, ProcessInfo.processInfo.activeProcessorCount / 2))
    }

    public let processor: ImageProcessor
    public let maxConcurrentJobs: Int
    let workQueue: BlockingWorkQueue

    public init(processor: ImageProcessor = ImageProcessor(), maxConcurrentJobs: Int = BatchExporter.defaultConcurrency, workQueue: BlockingWorkQueue = .shared) {
        self.processor = processor
        self.maxConcurrentJobs = max(1, maxConcurrentJobs)
        self.workQueue = workQueue
    }

    public func start(_ plan: ExportPlan) -> ExportRun {
        let (stream, continuation) = AsyncStream.makeStream(of: ExportEvent.self, bufferingPolicy: .unbounded)
        let processor = processor
        let limit = maxConcurrentJobs
        let workQueue = workQueue
        let task = Task.detached(priority: .userInitiated) {
            await Self.run(plan: plan, processor: processor, workQueue: workQueue, limit: limit, continuation: continuation)
        }
        return ExportRun(events: stream, task: task)
    }

    /// Runs to completion and returns every result (used by tests and simple callers).
    public func run(_ plan: ExportPlan) async -> [VariantResult] {
        var results: [VariantResult] = []
        for await event in start(plan).events {
            if case .variantFinished(let result) = event { results.append(result) }
        }
        return results
    }

    private static func run(plan: ExportPlan, processor: ImageProcessor, workQueue: BlockingWorkQueue, limit: Int, continuation: AsyncStream<ExportEvent>.Continuation) async {
        var pending = plan.jobs.makeIterator()
        await withTaskGroup(of: (PlannedJob, [VariantResult]).self) { group in
            func schedule(_ job: PlannedJob) {
                continuation.yield(.jobStarted(inputID: job.input.id, fileName: job.input.fileName))
                group.addTask {
                    // Image work runs on GCD threads; cancellation reaches it through the flag.
                    let flag = CancellationFlag()
                    let results = await withTaskCancellationHandler {
                        await workQueue.run {
                            processor.process(job: job, settings: plan.settings, protectedPathKeys: plan.protectedPathKeys, isCancelled: { flag.isCancelled })
                        }
                    } onCancel: {
                        flag.cancel()
                    }
                    return (job, results)
                }
            }
            for _ in 0..<limit {
                guard let job = pending.next() else { break }
                schedule(job)
            }
            while let (job, results) = await group.next() {
                for result in results { continuation.yield(.variantFinished(result)) }
                continuation.yield(.jobFinished(inputID: job.input.id))
                if !Task.isCancelled, let next = pending.next() {
                    schedule(next)
                }
            }
        }

        // Jobs never started because of cancellation still get a final state.
        let cancelled = Task.isCancelled
        while let job = pending.next() {
            for variant in job.variants {
                let outcome: VariantOutcome = if case .skip(let reason) = variant.action { .skipped(reason) } else { .cancelled }
                continuation.yield(.variantFinished(VariantResult(
                    id: variant.id,
                    inputID: job.input.id,
                    inputFileName: job.input.fileName,
                    sourceBytes: job.input.fileSize,
                    label: variant.label,
                    plannedFileName: variant.plannedFileName,
                    outcome: outcome,
                    notes: variant.notes.map(\.message)
                )))
            }
        }
        continuation.yield(.finished(cancelled: cancelled))
        continuation.finish()
    }
}

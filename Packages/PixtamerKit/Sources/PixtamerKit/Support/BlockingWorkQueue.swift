import Foundation
import os

/// Runs blocking Image I/O and libwebp work on dedicated threads, outside both Swift's
/// cooperative pool and GCD's constrained worker pool.
///
/// Some system codecs fan work out to GCD internally and block until it finishes (the AVIF
/// encoder goes through VideoToolbox's `AV1EncoderSW` and waits on a dispatch group). If the
/// calling thread itself came from a constrained pool that is saturated, that internal work never
/// gets a thread and the encode deadlocks. This was reproduced twice during development (once on
/// cooperative threads, once on a concurrent GCD queue under `xcodebuild test`). A dedicated
/// thread per work item leaves the GCD pool free for the codec's own work.
///
/// Concurrency is bounded by the callers (export job limit, thumbnail limiter), so the number
/// of threads stays small. Thread start-up cost is negligible next to image work.
public final class BlockingWorkQueue: Sendable {
    public static let shared = BlockingWorkQueue(name: "com.heysidhant.Pixtamer.image-work")

    private let name: String
    private let qualityOfService: QualityOfService
    /// Image decoders can use more stack than the 512 KB default for secondary threads.
    private static let stackSize = 4 << 20

    public init(name: String, qualityOfService: QualityOfService = .userInitiated) {
        self.name = name
        self.qualityOfService = qualityOfService
    }

    /// Runs `work` on a new thread and suspends the caller until it finishes.
    public func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            start { continuation.resume(returning: work()) }
        }
    }

    private func start(_ body: @escaping @Sendable () -> Void) {
        let thread = Thread(block: body)
        thread.name = name
        thread.qualityOfService = qualityOfService
        thread.stackSize = Self.stackSize
        thread.start()
    }
}

/// Thread-safe flag used to pass Swift task cancellation into work running on other threads.
public final class CancellationFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    public init() {}

    public func cancel() {
        state.withLock { $0 = true }
    }

    public var isCancelled: Bool {
        state.withLock { $0 }
    }
}

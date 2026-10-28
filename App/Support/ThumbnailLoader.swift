import AppKit
import PixtamerKit

/// Loads and caches small, orientation-corrected thumbnails. Decoding happens on
/// `BlockingWorkQueue` with at most four decodes at once, so scrolling a large queue never
/// decodes full-resolution images or floods the CPU.
@MainActor
final class ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let cache = NSCache<NSString, CGImage>()
    private let limiter = AsyncLimiter(limit: 4)

    private init() {
        cache.countLimit = 2_000
    }

    func cached(_ url: URL, maxPixelSize: Int) -> CGImage? {
        cache.object(forKey: key(url, maxPixelSize))
    }

    func thumbnail(for url: URL, maxPixelSize: Int) async -> CGImage? {
        let key = key(url, maxPixelSize)
        if let image = cache.object(forKey: key) { return image }
        await limiter.acquire()
        defer { Task { await limiter.release() } }
        guard !Task.isCancelled else { return nil }
        let image = await BlockingWorkQueue.shared.run { Thumbnailer.thumbnail(for: url, maxPixelSize: maxPixelSize) }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    func evict(_ url: URL) {
        for size in [64, 96, 2048] { cache.removeObject(forKey: key(url, size)) }
    }

    private func key(_ url: URL, _ size: Int) -> NSString {
        "\(url.path)#\(size)" as NSString
    }
}

/// Simple async semaphore.
actor AsyncLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

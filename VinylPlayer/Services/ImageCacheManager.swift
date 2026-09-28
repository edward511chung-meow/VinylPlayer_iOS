import SwiftUI
import CryptoKit

/// In-memory + disk image cache with automatic retry on failure.
final class ImageCacheManager {
    static let shared = ImageCacheManager()

    // MARK: - Memory Cache

    private let memoryCache = NSCache<NSString, UIImage>()

    // MARK: - Disk Cache

    private let diskCacheURL: URL
    private let fileManager = FileManager.default

    // MARK: - In-flight deduplication

    /// Prevents duplicate network requests for the same URL.
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]
    private let lock = NSLock()

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheURL = caches.appendingPathComponent("AlbumArtworkCache", isDirectory: true)
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        // Allow up to ~200 images in memory
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }

    // MARK: - Public API

    /// Load image from cache (memory → disk) or fetch from network with retry.
    func image(for urlString: String) async -> UIImage? {
        let key = cacheKey(for: urlString)

        // 1. Memory cache
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        // 2. Disk cache
        if let diskImage = loadFromDisk(key: key) {
            memoryCache.setObject(diskImage, forKey: key as NSString, cost: diskImage.pngData()?.count ?? 0)
            return diskImage
        }

        // 3. Deduplicate in-flight requests
        lock.lock()
        if let existing = inFlightTasks[key] {
            lock.unlock()
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            let image = await fetchWithRetry(urlString: urlString, retries: 3)
            if let image {
                self.memoryCache.setObject(image, forKey: key as NSString, cost: image.pngData()?.count ?? 0)
                self.saveToDisk(image: image, key: key)
            }
            self.lock.lock()
            self.inFlightTasks.removeValue(forKey: key)
            self.lock.unlock()
            return image
        }
        inFlightTasks[key] = task
        lock.unlock()

        return await task.value
    }

    /// Prefetch multiple URLs (fire-and-forget).
    func prefetch(urls: [String]) {
        for url in urls {
            Task { _ = await image(for: url) }
        }
    }

    /// Clear all caches.
    func clearAll() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: diskCacheURL)
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    // MARK: - Network Fetch with Retry

    private func fetchWithRetry(urlString: String, retries: Int) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }

        for attempt in 0..<retries {
            do {
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = 15
                config.timeoutIntervalForResource = 30
                let session = URLSession(configuration: config)

                let (data, response) = try await session.data(from: url)

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    print("[ImageCache] HTTP \(httpResponse.statusCode) for \(urlString)")
                    if attempt < retries - 1 {
                        try await Task.sleep(nanoseconds: UInt64((attempt + 1) * 500_000_000))
                    }
                    continue
                }

                if let image = UIImage(data: data) {
                    return image
                }
            } catch {
                print("[ImageCache] Attempt \(attempt + 1)/\(retries) failed for \(urlString): \(error.localizedDescription)")
                if attempt < retries - 1 {
                    try? await Task.sleep(nanoseconds: UInt64((attempt + 1) * 500_000_000))
                }
            }
        }
        return nil
    }

    // MARK: - Disk Helpers

    private func cacheKey(for urlString: String) -> String {
        let digest = SHA256.hash(data: Data(urlString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func diskURL(for key: String) -> URL {
        diskCacheURL.appendingPathComponent(key)
    }

    private func loadFromDisk(key: String) -> UIImage? {
        let url = diskURL(for: key)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    private func saveToDisk(image: UIImage, key: String) {
        let url = diskURL(for: key)
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

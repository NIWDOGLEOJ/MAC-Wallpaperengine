//
//  MotionBGsThumbnailCache.swift
//  WallpaperEngineCore
//
//  Ultra-efficient bounded memory and disk thumbnail loader for MotionBGs.
//  Limits concurrent downloads, deduplicates requests, cancels obsolete work,
//  and downsamples images directly via ImageIO to minimize CPU/RAM usage.
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import OSLog

private struct SendableImage: @unchecked Sendable {
    let image: NSImage?
}

public final class MotionBGsThumbnailCache: @unchecked Sendable {
    public static let shared = MotionBGsThumbnailCache()

    private let memoryCache = NSCache<NSURL, NSImage>()
    private let fileManager = FileManager.default
    private let diskCacheURL: URL
    private let session: URLSession
    private let queue = DispatchQueue(label: "com.wallpaperengine.motionbgs.thumbnails", qos: .utility)
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "MotionBGsThumbnailCache")

    // Actor-isolated in-flight task deduplication & concurrency limiter
    private actor InFlightManager {
        private var tasks: [URL: Task<SendableImage, Never>] = [:]
        private var activeCount: Int = 0
        private let maxConcurrent: Int = 6
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func task(for url: URL) -> Task<SendableImage, Never>? {
            tasks[url]
        }

        func register(task: Task<SendableImage, Never>, for url: URL) {
            tasks[url] = task
        }

        func remove(url: URL, task: Task<SendableImage, Never>) {
            if tasks[url] == task {
                tasks.removeValue(forKey: url)
            }
        }

        func cancel(url: URL) {
            if let task = tasks.removeValue(forKey: url) {
                task.cancel()
            }
        }

        func cancelAll() {
            for (_, t) in tasks {
                t.cancel()
            }
            tasks.removeAll()
        }

        func acquireSlot() async {
            if activeCount < maxConcurrent {
                activeCount += 1
                return
            }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func releaseSlot() {
            if !waiters.isEmpty {
                let next = waiters.removeFirst()
                next.resume()
            } else {
                activeCount = max(0, activeCount - 1)
            }
        }
    }

    private let inFlightManager = InFlightManager()
    private let maxDiskSizeBytes: Int64 = 50 * 1024 * 1024 // 50 MB disk cache limit

    public init() {
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let diskURL = cachesURL.appendingPathComponent("WallpaperEngineCore/MotionBGsThumbnails", isDirectory: true)
        self.diskCacheURL = diskURL
        try? fileManager.createDirectory(at: diskURL, withIntermediateDirectories: true)

        // Bounded memory cache: 40 MB max, 100 thumbnails max
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 40 * 1024 * 1024

        // Dedicated URLSession with bounded URLCache for images
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 15.0
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    public func image(for url: URL, targetSize: CGSize = CGSize(width: 364, height: 205)) async -> NSImage? {
        let nsURL = url as NSURL

        // 1. Check in-memory cache (zero disk/network overhead)
        if let cached = memoryCache.object(forKey: nsURL) {
            return cached
        }

        // 2. Check disk cache
        let diskFile = diskPath(for: url)
        if fileManager.fileExists(atPath: diskFile.path),
           let diskImage = loadAndDownsample(from: diskFile, targetSize: targetSize) {
            memoryCache.setObject(diskImage, forKey: nsURL, cost: cost(for: diskImage))
            return diskImage
        }

        // 3. Request deduplication: check if task is already in-flight for this URL
        if let existingTask = await inFlightManager.task(for: url) {
            return await existingTask.value.image
        }

        // Create new cooperative cancellable task with concurrency gating
        let manager = inFlightManager
        let downloadTask = Task<SendableImage, Never> { [weak self] in
            guard let self = self else { return SendableImage(image: nil) }

            await manager.acquireSlot()
            defer {
                Task {
                    await manager.releaseSlot()
                }
            }

            if Task.isCancelled { return SendableImage(image: nil) }

            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 8.0
                request.cachePolicy = .useProtocolCachePolicy

                let (data, response) = try await self.session.data(for: request)
                if Task.isCancelled { return SendableImage(image: nil) }

                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    return SendableImage(image: nil)
                }

                // Write raw network data directly to disk cache (zero TIFF/JPEG re-encoding overhead)
                self.queue.async { [weak self] in
                    guard let self = self else { return }
                    try? data.write(to: diskFile, options: .atomic)
                    self.trimDiskCacheIfNeeded()
                }

                if Task.isCancelled { return SendableImage(image: nil) }

                guard let decoded = self.downsample(data: data, targetSize: targetSize) else {
                    return SendableImage(image: nil)
                }

                self.memoryCache.setObject(decoded, forKey: nsURL, cost: self.cost(for: decoded))
                return SendableImage(image: decoded)
            } catch {
                return SendableImage(image: nil)
            }
        }

        await inFlightManager.register(task: downloadTask, for: url)
        let result = await downloadTask.value.image
        await inFlightManager.remove(url: url, task: downloadTask)

        return result
    }

    public func cancel(for url: URL) {
        Task { [inFlightManager] in
            await inFlightManager.cancel(url: url)
        }
    }

    public func cancelAll() {
        Task { [inFlightManager] in
            await inFlightManager.cancelAll()
        }
    }

    public func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    public func purgeAll() {
        cancelAll()
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: diskCacheURL)
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    // MARK: - Disk Cache Trimming

    private func trimDiskCacheIfNeeded() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: diskCacheURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        var fileInfos: [(url: URL, size: Int64, date: Date)] = []
        var totalSize: Int64 = 0

        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  let date = values.contentModificationDate else { continue }
            let size64 = Int64(size)
            totalSize += size64
            fileInfos.append((url: file, size: size64, date: date))
        }

        // If exceeds 50 MB, prune oldest 30% of files
        if totalSize > maxDiskSizeBytes {
            fileInfos.sort(by: { $0.date < $1.date }) // oldest first
            var prunedSize: Int64 = 0
            let targetPrune = totalSize - (maxDiskSizeBytes * 7 / 10)
            for info in fileInfos {
                if prunedSize >= targetPrune { break }
                try? fileManager.removeItem(at: info.url)
                prunedSize += info.size
            }
            logger.notice("Trimmed disk cache: pruned \(prunedSize / 1024) KB of thumbnail files.")
        }
    }

    // MARK: - Downsampling via ImageIO

    public func downsample(data: Data, targetSize: CGSize) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let maxPixelSize = max(targetSize.width, targetSize.height) * 2.0 // 2x for Retina display
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgThumb, size: targetSize)
    }

    private func loadAndDownsample(from fileURL: URL, targetSize: CGSize) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        let maxPixelSize = max(targetSize.width, targetSize.height) * 2.0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgThumb, size: targetSize)
    }

    // MARK: - Utilities

    private func diskPath(for url: URL) -> URL {
        let key = cacheKey(for: url)
        return diskCacheURL.appendingPathComponent("\(key).jpg")
    }

    private func cacheKey(for url: URL) -> String {
        let path = url.absoluteString
        var hash: UInt64 = 5381
        for byte in path.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }

    private func cost(for image: NSImage) -> Int {
        let w = Int(image.size.width)
        let h = Int(image.size.height)
        return w * h * 4
    }
}

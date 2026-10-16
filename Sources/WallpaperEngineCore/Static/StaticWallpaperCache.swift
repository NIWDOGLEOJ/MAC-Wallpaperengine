//
//  StaticWallpaperCache.swift
//  WallpaperEngineCore
//
//  Bounded, thread-safe memory cache for decoded static wallpaper CGImages
//  with automatic eviction under memory pressure.
//

import CoreGraphics
import Foundation
import OSLog

public final class StaticWallpaperCache: @unchecked Sendable {
    public static let shared = StaticWallpaperCache()

    private let cache = NSCache<NSURL, AnyObject>()
    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "StaticWallpaperCache")

    public init(countLimit: Int = 10, totalCostLimitMB: Int = 120) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimitMB * 1024 * 1024
    }

    public func image(for url: URL) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let wrapper = cache.object(forKey: url as NSURL) as? ImageWrapper {
            return wrapper.image
        }
        return nil
    }

    public func setImage(_ image: CGImage, for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        let cost = image.bytesPerRow * image.height
        cache.setObject(ImageWrapper(image: image), forKey: url as NSURL, cost: cost)
    }

    public func removeImage(for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        cache.removeObject(forKey: url as NSURL)
    }

    public func purge() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAllObjects()
        logger.notice("Purged all cached static wallpaper images.")
    }

    public func clear() {
        purge()
    }


    public func trim(toRatio ratio: Double = 0.5) {
        lock.lock()
        defer { lock.unlock() }
        // Evicts proportional capacity
        let currentLimit = cache.countLimit
        let currentCost = cache.totalCostLimit
        cache.countLimit = max(1, Int(Double(currentLimit) * ratio))
        cache.totalCostLimit = max(1024 * 1024, Int(Double(currentCost) * ratio))
        cache.countLimit = currentLimit
        cache.totalCostLimit = currentCost
        logger.info("Trimmed static wallpaper cache to \(ratio * 100)%")
    }

    private final class ImageWrapper {
        let image: CGImage
        init(image: CGImage) {
            self.image = image
        }
    }
}

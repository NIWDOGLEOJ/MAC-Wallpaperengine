//
//  WallpaperThumbnailCache.swift
//  WallpaperEngineCore
//
//  Bounded disk and memory thumbnail cache for library wallpapers.
//  Generates low-overhead thumbnails on demand via ImageIO and AVFoundation.
//

import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import OSLog

public final class WallpaperThumbnailCache: @unchecked Sendable {
    public static let shared = WallpaperThumbnailCache()

    private let memoryCache = NSCache<NSURL, NSImage>()
    private let fileManager = FileManager.default
    private let diskCacheURL: URL
    private let queue = DispatchQueue(label: "com.wallpaperengine.thumbnails", qos: .utility)
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "ThumbnailCache")

    public init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.diskCacheURL = appSupport.appendingPathComponent("WallpaperEngineCore/Thumbnails", isDirectory: true)
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        memoryCache.countLimit = 150
        memoryCache.totalCostLimit = 60 * 1024 * 1024 // 60 MB
    }

    public func thumbnail(for url: URL, targetSize: CGSize = CGSize(width: 320, height: 180)) async -> NSImage? {
        let nsURL = url as NSURL
        if let memImage = memoryCache.object(forKey: nsURL) {
            return memImage
        }

        let diskFile = diskCacheURL.appendingPathComponent("\(cacheKey(for: url)).jpg")
        if let diskImage = NSImage(contentsOf: diskFile) {
            memoryCache.setObject(diskImage, forKey: nsURL)
            return diskImage
        }

        // Generate asynchronously
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }

                let ext = url.pathExtension.lowercased()
                var generated: NSImage? = nil

                if ["mp4", "mov", "m4v"].contains(ext) {
                    generated = self.generateVideoThumbnail(for: url, targetSize: targetSize)
                } else {
                    generated = self.generateImageThumbnail(for: url, targetSize: targetSize)
                }

                if let img = generated {
                    self.memoryCache.setObject(img, forKey: nsURL)
                    if let data = img.tiffRepresentation,
                       let rep = NSBitmapImageRep(data: data),
                       let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                        try? jpegData.write(to: diskFile, options: .atomic)
                    }
                }

                continuation.resume(returning: generated)
            }
        }
    }

    private func generateImageThumbnail(for url: URL, targetSize: CGSize) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let maxDim = max(targetSize.width, targetSize.height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDim
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgThumb, size: targetSize)
    }

    private func generateVideoThumbnail(for url: URL, targetSize: CGSize) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = targetSize
        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            return NSImage(cgImage: cgImage, size: targetSize)
        } catch {
            return nil
        }
    }

    public func purge() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: diskCacheURL)
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        logger.notice("Purged thumbnail cache.")
    }

    public func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }


    private func cacheKey(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        var hash: UInt64 = 5381
        for byte in path.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }
}

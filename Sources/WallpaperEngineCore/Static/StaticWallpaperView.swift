//
//  StaticWallpaperView.swift
//  WallpaperEngineCore
//
//  Feature: Ultra-optimized static wallpaper display with strictly 0% continuous CPU and 0% GPU redraws.
//  Uses hardware-backed CALayer scanout with aspect-ratio-aware positioning and ImageIO decoding.
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import OSLog

@MainActor
public final class StaticWallpaperView: NSView {
    public enum ScalingMode: String, Codable, Sendable, CaseIterable {
        case aspectFill = "Fill"
        case aspectFit = "Fit"
        case stretch = "Stretch"
        case center = "Center"

        public var contentsGravity: CALayerContentsGravity {
            switch self {
            case .aspectFill: return .resizeAspectFill
            case .aspectFit: return .resizeAspect
            case .stretch: return .resize
            case .center: return .center
            }
        }
    }

    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "StaticWallpaperView")
    public private(set) var currentImageURL: URL?
    public private(set) var currentCGImage: CGImage?
    public var scalingMode: ScalingMode = .aspectFill {
        didSet {
            updateLayerGravity()
        }
    }

    public var contentsRect: CGRect {
        get { layer?.contentsRect ?? CGRect(x: 0, y: 0, width: 1, height: 1) }
        set { layer?.contentsRect = newValue }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        autoresizingMask = [.width, .height]
        updateLayerGravity()
    }

    private func updateLayerGravity() {
        layer?.contentsGravity = scalingMode.contentsGravity
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let window = window {
            layer?.contentsScale = window.backingScaleFactor
        }
    }

    /// Loads a static wallpaper asynchronously from a local file URL with ImageIO decoding and caching.
    public func loadWallpaper(
        from url: URL,
        cache: StaticWallpaperCache = .shared,
        maxPixelDimension: Int? = 4096
    ) async throws -> CGImage {
        currentImageURL = url

        // 1. Check in-memory cache
        if let cached = cache.image(for: url) {
            applyImage(cached)
            return cached
        }

        // 2. Decode off main thread using ImageIO
        let decodedImage = try await Task.detached(priority: .userInitiated) { () -> CGImage in
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw CocoaError(.fileNoSuchFile)
            }

            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                throw CocoaError(.fileReadCorruptFile)
            }

            var options: [CFString: Any] = [
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldCacheImmediately: true
            ]

            if let maxDim = maxPixelDimension {
                options[kCGImageSourceThumbnailMaxPixelSize] = maxDim
                options[kCGImageSourceCreateThumbnailFromImageAlways] = true
                options[kCGImageSourceCreateThumbnailWithTransform] = true
                if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                    return thumb
                }
            }

            guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return image
        }.value

        // 3. Cache and apply
        cache.setImage(decodedImage, for: url)
        applyImage(decodedImage)
        return decodedImage
    }

    /// Directly applies a pre-decoded CGImage to the layer.
    public func applyImage(_ image: CGImage) {
        self.currentCGImage = image
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = image
        if let window = window {
            layer?.contentsScale = window.backingScaleFactor
        }
        updateLayerGravity()
        CATransaction.commit()
    }

    public func clear() {
        currentImageURL = nil
        currentCGImage = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = nil
        CATransaction.commit()
    }
}

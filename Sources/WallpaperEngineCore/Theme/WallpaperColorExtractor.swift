//
//  WallpaperColorExtractor.swift
//  WallpaperEngineCore
//
//  Feature: Automatic Wallpaper-Aware Dynamic Widget Theming
//  Hardware-accelerated color extraction engine with downsampling,
//  multi-role palette clustering, vibrancy scoring, and thread-safe caching.
//

import AppKit
import AVFoundation
import CoreGraphics
import Foundation

// MARK: - Extracted Palette Representation

public struct ExtractedPalette: Sendable, Equatable {
    public let dominant: CodableRGBA
    public let vibrant: CodableRGBA
    public let secondary: CodableRGBA
    public let darkMuted: CodableRGBA
    public let lightMuted: CodableRGBA
    public let averageLuminance: Double
    public let isPredominantlyDark: Bool

    public init(
        dominant: CodableRGBA,
        vibrant: CodableRGBA,
        secondary: CodableRGBA,
        darkMuted: CodableRGBA,
        lightMuted: CodableRGBA,
        averageLuminance: Double,
        isPredominantlyDark: Bool
    ) {
        self.dominant = dominant
        self.vibrant = vibrant
        self.secondary = secondary
        self.darkMuted = darkMuted
        self.lightMuted = lightMuted
        self.averageLuminance = averageLuminance
        self.isPredominantlyDark = isPredominantlyDark
    }

    public static let fallback = ExtractedPalette(
        dominant: CodableRGBA(red: 0.18, green: 0.90, blue: 0.62),
        vibrant: CodableRGBA(red: 0.00, green: 0.94, blue: 1.00),
        secondary: CodableRGBA(red: 0.45, green: 0.40, blue: 0.95),
        darkMuted: CodableRGBA(red: 0.08, green: 0.10, blue: 0.14),
        lightMuted: CodableRGBA(red: 0.92, green: 0.95, blue: 0.98),
        averageLuminance: 0.15,
        isPredominantlyDark: true
    )
}

// MARK: - Extractor Protocol

public protocol WallpaperColorExtractorProtocol: Sendable {
    func extractPalette(from image: CGImage) -> ExtractedPalette
    func extractPalette(fromImageAt url: URL) async -> ExtractedPalette?
    func extractPalette(fromVideoAt url: URL, at time: CMTime) async -> ExtractedPalette?
}

// MARK: - Production Color Extraction Engine

public final class WallpaperColorExtractor: WallpaperColorExtractorProtocol, @unchecked Sendable {

    public static let shared = WallpaperColorExtractor()

    private let cacheLock = NSLock()
    private var paletteCache: [String: ExtractedPalette] = [:]
    private var colorCache: [String: NSColor] = [:]

    // Curated vibrant accent palette for known library 4K wallpapers
    private let curatedLibraryColors: [String: NSColor] = [
        "wandering-samurai": NSColor(srgbRed: 0.92, green: 0.32, blue: 0.05, alpha: 1.0),
        "koi-pond-serenity": NSColor(srgbRed: 0.02, green: 0.60, blue: 0.88, alpha: 1.0),
        "large-sakura-tree": NSColor(srgbRed: 0.94, green: 0.28, blue: 0.52, alpha: 1.0),
        "orange-train-at-sunset": NSColor(srgbRed: 0.98, green: 0.56, blue: 0.00, alpha: 1.0),
        "sabrina-carpenter-kissing-screen": NSColor(srgbRed: 0.88, green: 0.12, blue: 0.40, alpha: 1.0)
    ]

    // Procedural Shader Vibrant Color Palettes
    public static let auroraAccent = NSColor(srgbRed: 0.18, green: 0.90, blue: 0.62, alpha: 1.0)
    public static let starfieldAccent = NSColor(srgbRed: 0.45, green: 0.40, blue: 0.95, alpha: 1.0)
    public static let gradientFlowAccent = NSColor(srgbRed: 1.00, green: 0.35, blue: 0.47, alpha: 1.0)
    public static let cyberpunkGridAccent = NSColor(srgbRed: 0.00, green: 0.94, blue: 1.00, alpha: 1.0)
    public static let bokehAccent = NSColor(srgbRed: 1.00, green: 0.67, blue: 0.20, alpha: 1.0)

    public init() {}

    // MARK: - Core Palette Extraction

    public func extractPalette(from image: CGImage) -> ExtractedPalette {
        let sampleWidth = 32
        let sampleHeight = 32
        let totalPixels = sampleWidth * sampleHeight
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: totalPixels * 4)

        guard let context = CGContext(
            data: &rawData,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: sampleWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return .fallback
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        var totalLum: Double = 0.0
        var validPixelCount: Double = 0.0

        struct ColorBucket {
            var sumR: Double = 0.0
            var sumG: Double = 0.0
            var sumB: Double = 0.0
            var count: Int = 0
            var maxVibrancy: Double = 0.0
        }

        // 16 Hue Buckets (22.5 deg each) + 1 Grayscale Bucket
        var buckets = [ColorBucket](repeating: ColorBucket(), count: 17)

        for i in 0..<totalPixels {
            let offset = i * 4
            let r = Double(rawData[offset]) / 255.0
            let g = Double(rawData[offset + 1]) / 255.0
            let b = Double(rawData[offset + 2]) / 255.0
            let a = Double(rawData[offset + 3]) / 255.0

            guard a > 0.5 else { continue }

            let nsColor = NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1.0)
            let h = Double(nsColor.hueComponent)
            let s = Double(nsColor.saturationComponent)
            let v = Double(nsColor.brightnessComponent)

            // Linearized relative luminance per pixel
            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            totalLum += lum
            validPixelCount += 1.0

            let bucketIdx: Int
            if s < 0.12 {
                bucketIdx = 16 // Grayscale
            } else {
                bucketIdx = min(15, max(0, Int(h * 16.0)))
            }

            buckets[bucketIdx].sumR += r
            buckets[bucketIdx].sumG += g
            buckets[bucketIdx].sumB += b
            buckets[bucketIdx].count += 1

            let vibrancy = pow(s, 1.2) * pow(v, 0.8)
            if vibrancy > buckets[bucketIdx].maxVibrancy {
                buckets[bucketIdx].maxVibrancy = vibrancy
            }
        }

        let avgLum = validPixelCount > 0 ? (totalLum / validPixelCount) : 0.5
        let isPredomDark = avgLum < 0.45

        // Determine dominant color (highest pixel count)
        var dominantIdx = 0
        var maxCount = -1
        for (idx, b) in buckets.enumerated() {
            if b.count > maxCount {
                maxCount = b.count
                dominantIdx = idx
            }
        }

        // Determine vibrant color (highest vibrancy score with balanced brightness)
        var bestVibrantIdx = dominantIdx
        var bestVibrancy: Double = -1.0
        for idx in 0..<16 { // Check chromatic buckets
            let b = buckets[idx]
            guard b.count > 4 else { continue }
            let countWeight = min(1.0, Double(b.count) / (validPixelCount * 0.15))
            let score = b.maxVibrancy * (0.6 + 0.4 * countWeight)
            if score > bestVibrancy {
                bestVibrancy = score
                bestVibrantIdx = idx
            }
        }

        func rgba(from bucket: ColorBucket, fallback: CodableRGBA) -> CodableRGBA {
            guard bucket.count > 0 else { return fallback }
            let r = bucket.sumR / Double(bucket.count)
            let g = bucket.sumG / Double(bucket.count)
            let b = bucket.sumB / Double(bucket.count)
            return CodableRGBA(red: r, green: g, blue: b)
        }

        let dominantColor = rgba(from: buckets[dominantIdx], fallback: CodableRGBA(nsColor: Self.auroraAccent))
        var vibrantColor = rgba(from: buckets[bestVibrantIdx], fallback: dominantColor)

        // Ensure vibrant color has sufficient saturation for attractive UI
        let nsVibrant = vibrantColor.nsColor
        if nsVibrant.saturationComponent < 0.25 {
            // Boost saturation slightly if muted
            let boosted = NSColor(
                calibratedHue: nsVibrant.hueComponent,
                saturation: max(0.40, nsVibrant.saturationComponent * 1.5),
                brightness: min(0.95, max(0.60, nsVibrant.brightnessComponent)),
                alpha: 1.0
            )
            vibrantColor = CodableRGBA(nsColor: boosted)
        }

        // Secondary color: rotate hue by ~30 deg
        let secondary = CodableRGBA(nsColor: Self.secondaryAccentColor(for: vibrantColor.nsColor))

        // Dark Muted anchor: deep rich surface tint
        let darkMutedNS = NSColor(
            calibratedHue: nsVibrant.hueComponent,
            saturation: min(0.40, nsVibrant.saturationComponent * 0.6),
            brightness: 0.14,
            alpha: 1.0
        )
        let darkMuted = CodableRGBA(nsColor: darkMutedNS)

        // Light Muted anchor: clean crisp frosted glass tint
        let lightMutedNS = NSColor(
            calibratedHue: nsVibrant.hueComponent,
            saturation: min(0.25, nsVibrant.saturationComponent * 0.3),
            brightness: 0.94,
            alpha: 1.0
        )
        let lightMuted = CodableRGBA(nsColor: lightMutedNS)

        return ExtractedPalette(
            dominant: dominantColor,
            vibrant: vibrantColor,
            secondary: secondary,
            darkMuted: darkMuted,
            lightMuted: lightMuted,
            averageLuminance: avgLum,
            isPredominantlyDark: isPredomDark
        )
    }

    // MARK: - Synchronous Cache Access Helpers (Async-safe scoped)

    public func getCachedPalette(for key: String) -> ExtractedPalette? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return paletteCache[key]
    }

    public func setCachedPalette(_ palette: ExtractedPalette, for key: String, colorKey: String? = nil) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        paletteCache[key] = palette
        colorCache[key] = palette.vibrant.nsColor
        if let cKey = colorKey {
            colorCache[cKey] = palette.vibrant.nsColor
        }
    }

    // MARK: - NSImage Extraction with Cache

    public func extractPalette(from nsImage: NSImage, cacheKey: String? = nil) -> ExtractedPalette? {
        if let key = cacheKey, let cached = getCachedPalette(for: key) {
            return cached
        }

        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let palette = extractPalette(from: cgImage)
        if let key = cacheKey {
            setCachedPalette(palette, for: key)
        }
        return palette
    }

    // MARK: - Still Image Extraction with Cache

    public func extractPalette(fromImageAt url: URL) async -> ExtractedPalette? {
        let key = url.path
        if let cached = getCachedPalette(for: key) {
            return cached
        }

        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }

        let palette = extractPalette(from: cgImage)
        setCachedPalette(palette, for: key)
        return palette
    }

    // MARK: - Video Keyframe Extraction with Cache

    public func extractPalette(fromVideoAt url: URL, at time: CMTime = CMTime(seconds: 1.0, preferredTimescale: 600)) async -> ExtractedPalette? {
        let key = "\(url.path)@\(Int(time.seconds * 10))"
        if let cached = getCachedPalette(for: key) {
            return cached
        }

        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 64, height: 64)

        do {
            let cgImage = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
                generator.generateCGImageAsynchronously(for: time) { image, _, error in
                    if let img = image {
                        continuation.resume(returning: img)
                    } else {
                        continuation.resume(throwing: error ?? NSError(domain: "WallpaperColorExtractor", code: -1))
                    }
                }
            }

            let palette = extractPalette(from: cgImage)
            setCachedPalette(palette, for: key, colorKey: url.path)
            return palette
        } catch {
            return nil
        }
    }

    // MARK: - Legacy Compatibility API

    public func dominantAccentColor(for activeWallpaper: ActiveWallpaperType) -> NSColor {
        switch activeWallpaper {
        case .shader(let preset):
            return accentColor(for: preset)

        case .customShader(let path):
            cacheLock.lock()
            if let cached = colorCache[path] {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()
            return NSColor(srgbRed: 0.00, green: 0.88, blue: 0.98, alpha: 1.0)

        case .video(let path):
            cacheLock.lock()
            if let cached = colorCache[path] {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()

            let url = URL(fileURLWithPath: path)
            let filename = url.deletingPathExtension().lastPathComponent.lowercased()

            for (key, color) in curatedLibraryColors {
                if filename.contains(key) {
                    cacheLock.lock()
                    colorCache[path] = color
                    cacheLock.unlock()
                    return color
                }
            }

            Task { [weak self] in
                _ = await self?.extractAccentColor(fromVideoAt: url)
            }
            return NSColor(srgbRed: 0.00, green: 0.82, blue: 1.00, alpha: 1.0)

        case .parallax(let path):
            cacheLock.lock()
            if let cached = colorCache[path] {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()

            let url = URL(fileURLWithPath: path)
            if let extracted = extractAccentColor(fromImageAt: url) {
                cacheLock.lock()
                colorCache[path] = extracted
                cacheLock.unlock()
                return extracted
            }
            return NSColor(srgbRed: 0.35, green: 0.65, blue: 1.00, alpha: 1.0)

        case .none:
            return NSColor.systemTeal
        }
    }

    public func accentColor(for preset: ProceduralShaderPreset) -> NSColor {
        switch preset {
        case .aurora: return Self.auroraAccent
        case .starfield: return Self.starfieldAccent
        case .gradientFlow: return Self.gradientFlowAccent
        case .cyberpunkGrid: return Self.cyberpunkGridAccent
        case .bokeh: return Self.bokehAccent
        }
    }

    public func extractAccentColor(fromVideoAt url: URL) async -> NSColor {
        if let pal = await extractPalette(fromVideoAt: url) {
            return pal.vibrant.nsColor
        }
        return NSColor(srgbRed: 0.0, green: 0.75, blue: 0.95, alpha: 1.0)
    }

    public func extractAccentColor(fromImageAt url: URL) -> NSColor? {
        cacheLock.lock()
        if let cached = colorCache[url.path] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }

        let dominant = extractDominantVibrantColor(from: cgImage)
        cacheLock.lock()
        colorCache[url.path] = dominant
        cacheLock.unlock()
        return dominant
    }

    public func extractDominantVibrantColor(from image: CGImage) -> NSColor {
        let palette = extractPalette(from: image)
        return palette.vibrant.nsColor
    }

    public static func secondaryAccentColor(for color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let newH = (h + 0.08).truncatingRemainder(dividingBy: 1.0)
        return NSColor(calibratedHue: newH, saturation: max(0.5, s), brightness: max(0.6, b), alpha: a)
    }

    public static func complementaryAccentColor(for color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let newH = (h + 0.5).truncatingRemainder(dividingBy: 1.0)
        return NSColor(calibratedHue: newH, saturation: max(0.5, s), brightness: max(0.6, b), alpha: a)
    }
}

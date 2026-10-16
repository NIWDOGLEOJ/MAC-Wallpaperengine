//
//  WallpaperColorExtractor.swift
//  WallpaperEngineCore
//
//  Intelligent, hardware-accelerated dominant accent color extraction for
//  live wallpapers (procedural Metal shaders, 4K video frames, and 3D parallax photos).
//

import AppKit
import AVFoundation
import CoreGraphics
import Foundation

@MainActor
public final class WallpaperColorExtractor {

    public static let shared = WallpaperColorExtractor()

    // In-memory cache to guarantee instantaneous lookups with zero disk/GPU thrashing
    private var colorCache: [String: NSColor] = [:]

    // Curated vibrant accent palette for known library 4K wallpapers
    private let curatedLibraryColors: [String: NSColor] = [
        "wandering-samurai": NSColor(srgbRed: 0.92, green: 0.32, blue: 0.05, alpha: 1.0), // Sunset Amber / Crimson
        "koi-pond-serenity": NSColor(srgbRed: 0.02, green: 0.60, blue: 0.88, alpha: 1.0), // Aquatic Azure / Deep Cyan
        "large-sakura-tree": NSColor(srgbRed: 0.94, green: 0.28, blue: 0.52, alpha: 1.0), // Sakura Blossom Rose
        "orange-train-at-sunset": NSColor(srgbRed: 0.98, green: 0.56, blue: 0.00, alpha: 1.0), // Golden Hour Sunset Orange
        "sabrina-carpenter-kissing-screen": NSColor(srgbRed: 0.88, green: 0.12, blue: 0.40, alpha: 1.0) // Neon Passion Pink
    ]

    // Procedural Shader Vibrant Color Palettes
    public static let auroraAccent = NSColor(srgbRed: 0.18, green: 0.90, blue: 0.62, alpha: 1.0) // Northern Emerald Teal (#2EE59D)
    public static let starfieldAccent = NSColor(srgbRed: 0.45, green: 0.40, blue: 0.95, alpha: 1.0) // Cosmic Indigo Violet (#7367F0)
    public static let gradientFlowAccent = NSColor(srgbRed: 1.00, green: 0.35, blue: 0.47, alpha: 1.0) // Sunset Coral Magenta (#FF5A78)
    public static let cyberpunkGridAccent = NSColor(srgbRed: 0.00, green: 0.94, blue: 1.00, alpha: 1.0) // Electric Cyber Cyan (#00F0FF)
    public static let bokehAccent = NSColor(srgbRed: 1.00, green: 0.67, blue: 0.20, alpha: 1.0) // Golden Sunset Peach (#FFAA33)

    public init() {}

    // MARK: - Synchronous Accent Color Resolution

    public func dominantAccentColor(for activeWallpaper: ActiveWallpaperType) -> NSColor {
        switch activeWallpaper {
        case .shader(let preset):
            return accentColor(for: preset)

        case .customShader(let path):
            if let cached = colorCache[path] { return cached }
            // Default vibrant cyan for custom MSL/Shadertoy code
            return NSColor(srgbRed: 0.00, green: 0.88, blue: 0.98, alpha: 1.0)

        case .video(let path):
            if let cached = colorCache[path] { return cached }
            let url = URL(fileURLWithPath: path)
            let filename = url.deletingPathExtension().lastPathComponent.lowercased()

            for (key, color) in curatedLibraryColors {
                if filename.contains(key) {
                    colorCache[path] = color
                    return color
                }
            }

            // If not in cache or curated list, trigger background extraction and return default
            Task { @MainActor [weak self] in
                _ = await self?.extractAccentColor(fromVideoAt: url)
            }
            return NSColor(srgbRed: 0.00, green: 0.82, blue: 1.00, alpha: 1.0)

        case .parallax(let path):
            if let cached = colorCache[path] { return cached }
            let url = URL(fileURLWithPath: path)
            if let extracted = extractAccentColor(fromImageAt: url) {
                colorCache[path] = extracted
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

    // MARK: - Video Keyframe Extraction

    public func extractAccentColor(fromVideoAt url: URL) async -> NSColor {
        let path = url.path
        if let cached = colorCache[path] { return cached }

        let filename = url.deletingPathExtension().lastPathComponent.lowercased()
        for (key, color) in curatedLibraryColors {
            if filename.contains(key) {
                colorCache[path] = color
                return color
            }
        }

        // Asynchronously extract keyframe from video at 1.0 second
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 64, height: 64)

        let targetTime = CMTime(seconds: 1.0, preferredTimescale: 600)
        do {
            let cgImage = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
                generator.generateCGImageAsynchronously(for: targetTime) { image, _, error in
                    if let img = image {
                        continuation.resume(returning: img)
                    } else {
                        continuation.resume(throwing: error ?? NSError(domain: "WallpaperColorExtractor", code: -1))
                    }
                }
            }

            let dominant = extractDominantVibrantColor(from: cgImage)
            colorCache[path] = dominant
            return dominant
        } catch {
            // Fallback: Default vibrant oceanic blue
            let fallback = NSColor(srgbRed: 0.0, green: 0.75, blue: 0.95, alpha: 1.0)
            colorCache[path] = fallback
            return fallback
        }
    }

    // MARK: - Still Image Extraction (Photos & Parallax)

    public func extractAccentColor(fromImageAt url: URL) -> NSColor? {
        let path = url.path
        if let cached = colorCache[path] { return cached }

        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }

        let dominant = extractDominantVibrantColor(from: cgImage)
        colorCache[path] = dominant
        return dominant
    }

    // MARK: - Hardware-Accelerated Color Quantization & Saturation Scoring

    public func extractDominantVibrantColor(from image: CGImage) -> NSColor {
        // Downsample to 16x16 thumbnail to sample 256 pixels efficiently
        let sampleWidth = 16
        let sampleHeight = 16
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)

        guard let context = CGContext(
            data: &rawData,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: sampleWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return Self.auroraAccent
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        var bestScore: CGFloat = -1.0
        var bestColor = Self.auroraAccent

        for i in 0..<(sampleWidth * sampleHeight) {
            let offset = i * 4
            let r = CGFloat(rawData[offset]) / 255.0
            let g = CGFloat(rawData[offset + 1]) / 255.0
            let b = CGFloat(rawData[offset + 2]) / 255.0
            let a = CGFloat(rawData[offset + 3]) / 255.0

            guard a > 0.5 else { continue }

            let nsColor = NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
            let h = nsColor.hueComponent
            let s = nsColor.saturationComponent
            let v = nsColor.brightnessComponent

            // Discard pure blacks/shadows (v < 0.18) and blown-out whites (v > 0.92 with low saturation)
            if v < 0.18 || (v > 0.92 && s < 0.15) || s < 0.12 {
                continue
            }

            // Scoring function: High saturation and balanced brightness yields prime wallpaper accents
            let score = s * 1.5 + v * 0.8
            if score > bestScore {
                bestScore = score
                // Boost saturation and brightness slightly to make widget pop
                let boostedS = min(1.0, s * 1.25)
                let boostedV = min(1.0, max(0.65, v * 1.15))
                bestColor = NSColor(calibratedHue: h, saturation: boostedS, brightness: boostedV, alpha: 1.0)
            }
        }

        return bestColor
    }

    // MARK: - Color Harmony Helpers

    /// Computes a harmonious secondary accent (hue rotated ~30 degrees)
    public static func secondaryAccentColor(for color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let newH = (h + 0.08).truncatingRemainder(dividingBy: 1.0)
        return NSColor(calibratedHue: newH, saturation: max(0.5, s), brightness: max(0.6, b), alpha: a)
    }

    /// Computes a complementary accent (hue rotated ~180 degrees)
    public static func complementaryAccentColor(for color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let newH = (h + 0.5).truncatingRemainder(dividingBy: 1.0)
        return NSColor(calibratedHue: newH, saturation: max(0.5, s), brightness: max(0.6, b), alpha: a)
    }
}

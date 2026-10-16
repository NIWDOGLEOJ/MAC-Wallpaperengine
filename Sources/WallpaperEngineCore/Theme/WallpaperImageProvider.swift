//
//  WallpaperImageProvider.swift
//  WallpaperEngineCore
//
//  Feature: Automatic Wallpaper-Aware Dynamic Widget Theming
//  Retrieves readable wallpaper imagery and representative frames across
//  macOS System Settings, looping video engines, procedural Metal shaders, and parallax scenes.
//

import AppKit
import AVFoundation
import CoreGraphics
import Foundation

public protocol WallpaperImageProviderProtocol: Sendable {
    func systemWallpaperURL(for displayID: CGDirectDisplayID) -> URL?
    func extractImage(from url: URL) -> CGImage?
}

public final class WallpaperImageProvider: WallpaperImageProviderProtocol, @unchecked Sendable {

    public static let shared = WallpaperImageProvider()

    public init() {}

    // MARK: - macOS System Desktop Picture Detection

    public func systemWallpaperURL(for displayID: CGDirectDisplayID) -> URL? {
        let matchingScreen = NSScreen.screens.first { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return false
            }
            return screenNumber == displayID
        } ?? NSScreen.main

        guard let screen = matchingScreen else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)
    }

    // MARK: - Still Image Extraction

    public func extractImage(from url: URL) -> CGImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - Video Keyframe Extraction

    public func extractVideoFrame(from url: URL, at time: CMTime) async -> CGImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 64, height: 64)

        return try? await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                if let img = image {
                    continuation.resume(returning: img)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "WallpaperImageProvider", code: -1))
                }
            }
        }
    }

    // MARK: - Procedural Shader Canonical Palettes

    public func proceduralShaderPalette(for preset: ProceduralShaderPreset) -> ExtractedPalette {
        switch preset {
        case .aurora:
            return ExtractedPalette(
                dominant: CodableRGBA(red: 0.18, green: 0.90, blue: 0.62),
                vibrant: CodableRGBA(red: 0.00, green: 0.94, blue: 0.88),
                secondary: CodableRGBA(red: 0.45, green: 0.40, blue: 0.95),
                darkMuted: CodableRGBA(red: 0.06, green: 0.12, blue: 0.14),
                lightMuted: CodableRGBA(red: 0.90, green: 0.98, blue: 0.95),
                averageLuminance: 0.18,
                isPredominantlyDark: true
            )
        case .starfield:
            return ExtractedPalette(
                dominant: CodableRGBA(red: 0.45, green: 0.40, blue: 0.95),
                vibrant: CodableRGBA(red: 0.60, green: 0.50, blue: 1.00),
                secondary: CodableRGBA(red: 0.10, green: 0.85, blue: 1.00),
                darkMuted: CodableRGBA(red: 0.05, green: 0.05, blue: 0.12),
                lightMuted: CodableRGBA(red: 0.92, green: 0.92, blue: 0.98),
                averageLuminance: 0.08,
                isPredominantlyDark: true
            )
        case .gradientFlow:
            return ExtractedPalette(
                dominant: CodableRGBA(red: 1.00, green: 0.35, blue: 0.47),
                vibrant: CodableRGBA(red: 1.00, green: 0.45, blue: 0.60),
                secondary: CodableRGBA(red: 0.95, green: 0.65, blue: 0.20),
                darkMuted: CodableRGBA(red: 0.15, green: 0.06, blue: 0.10),
                lightMuted: CodableRGBA(red: 0.98, green: 0.92, blue: 0.94),
                averageLuminance: 0.26,
                isPredominantlyDark: true
            )
        case .cyberpunkGrid:
            return ExtractedPalette(
                dominant: CodableRGBA(red: 0.00, green: 0.94, blue: 1.00),
                vibrant: CodableRGBA(red: 1.00, green: 0.08, blue: 0.58),
                secondary: CodableRGBA(red: 0.00, green: 0.88, blue: 0.98),
                darkMuted: CodableRGBA(red: 0.05, green: 0.04, blue: 0.12),
                lightMuted: CodableRGBA(red: 0.90, green: 0.98, blue: 1.00),
                averageLuminance: 0.12,
                isPredominantlyDark: true
            )
        case .bokeh:
            return ExtractedPalette(
                dominant: CodableRGBA(red: 1.00, green: 0.67, blue: 0.20),
                vibrant: CodableRGBA(red: 1.00, green: 0.75, blue: 0.30),
                secondary: CodableRGBA(red: 0.95, green: 0.45, blue: 0.15),
                darkMuted: CodableRGBA(red: 0.14, green: 0.09, blue: 0.04),
                lightMuted: CodableRGBA(red: 0.98, green: 0.95, blue: 0.90),
                averageLuminance: 0.32,
                isPredominantlyDark: true
            )
        }
    }
}

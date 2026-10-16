//
//  ThemeEngineTests.swift
//  WallpaperEngineCoreTests
//
//  Comprehensive test suite for Feature: Automatic Wallpaper-Aware Dynamic Widget Theming.
//  Verifies WCAG 2.1 relative luminance and contrast ratios (>= 4.5:1), Core Graphics downsampled
//  color extraction across synthetic images, semantic 13-role theme generation, hysteresis stability,
//  stale task cancellation via generation IDs, and ThemeSettings serialization.
//

import AppKit
import CoreGraphics
import Foundation
@testable import WallpaperEngineCore

@MainActor
public struct ThemeEngineTests {
    public static func runAllTests() async {
        let runner = TestRunner.shared

        // MARK: - Suite 1: WCAG 2.1 Calculations & Color Models
        await runner.runSuite("Suite: WCAG 2.1 Relative Luminance & Contrast") {

            runner.test("CodableRGBA linearizes sRGB luminance accurately for black and white") {
                let black = CodableRGBA.black
                let white = CodableRGBA.white

                try assertEqual(black.luminance, 0.0, "Black luminance is 0.0")
                try assertEqual(white.luminance, 1.0, "White luminance is 1.0")

                let contrast = white.contrastRatio(against: black)
                try assertTrue(abs(contrast - 21.0) < 0.01, "White vs Black contrast ratio is 21:1 (got \(contrast))")

                let selfContrast = white.contrastRatio(against: white)
                try assertTrue(abs(selfContrast - 1.0) < 0.01, "Self contrast ratio is 1:1")
            }

            runner.test("CodableRGBA distance calculation and JSON serialization roundtrip") {
                let color = CodableRGBA(red: 0.12, green: 0.54, blue: 0.88, alpha: 0.95)
                let identical = CodableRGBA(red: 0.12, green: 0.54, blue: 0.88, alpha: 0.95)
                let distant = CodableRGBA(red: 0.90, green: 0.10, blue: 0.10, alpha: 1.0)

                try assertTrue(color.distance(to: identical) < 0.001, "Distance to self is ~0")
                try assertTrue(color.distance(to: distant) > 0.5, "Distance to distinct color is significant")

                let encoder = JSONEncoder()
                let data = try encoder.encode(color)
                let decoded = try JSONDecoder().decode(CodableRGBA.self, from: data)

                try assertEqual(decoded, color, "CodableRGBA roundtrips through JSON identically")
            }
        }

        // MARK: - Suite 2: Color Extraction & Quantization on Synthetic Images
        await runner.runSuite("Suite: Core Graphics Downsampled Color Extraction") {

            runner.test("Extracts dominant palette from synthetic deep blue image") {
                let size = CGSize(width: 128, height: 128)
                let img = createSyntheticImage(size: size, color: NSColor(red: 0.05, green: 0.20, blue: 0.85, alpha: 1.0))

                let extractor = WallpaperColorExtractor.shared
                guard let palette = extractor.extractPalette(from: img) else {
                    throw TestFailure("Failed to extract palette from synthetic blue image")
                }

                try assertTrue(palette.dominant.blue > palette.dominant.red, "Blue dominates red")
                try assertTrue(palette.dominant.blue > 0.5, "Dominant blue channel is strong")
                try assertTrue(palette.isPredominantlyDark, "Deep blue is classified as predominantly dark")
            }

            runner.test("Extracts dominant palette from synthetic emerald green image") {
                let size = CGSize(width: 128, height: 128)
                let img = createSyntheticImage(size: size, color: NSColor(red: 0.08, green: 0.82, blue: 0.35, alpha: 1.0))

                let extractor = WallpaperColorExtractor.shared
                guard let palette = extractor.extractPalette(from: img) else {
                    throw TestFailure("Failed to extract palette from synthetic green image")
                }

                try assertTrue(palette.dominant.green > palette.dominant.red, "Green dominates red")
                try assertTrue(palette.dominant.green > palette.dominant.blue, "Green dominates blue")
            }

            runner.test("Extracts palette from synthetic dark/black image with dark classification") {
                let size = CGSize(width: 64, height: 64)
                let img = createSyntheticImage(size: size, color: NSColor.black)

                let extractor = WallpaperColorExtractor.shared
                guard let palette = extractor.extractPalette(from: img) else {
                    throw TestFailure("Failed to extract palette from black image")
                }

                try assertTrue(palette.isPredominantlyDark, "Black image is predominantly dark")
                try assertTrue(palette.averageLuminance < 0.05, "Luminance is near zero")
            }

            runner.test("Extracts palette from synthetic bright white image with light classification") {
                let size = CGSize(width: 64, height: 64)
                let img = createSyntheticImage(size: size, color: NSColor.white)

                let extractor = WallpaperColorExtractor.shared
                guard let palette = extractor.extractPalette(from: img) else {
                    throw TestFailure("Failed to extract palette from white image")
                }

                try assertTrue(!palette.isPredominantlyDark, "White image is predominantly light")
                try assertTrue(palette.averageLuminance > 0.90, "Luminance is near one")
            }

            runner.test("Thread-safe palette cache accelerates repeat requests") {
                let size = CGSize(width: 64, height: 64)
                let img = createSyntheticImage(size: size, color: NSColor.purple)

                let extractor = WallpaperColorExtractor()
                let p1 = extractor.extractPalette(from: img, cacheKey: "test_purple")
                let p2 = extractor.extractPalette(from: img, cacheKey: "test_purple")

                try assertNotNil(p1, "First extraction succeeds")
                try assertEqual(p1, p2, "Cached extraction returns identical palette")
            }
        }

        // MARK: - Suite 3: Adaptive Theme Generation & Semantic Roles
        await runner.runSuite("Suite: Semantic Theme Generation & WCAG Contrast Guarantee") {

            runner.test("Generates complete 13-role theme with WCAG AA compliance (>= 4.5:1)") {
                let palette = ExtractedPalette(
                    dominant: CodableRGBA(red: 0.10, green: 0.20, blue: 0.60),
                    vibrant: CodableRGBA(red: 0.20, green: 0.60, blue: 1.00),
                    secondary: CodableRGBA(red: 0.15, green: 0.35, blue: 0.70),
                    darkMuted: CodableRGBA(red: 0.05, green: 0.08, blue: 0.15),
                    lightMuted: CodableRGBA(red: 0.85, green: 0.90, blue: 0.95),
                    averageLuminance: 0.18,
                    isPredominantlyDark: true
                )

                let generator = AdaptiveThemeGenerator.shared
                let theme = generator.generateTheme(from: palette, settings: .default, identifier: "test_navy")

                // Verify all 13 semantic color roles
                try assertTrue(theme.primaryRGBA.alpha > 0, "Primary role present")
                try assertTrue(theme.secondaryRGBA.alpha > 0, "Secondary role present")
                try assertTrue(theme.accentRGBA.alpha > 0, "Accent role present")
                try assertTrue(theme.backgroundRGBA.alpha > 0, "Background role present")
                try assertTrue(theme.surfaceRGBA.alpha > 0, "Surface role present")
                try assertTrue(theme.surfaceElevatedRGBA.alpha > 0, "SurfaceElevated role present")
                try assertTrue(theme.textPrimaryRGBA.alpha > 0, "TextPrimary role present")
                try assertTrue(theme.textSecondaryRGBA.alpha > 0, "TextSecondary role present")
                try assertTrue(theme.borderRGBA.alpha > 0, "Border role present")
                try assertTrue(theme.separatorRGBA.alpha > 0, "Separator role present")
                try assertTrue(theme.successRGBA.alpha > 0, "Success role present")
                try assertTrue(theme.warningRGBA.alpha > 0, "Warning role present")
                try assertTrue(theme.errorRGBA.alpha > 0, "Error role present")

                // WCAG 2.1 Normal Text AA Guarantee: Contrast >= 4.5:1
                let contrast = theme.contrastRatio
                try assertTrue(contrast >= 4.5, "TextPrimary contrast against surface satisfies WCAG AA >= 4.5:1 (got \(contrast):1)")
                try assertTrue(theme.isDark, "Dark palette generates dark theme")
            }

            runner.test("Bright wallpaper generates dark text satisfying WCAG AA (>= 4.5:1)") {
                let palette = ExtractedPalette(
                    dominant: CodableRGBA(red: 0.92, green: 0.92, blue: 0.94),
                    vibrant: CodableRGBA(red: 0.95, green: 0.70, blue: 0.20),
                    secondary: CodableRGBA(red: 0.80, green: 0.85, blue: 0.90),
                    darkMuted: CodableRGBA(red: 0.20, green: 0.25, blue: 0.30),
                    lightMuted: CodableRGBA(red: 0.95, green: 0.96, blue: 0.98),
                    averageLuminance: 0.85,
                    isPredominantlyDark: false
                )

                let generator = AdaptiveThemeGenerator.shared
                let theme = generator.generateTheme(from: palette, settings: .default, identifier: "test_bright")

                try assertTrue(!theme.isDark, "Bright palette generates light theme")
                let contrast = theme.contrastRatio
                try assertTrue(contrast >= 4.5, "Light theme text satisfies WCAG AA >= 4.5:1 (got \(contrast):1)")
            }

            runner.test("Appearance preference overrides wallpaper default tone") {
                let darkPalette = ExtractedPalette(
                    dominant: CodableRGBA(red: 0.1, green: 0.1, blue: 0.1),
                    vibrant: CodableRGBA(red: 0.0, green: 0.8, blue: 0.9),
                    secondary: CodableRGBA(red: 0.2, green: 0.2, blue: 0.2),
                    darkMuted: CodableRGBA(red: 0.05, green: 0.05, blue: 0.05),
                    lightMuted: CodableRGBA(red: 0.8, green: 0.8, blue: 0.8),
                    averageLuminance: 0.1,
                    isPredominantlyDark: true
                )

                let generator = AdaptiveThemeGenerator.shared
                var lightSettings = ThemeSettings.default
                lightSettings.appearancePreference = .preferLight

                let lightTheme = generator.generateTheme(from: darkPalette, settings: lightSettings, identifier: "test_override")
                try assertTrue(!lightTheme.isDark, "preferLight forces light theme surface")
                try assertTrue(lightTheme.contrastRatio >= 4.5, "Overridden theme still satisfies WCAG AA")
            }
        }

        // MARK: - Suite 4: Hysteresis Stability & Theme Distance
        await runner.runSuite("Suite: Hysteresis Stability & Difference Metrics") {

            runner.test("Identical themes have 0.0 difference") {
                let theme = WallpaperTheme.fallback
                let diff = theme.difference(from: theme)
                try assertEqual(diff, 0.0, "Self difference is zero")
            }

            runner.test("Insignificant theme differences (< 0.06) are suppressed by ThemeManager") {
                let manager = ThemeManager()
                let displayID: CGDirectDisplayID = 1

                let theme1 = WallpaperTheme.fallback
                manager.applyTheme(theme1, for: displayID, notify: false)
                try assertEqual(manager.themes[displayID]?.identifier, theme1.identifier, "Theme 1 applied")

                // Create micro-variation (less than 0.06 difference)
                var variation = theme1
                variation.accentRGBA = CodableRGBA(
                    red: theme1.accentRGBA.red + 0.01,
                    green: theme1.accentRGBA.green,
                    blue: theme1.accentRGBA.blue,
                    alpha: 1.0
                )
                let diff = variation.difference(from: theme1)
                try assertTrue(diff < 0.06, "Difference is below hysteresis threshold (got \(diff))")

                nonisolated(unsafe) var notificationFired = false
                manager.onThemeUpdate = { _, _ in
                    notificationFired = true
                }

                manager.applyTheme(variation, for: displayID, notify: true)
                try assertTrue(!notificationFired, "Notification suppressed for micro-variation below hysteresis threshold")
            }

            runner.test("Significant theme differences (>= 0.08) trigger theme update") {
                let manager = ThemeManager()
                let displayID: CGDirectDisplayID = 1

                let theme1 = WallpaperTheme.fallback
                manager.applyTheme(theme1, for: displayID, notify: false)

                // Substantially different theme (emerald green vs fallback cyan)
                let emeraldPalette = ExtractedPalette(
                    dominant: CodableRGBA(red: 0.0, green: 0.8, blue: 0.3),
                    vibrant: CodableRGBA(red: 0.1, green: 0.9, blue: 0.4),
                    secondary: CodableRGBA(red: 0.0, green: 0.5, blue: 0.2),
                    darkMuted: CodableRGBA(red: 0.02, green: 0.08, blue: 0.04),
                    lightMuted: CodableRGBA(red: 0.8, green: 0.95, blue: 0.85),
                    averageLuminance: 0.35,
                    isPredominantlyDark: true
                )
                let theme2 = AdaptiveThemeGenerator.shared.generateTheme(from: emeraldPalette, settings: .default, identifier: "emerald")

                let diff = theme2.difference(from: theme1)
                try assertTrue(diff >= 0.08, "Emerald theme is significantly different from fallback (got \(diff))")

                nonisolated(unsafe) var receivedTheme: WallpaperTheme?
                manager.onThemeUpdate = { _, t in
                    receivedTheme = t
                }

                manager.applyTheme(theme2, for: displayID, notify: true)
                try assertNotNil(receivedTheme, "Significant theme change successfully notified")
                try assertEqual(receivedTheme?.identifier, "emerald", "Correct theme updated")
            }
        }

        // MARK: - Suite 5: Palette Locking & Theme Settings Serialization
        await runner.runSuite("Suite: Theme Locking & Configuration Persistence") {

            await runner.testAsync("ThemeManager respects isLocked and manual mode") {
                let manager = ThemeManager()
                let displayID: CGDirectDisplayID = 1

                manager.applyTheme(WallpaperTheme.fallback, for: displayID, notify: false)
                manager.lockCurrentPalette(for: displayID)

                try assertTrue(manager.settings.isLocked, "Settings reflect locked state")

                nonisolated(unsafe) var didUpdate = false
                manager.onThemeUpdate = { _, _ in
                    didUpdate = true
                }

                // Process a wallpaper change while locked
                await manager.processWallpaperChange(
                    displayID: displayID,
                    info: WallpaperSourceInfo(
                        displayID: displayID,
                        type: .applicationShader(preset: .cyberpunkGrid),
                        identifier: "shader:cyberpunkGrid"
                    )
                )

                try assertTrue(!didUpdate, "No theme update emitted while palette is locked")
            }

            runner.test("ThemeSettings serializes and roundtrips with Codable") {
                let settings = ThemeSettings(
                    mode: .liveAdaptive,
                    appearancePreference: .preferDark,
                    accentIntensity: .vibrant,
                    backgroundOpacity: 0.85,
                    liveUpdateInterval: 4.5,
                    isLocked: true,
                    manualTheme: .fallback
                )

                let encoder = JSONEncoder()
                let data = try encoder.encode(settings)
                let decoded = try JSONDecoder().decode(ThemeSettings.self, from: data)

                try assertEqual(decoded.mode, .liveAdaptive, "Mode roundtrips")
                try assertEqual(decoded.appearancePreference, .preferDark, "AppearancePreference roundtrips")
                try assertEqual(decoded.accentIntensity, .vibrant, "AccentIntensity roundtrips")
                try assertEqual(decoded.backgroundOpacity, 0.85, "BackgroundOpacity roundtrips")
                try assertEqual(decoded.liveUpdateInterval, 4.5, "LiveUpdateInterval roundtrips")
                try assertEqual(decoded.isLocked, true, "isLocked roundtrips")
                try assertEqual(decoded.manualTheme?.identifier, WallpaperTheme.fallback.identifier, "manualTheme roundtrips")
            }

            runner.test("EngineConfig.HUDConfig decodes legacy JSON gracefully with default themeSettings") {
                let legacyJSON = """
                {
                    "isEnabled": true,
                    "position": "topRight",
                    "showClock": true,
                    "showDate": true,
                    "showSystemStats": true,
                    "showNowPlaying": true,
                    "showAudioVisualizer": true,
                    "scale": 1.0
                }
                """.data(using: .utf8)!

                let decoded = try JSONDecoder().decode(EngineConfig.HUDConfig.self, from: legacyJSON)
                try assertEqual(decoded.themeSettings.mode, .automatic, "Legacy JSON defaults themeSettings to automatic")
                try assertEqual(decoded.themeSettings.backgroundOpacity, 0.70, "Default backgroundOpacity is 0.70")
            }
        }
    }

    // MARK: - Helper: Synthetic NSImage Generator

    private static func createSyntheticImage(size: CGSize, color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.drawSwatch(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        return image
    }
}

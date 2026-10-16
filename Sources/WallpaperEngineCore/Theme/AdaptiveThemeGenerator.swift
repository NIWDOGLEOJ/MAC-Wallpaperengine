//
//  AdaptiveThemeGenerator.swift
//  WallpaperEngineCore
//
//  Feature: Automatic Wallpaper-Aware Dynamic Widget Theming
//  Transforms raw extracted palettes into WCAG 2.1 contrast-compliant
//  semantic themes with intelligent dark/light surface calculation.
//

import AppKit
import Foundation

public protocol AdaptiveThemeGeneratorProtocol: Sendable {
    func generateTheme(from palette: ExtractedPalette, settings: ThemeSettings, identifier: String) -> WallpaperTheme
}

public final class AdaptiveThemeGenerator: AdaptiveThemeGeneratorProtocol, @unchecked Sendable {

    public static let shared = AdaptiveThemeGenerator()

    public init() {}

    public func generateTheme(
        from palette: ExtractedPalette,
        settings: ThemeSettings = .default,
        identifier: String = "automatic"
    ) -> WallpaperTheme {
        // 1. Determine Dark vs Light Appearance
        let isDark: Bool
        switch settings.appearancePreference {
        case .preferDark:
            isDark = true
        case .preferLight:
            isDark = false
        case .automatic:
            isDark = palette.isPredominantlyDark
        }

        // 2. Adjust Accents according to Intensity Preference
        let satMult = settings.accentIntensity.saturationMultiplier
        let adjustedPrimary = adjustSaturation(palette.vibrant, multiplier: satMult)
        let adjustedSecondary = adjustSaturation(palette.secondary, multiplier: satMult)
        let adjustedAccent = adjustSaturation(palette.dominant, multiplier: satMult * 1.1)

        // 3. Generate Structural Surfaces
        let bgOpacity = settings.backgroundOpacity
        let backgroundRGBA: CodableRGBA
        let surfaceRGBA: CodableRGBA
        let surfaceElevatedRGBA: CodableRGBA

        if isDark {
            // Dark glassmorphic background & surfaces
            let r = max(0.04, min(0.14, palette.darkMuted.red * 0.8))
            let g = max(0.05, min(0.15, palette.darkMuted.green * 0.8))
            let b = max(0.07, min(0.18, palette.darkMuted.blue * 0.8))

            backgroundRGBA = CodableRGBA(red: r, green: g, blue: b, alpha: bgOpacity)
            surfaceRGBA = CodableRGBA(red: r + 0.05, green: g + 0.05, blue: b + 0.06, alpha: min(1.0, bgOpacity * 0.75))
            surfaceElevatedRGBA = CodableRGBA(red: r + 0.09, green: g + 0.09, blue: b + 0.11, alpha: min(1.0, bgOpacity * 0.88))
        } else {
            // Light glassmorphic background & surfaces
            let r = min(0.98, max(0.90, palette.lightMuted.red))
            let g = min(0.98, max(0.90, palette.lightMuted.green))
            let b = min(0.99, max(0.92, palette.lightMuted.blue))

            backgroundRGBA = CodableRGBA(red: r, green: g, blue: b, alpha: bgOpacity)
            surfaceRGBA = CodableRGBA(red: r - 0.04, green: g - 0.04, blue: b - 0.03, alpha: min(1.0, bgOpacity * 0.85))
            surfaceElevatedRGBA = CodableRGBA(red: r - 0.08, green: g - 0.08, blue: b - 0.06, alpha: min(1.0, bgOpacity * 0.92))
        }

        // 4. Calculate WCAG 2.1 Contrast-Compliant Typography
        var textPrimary: CodableRGBA
        var textSecondary: CodableRGBA

        if isDark {
            textPrimary = CodableRGBA(red: 0.98, green: 0.98, blue: 1.00, alpha: 1.0)
            textSecondary = CodableRGBA(red: 0.72, green: 0.76, blue: 0.84, alpha: 0.90)
        } else {
            textPrimary = CodableRGBA(red: 0.08, green: 0.09, blue: 0.12, alpha: 1.0)
            textSecondary = CodableRGBA(red: 0.36, green: 0.38, blue: 0.44, alpha: 0.90)
        }

        // Guarantee WCAG AA minimum contrast ratio (4.5:1)
        var currentContrast = textPrimary.contrastRatio(against: surfaceRGBA)
        if currentContrast < 4.5 {
            // Fall back to pure high-contrast black/white
            textPrimary = isDark ? CodableRGBA(red: 1.0, green: 1.0, blue: 1.0) : CodableRGBA(red: 0.0, green: 0.0, blue: 0.0)
            currentContrast = textPrimary.contrastRatio(against: surfaceRGBA)
        }

        // 5. Borders & Separators
        let borderRGBA: CodableRGBA
        let separatorRGBA: CodableRGBA
        if isDark {
            borderRGBA = adjustedPrimary.withAlpha(0.28)
            separatorRGBA = CodableRGBA(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.12)
        } else {
            borderRGBA = adjustedPrimary.withAlpha(0.22)
            separatorRGBA = CodableRGBA(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.10)
        }

        // 6. Harmonized Semantic Feedback Roles
        let successRGBA = CodableRGBA(red: 0.20, green: 0.84, blue: 0.48)
        let warningRGBA = CodableRGBA(red: 1.00, green: 0.68, blue: 0.18)
        let errorRGBA = CodableRGBA(red: 1.00, green: 0.32, blue: 0.36)

        return WallpaperTheme(
            primary: adjustedPrimary,
            secondary: adjustedSecondary,
            accent: adjustedAccent,
            background: backgroundRGBA,
            surface: surfaceRGBA,
            surfaceElevated: surfaceElevatedRGBA,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            border: borderRGBA,
            separator: separatorRGBA,
            success: successRGBA,
            warning: warningRGBA,
            error: errorRGBA,
            isDark: isDark,
            wallpaperLuminance: palette.averageLuminance,
            textContrastRatio: currentContrast,
            sourceIdentifier: identifier
        )
    }

    private func adjustSaturation(_ rgba: CodableRGBA, multiplier: Double) -> CodableRGBA {
        let ns = rgba.nsColor
        let h = ns.hueComponent
        let s = max(0.0, min(1.0, ns.saturationComponent * CGFloat(multiplier)))
        let b = ns.brightnessComponent
        let adjusted = NSColor(calibratedHue: h, saturation: s, brightness: b, alpha: CGFloat(rgba.alpha))
        return CodableRGBA(nsColor: adjusted)
    }
}

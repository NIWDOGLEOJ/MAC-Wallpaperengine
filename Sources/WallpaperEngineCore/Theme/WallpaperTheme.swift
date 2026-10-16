//
//  WallpaperTheme.swift
//  WallpaperEngineCore
//
//  Feature: Automatic Wallpaper-Aware Dynamic Widget Theming
//  Complete semantic color palette model supporting serialization,
//  WCAG 2.1 relative luminance and contrast metrics, and dual AppKit/SwiftUI accessors.
//

import AppKit
import Foundation
import SwiftUI

// MARK: - Codable Color Representation

public struct CodableRGBA: Codable, Sendable, Equatable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = max(0.0, min(1.0, red))
        self.green = max(0.0, min(1.0, green))
        self.blue = max(0.0, min(1.0, blue))
        self.alpha = max(0.0, min(1.0, alpha))
    }

    public static let black = CodableRGBA(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    public static let white = CodableRGBA(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    public static let clear = CodableRGBA(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)

    public init(nsColor: NSColor) {
        let rgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.red = Double(rgb.redComponent)
        self.green = Double(rgb.greenComponent)
        self.blue = Double(rgb.blueComponent)
        self.alpha = Double(rgb.alphaComponent)
    }

    public var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    public func withAlpha(_ newAlpha: Double) -> CodableRGBA {
        CodableRGBA(red: red, green: green, blue: blue, alpha: newAlpha)
    }

    /// Linearized relative luminance per WCAG 2.1 specifications
    public var relativeLuminance: Double {
        func linearize(_ component: Double) -> Double {
            if component <= 0.04045 {
                return component / 12.92
            } else {
                return pow((component + 0.055) / 1.055, 2.4)
            }
        }
        let rLin = linearize(red)
        let gLin = linearize(green)
        let bLin = linearize(blue)
        return 0.2126 * rLin + 0.7152 * gLin + 0.0722 * bLin
    }

    public var luminance: Double { relativeLuminance }

    /// Calculates WCAG 2.1 contrast ratio against another color (range 1.0 to 21.0)
    public func contrastRatio(against other: CodableRGBA) -> Double {
        let l1 = self.relativeLuminance
        let l2 = other.relativeLuminance
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Euclidean distance in sRGB color space (range 0.0 to ~1.73)
    public func distance(to other: CodableRGBA) -> Double {
        let dr = red - other.red
        let dg = green - other.green
        let db = blue - other.blue
        return sqrt(dr * dr + dg * dg + db * db)
    }
}

// MARK: - Semantic Wallpaper Theme Model

public struct WallpaperTheme: Codable, Sendable, Equatable {
    // 1. Primary & Tonal Accents
    public var primaryRGBA: CodableRGBA
    public var secondaryRGBA: CodableRGBA
    public var accentRGBA: CodableRGBA

    // 2. Structural Surfaces & Backgrounds
    public var backgroundRGBA: CodableRGBA
    public var surfaceRGBA: CodableRGBA
    public var surfaceElevatedRGBA: CodableRGBA

    // 3. Typography & Foregrounds
    public var textPrimaryRGBA: CodableRGBA
    public var textSecondaryRGBA: CodableRGBA

    // 4. Borders & Separators
    public var borderRGBA: CodableRGBA
    public var separatorRGBA: CodableRGBA

    // 5. Semantic Feedback Tones
    public var successRGBA: CodableRGBA
    public var warningRGBA: CodableRGBA
    public var errorRGBA: CodableRGBA

    // 6. Metadata & Contrast Intelligence
    public var isDark: Bool
    public var wallpaperLuminance: Double
    public var textContrastRatio: Double
    public var sourceIdentifier: String

    public init(
        primary: CodableRGBA,
        secondary: CodableRGBA,
        accent: CodableRGBA,
        background: CodableRGBA,
        surface: CodableRGBA,
        surfaceElevated: CodableRGBA,
        textPrimary: CodableRGBA,
        textSecondary: CodableRGBA,
        border: CodableRGBA,
        separator: CodableRGBA,
        success: CodableRGBA,
        warning: CodableRGBA,
        error: CodableRGBA,
        isDark: Bool,
        wallpaperLuminance: Double,
        textContrastRatio: Double,
        sourceIdentifier: String = "automatic"
    ) {
        self.primaryRGBA = primary
        self.secondaryRGBA = secondary
        self.accentRGBA = accent
        self.backgroundRGBA = background
        self.surfaceRGBA = surface
        self.surfaceElevatedRGBA = surfaceElevated
        self.textPrimaryRGBA = textPrimary
        self.textSecondaryRGBA = textSecondary
        self.borderRGBA = border
        self.separatorRGBA = separator
        self.successRGBA = success
        self.warningRGBA = warning
        self.errorRGBA = error
        self.isDark = isDark
        self.wallpaperLuminance = wallpaperLuminance
        self.textContrastRatio = textContrastRatio
        self.sourceIdentifier = sourceIdentifier
    }

    // MARK: - AppKit NSColor Accessors

    public var primary: NSColor { primaryRGBA.nsColor }
    public var secondary: NSColor { secondaryRGBA.nsColor }
    public var accent: NSColor { accentRGBA.nsColor }
    public var background: NSColor { backgroundRGBA.nsColor }
    public var surface: NSColor { surfaceRGBA.nsColor }
    public var surfaceElevated: NSColor { surfaceElevatedRGBA.nsColor }
    public var textPrimary: NSColor { textPrimaryRGBA.nsColor }
    public var textSecondary: NSColor { textSecondaryRGBA.nsColor }
    public var border: NSColor { borderRGBA.nsColor }
    public var separator: NSColor { separatorRGBA.nsColor }
    public var success: NSColor { successRGBA.nsColor }
    public var warning: NSColor { warningRGBA.nsColor }
    public var error: NSColor { errorRGBA.nsColor }

    // MARK: - SwiftUI Color Accessors

    public var primaryColor: Color { primaryRGBA.color }
    public var secondaryColor: Color { secondaryRGBA.color }
    public var accentColor: Color { accentRGBA.color }
    public var backgroundColor: Color { backgroundRGBA.color }
    public var surfaceColor: Color { surfaceRGBA.color }
    public var surfaceElevatedColor: Color { surfaceElevatedRGBA.color }
    public var textPrimaryColor: Color { textPrimaryRGBA.color }
    public var textSecondaryColor: Color { textSecondaryRGBA.color }
    public var borderColor: Color { borderRGBA.color }
    public var separatorColor: Color { separatorRGBA.color }
    public var successColor: Color { successRGBA.color }
    public var warningColor: Color { warningRGBA.color }
    public var errorColor: Color { errorRGBA.color }

    public var primarySwiftUIColor: Color { primaryRGBA.color }
    public var secondarySwiftUIColor: Color { secondaryRGBA.color }
    public var accentSwiftUIColor: Color { accentRGBA.color }
    public var backgroundSwiftUIColor: Color { backgroundRGBA.color }
    public var surfaceSwiftUIColor: Color { surfaceRGBA.color }
    public var surfaceElevatedSwiftUIColor: Color { surfaceElevatedRGBA.color }
    public var textPrimarySwiftUIColor: Color { textPrimaryRGBA.color }
    public var textSecondarySwiftUIColor: Color { textSecondaryRGBA.color }
    public var borderSwiftUIColor: Color { borderRGBA.color }
    public var separatorSwiftUIColor: Color { separatorRGBA.color }
    public var successSwiftUIColor: Color { successRGBA.color }
    public var warningSwiftUIColor: Color { warningRGBA.color }
    public var errorSwiftUIColor: Color { errorRGBA.color }

    public var contrastRatio: Double { textContrastRatio }
    public var identifier: String { sourceIdentifier }

    // MARK: - Palette Similarity Evaluation (Hysteresis)

    /// Calculates composite visual difference metric between two themes (0.0 ... 1.0)
    public func difference(from other: WallpaperTheme) -> Double {
        let dPrimary = primaryRGBA.distance(to: other.primaryRGBA)
        let dAccent = accentRGBA.distance(to: other.accentRGBA)
        let dSurface = surfaceRGBA.distance(to: other.surfaceRGBA)
        let dText = textPrimaryRGBA.distance(to: other.textPrimaryRGBA)
        return (dPrimary * 0.35 + dAccent * 0.35 + dSurface * 0.20 + dText * 0.10) / sqrt(3.0)
    }

    // MARK: - Canonical Default Theme (Aurora Emerald Glass)

    public static let fallback = WallpaperTheme(
        primary: CodableRGBA(red: 0.18, green: 0.90, blue: 0.62), // Emerald Teal
        secondary: CodableRGBA(red: 0.45, green: 0.40, blue: 0.95), // Cosmic Indigo
        accent: CodableRGBA(red: 0.00, green: 0.94, blue: 1.00), // Electric Cyan
        background: CodableRGBA(red: 0.08, green: 0.09, blue: 0.12, alpha: 0.70),
        surface: CodableRGBA(red: 0.14, green: 0.16, blue: 0.22, alpha: 0.55),
        surfaceElevated: CodableRGBA(red: 0.18, green: 0.20, blue: 0.28, alpha: 0.65),
        textPrimary: CodableRGBA(red: 0.98, green: 0.98, blue: 1.00),
        textSecondary: CodableRGBA(red: 0.75, green: 0.78, blue: 0.86),
        border: CodableRGBA(red: 0.18, green: 0.90, blue: 0.62, alpha: 0.25),
        separator: CodableRGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.12),
        success: CodableRGBA(red: 0.20, green: 0.85, blue: 0.50),
        warning: CodableRGBA(red: 1.00, green: 0.70, blue: 0.20),
        error: CodableRGBA(red: 1.00, green: 0.32, blue: 0.36),
        isDark: true,
        wallpaperLuminance: 0.15,
        textContrastRatio: 11.2,
        sourceIdentifier: "fallback-aurora"
    )
}

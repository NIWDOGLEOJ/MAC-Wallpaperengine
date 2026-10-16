//
//  ThemeSettings.swift
//  WallpaperEngineCore
//
//  Feature: Automatic Wallpaper-Aware Dynamic Widget Theming
//  User-configurable preferences for theme modes, contrast, accent vibrancy,
//  glass opacity, live update cadence, and palette locking.
//

import Foundation

public enum ThemeMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case automatic = "Automatic"
    case staticAdaptive = "Static Adaptive"
    case liveAdaptive = "Live Adaptive"
    case manual = "Manual"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .automatic:
            return "Automatically selects static or live sampling depending on wallpaper type."
        case .staticAdaptive:
            return "Analyzes wallpaper once upon change; zero ongoing background sampling."
        case .liveAdaptive:
            return "Periodically samples video frames for gradual dynamic color changes."
        case .manual:
            return "Theme is locked and will not automatically adapt to wallpapers."
        }
    }
}

public enum AppearancePreference: String, Codable, CaseIterable, Sendable, Identifiable {
    case automatic = "Auto (Wallpaper-Driven)"
    case preferLight = "Prefer Light Surfaces"
    case preferDark = "Prefer Dark Surfaces"

    public var id: String { rawValue }
}

public enum AccentIntensity: String, Codable, CaseIterable, Sendable, Identifiable {
    case subtle = "Subtle"
    case balanced = "Balanced"
    case vibrant = "Vibrant"

    public var id: String { rawValue }

    public var saturationMultiplier: Double {
        switch self {
        case .subtle: return 0.75
        case .balanced: return 1.0
        case .vibrant: return 1.35
        }
    }
}

public struct ThemeSettings: Codable, Sendable, Equatable {
    public var mode: ThemeMode
    public var appearancePreference: AppearancePreference
    public var accentIntensity: AccentIntensity
    public var backgroundOpacity: Double
    public var liveUpdateInterval: Double
    public var isLocked: Bool
    public var manualTheme: WallpaperTheme?

    public static let `default` = ThemeSettings(
        mode: .automatic,
        appearancePreference: .automatic,
        accentIntensity: .balanced,
        backgroundOpacity: 0.70,
        liveUpdateInterval: 3.0,
        isLocked: false,
        manualTheme: nil
    )

    public init(
        mode: ThemeMode = .automatic,
        appearancePreference: AppearancePreference = .automatic,
        accentIntensity: AccentIntensity = .balanced,
        backgroundOpacity: Double = 0.70,
        liveUpdateInterval: Double = 3.0,
        isLocked: Bool = false,
        manualTheme: WallpaperTheme? = nil
    ) {
        self.mode = mode
        self.appearancePreference = appearancePreference
        self.accentIntensity = accentIntensity
        self.backgroundOpacity = max(0.2, min(1.0, backgroundOpacity))
        self.liveUpdateInterval = max(1.0, min(10.0, liveUpdateInterval))
        self.isLocked = isLocked
        self.manualTheme = manualTheme
    }
}

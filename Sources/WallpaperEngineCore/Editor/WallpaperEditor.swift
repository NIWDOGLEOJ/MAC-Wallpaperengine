//
//  WallpaperEditor.swift
//  WallpaperEngineCore
//
//  Feature 13: Modular editor for creating and customizing multi-layer wallpapers.
//  Maintains strict isolation between heavy editing preview and lightweight runtime.
//

import AppKit
import CoreGraphics
import Foundation
import OSLog

public struct WallpaperLayerConfig: Codable, Equatable, Sendable {
    public var baseAssetPath: String?
    public var baseType: LibraryWallpaperType
    public var particleEffect: ParticleSceneType?
    public var particleDensity: Int
    public var particleSpeed: Float
    public var brightness: Float
    public var contrast: Float
    public var saturation: Float
    public var vignetteIntensity: Float
    public var audioSensitivity: Float

    public init(
        baseAssetPath: String? = nil,
        baseType: LibraryWallpaperType = .shader,
        particleEffect: ParticleSceneType? = nil,
        particleDensity: Int = 100,
        particleSpeed: Float = 1.0,
        brightness: Float = 0.0,
        contrast: Float = 1.0,
        saturation: Float = 1.0,
        vignetteIntensity: Float = 0.0,
        audioSensitivity: Float = 1.0
    ) {
        self.baseAssetPath = baseAssetPath
        self.baseType = baseType
        self.particleEffect = particleEffect
        self.particleDensity = particleDensity
        self.particleSpeed = particleSpeed
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.vignetteIntensity = vignetteIntensity
        self.audioSensitivity = audioSensitivity
    }
}

@MainActor
public final class WallpaperEditor: ObservableObject {
    @Published public var config: WallpaperLayerConfig = .init()
    @Published public private(set) var isPreviewActive: Bool = false

    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "WallpaperEditor")

    public init() {}

    public func startPreview() {
        isPreviewActive = true
        logger.info("Editor preview started.")
    }

    public func stopPreview() {
        isPreviewActive = false
        logger.info("Editor preview stopped and preview resources released.")
    }

    public func resetToDefaults() {
        config = WallpaperLayerConfig()
    }

    public func exportConfiguration() -> Data? {
        try? JSONEncoder().encode(config)
    }

    public func importConfiguration(from data: Data) -> Bool {
        guard let decoded = try? JSONDecoder().decode(WallpaperLayerConfig.self, from: data) else {
            return false
        }
        self.config = decoded
        return true
    }
}

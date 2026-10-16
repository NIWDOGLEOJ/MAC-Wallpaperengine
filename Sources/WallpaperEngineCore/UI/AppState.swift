//
//  AppState.swift
//  WallpaperEngineCore
//
//  Central observable application state driving the SwiftUI interface
//  and bridging commands to the AppCoordinator engine.
//

import AppKit
import Combine
import Foundation
import SwiftUI

public enum GalleryCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case shaders = "Metal Shaders"
    case parallax = "AI 3D Parallax"
    case videos = "Looping Videos"
    case custom = "Custom Code"

    public var id: String { rawValue }
}

public struct WallpaperVideoItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let url: URL
    public let filename: String
    public let resolution: String
    public let fileSizeFormatted: String

    public init(url: URL) {
        self.id = url.path
        self.url = url
        self.filename = url.lastPathComponent

        var name = url.deletingPathExtension().lastPathComponent
        var res = "HD Video"
        if name.contains("3840x2160") || name.contains("4k") || name.contains("4K") {
            res = "4K UHD 2160p"
            name = name.replacingOccurrences(of: ".3840x2160", with: "")
                       .replacingOccurrences(of: "_3840x2160", with: "")
        } else if name.contains("1920x1080") || name.contains("1080p") {
            res = "Full HD 1080p"
            name = name.replacingOccurrences(of: ".1920x1080", with: "")
                       .replacingOccurrences(of: "_1920x1080", with: "")
        }
        self.resolution = res

        let words = name.replacingOccurrences(of: "-", with: " ")
                        .replacingOccurrences(of: "_", with: " ")
                        .split(separator: " ")
        self.title = words.map { $0.capitalized }.joined(separator: " ")

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            let mb = Double(size) / (1024 * 1024)
            self.fileSizeFormatted = String(format: "%.1f MB", mb)
        } else {
            self.fileSizeFormatted = "Video"
        }
    }
}

public enum ActiveWallpaperType: Equatable, Sendable {
    case shader(ProceduralShaderPreset)
    case customShader(path: String)
    case parallax(path: String)
    case video(path: String)
    case none
}

@MainActor
public final class AppState: ObservableObject {
    // MARK: - Navigation
    @Published public var selectedTab: NavigationTab = .gallery

    // MARK: - Core Engine State
    @Published public var config: EngineConfig
    @Published public var telemetry: SystemTelemetry = SystemTelemetry()
    @Published public var audioSpectrum: AudioSpectrumData = AudioSpectrumData()
    @Published public var nowPlaying: NowPlayingInfo = NowPlayingInfo()
    @Published public var displays: [DisplayInfo] = []
    @Published public var selectedDisplayID: CGDirectDisplayID? = nil

    // MARK: - Active Wallpaper Selection
    @Published public var activeShaderPreset: ProceduralShaderPreset = .aurora
    @Published public var shaderSpeed: Float = 1.0
    @Published public var isPlaybackPaused: Bool = false
    @Published public var isAudioReactive: Bool = true
    @Published public var discoveredVideos: [WallpaperVideoItem] = []
    @Published public var activeWallpaperAccentColor: NSColor = WallpaperColorExtractor.auroraAccent
    @Published public var activeWallpaperTheme: WallpaperTheme = .fallback

    // MARK: - Interactive UI View State (Stored in AppState to avoid Command Line Tools SwiftUI macro missing symbols)
    @Published public var galleryCategory: GalleryCategory = .all
    @Published public var showingCustomShaderSheet: Bool = false
    @Published public var customShaderDraft: String = """
    // Custom Shadertoy or Metal Shading Language
    void mainImage(out vec4 fragColor, in vec2 fragCoord) {
        vec2 uv = fragCoord / iResolution.xy;
        float wave = sin(uv.x * 10.0 + iTime * 2.0) * 0.5 + 0.5;
        fragColor = vec4(uv.x * iBass, wave * iMid, uv.y * iTreble, 1.0);
    }
    """
    @Published public var compileErrorMessage: String? = nil
    @Published public var previewSpeed: Float = 1.0
    @Published public var isAudioPreviewActive: Bool = true
    @Published public var isPausedLocally: Bool = false

    // MARK: - User Feedback / Toast
    @Published public var toastMessage: String? = nil
    private var toastTask: Task<Void, Never>?

    // MARK: - Coordinator Reference
    public weak var coordinator: AppCoordinatorProtocol?

    // MARK: - Initialization
    public init(config: EngineConfig, coordinator: AppCoordinatorProtocol? = nil) {
        self.config = config
        self.coordinator = coordinator
        self.shaderSpeed = config.shaderSpeed
        self.isAudioReactive = config.isAudioReactive
        if let preset = config.shaderPreset {
            self.activeShaderPreset = preset
        }
        refreshDiscoveredVideos()
        updateActiveWallpaperAccentColor()
    }

    // MARK: - Wallpaper Discovery & Active Detection

    public func refreshDiscoveredVideos() {
        var foundURLs: Set<URL> = []
        let fm = FileManager.default

        // 1. Scan ~/Library/Application Support/WallpaperEngineCore/Wallpapers
        let appSupport = ConfigPersistenceManager.defaultConfigDirectoryURL
        let wallpapersDir = appSupport.appendingPathComponent("Wallpapers", isDirectory: true)
        if let items = try? fm.contentsOfDirectory(at: wallpapersDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for item in items {
                let ext = item.pathExtension.lowercased()
                if ext == "mp4" || ext == "mov" || ext == "m4v" {
                    foundURLs.insert(item)
                }
            }
        }

        // 2. Add current configured video paths
        if let defaultPath = config.defaultAssetPath, fm.fileExists(atPath: defaultPath) {
            foundURLs.insert(URL(fileURLWithPath: defaultPath))
        }
        for dispCfg in config.displayConfigurations.values {
            if let path = dispCfg.assetPath, fm.fileExists(atPath: path) {
                foundURLs.insert(URL(fileURLWithPath: path))
            }
        }

        self.discoveredVideos = foundURLs.map { WallpaperVideoItem(url: $0) }.sorted(by: { $0.title < $1.title })
    }

    public func activeWallpaper(for displayID: CGDirectDisplayID? = nil) -> ActiveWallpaperType {
        let targetID = displayID ?? selectedDisplayID
        if let id = targetID {
            let key = String(id)
            if let disp = config.displayConfigurations[key] {
                if let sName = disp.shaderName, let preset = ProceduralShaderPreset(rawValue: sName) {
                    return .shader(preset)
                }
                if let sPath = disp.shaderPath {
                    return .customShader(path: sPath)
                }
                if let pPath = disp.photoPath {
                    return .parallax(path: pPath)
                }
                if let vPath = disp.assetPath {
                    return .video(path: vPath)
                }
            }
        }

        // Global fallback
        if let sName = config.shaderName, let preset = ProceduralShaderPreset(rawValue: sName) {
            return .shader(preset)
        }
        if let sPath = config.shaderPath {
            return .customShader(path: sPath)
        }
        if let pPath = config.photoPath {
            return .parallax(path: pPath)
        }
        if let vPath = config.defaultAssetPath {
            return .video(path: vPath)
        }
        return .none
    }

    // MARK: - Telemetry & Media Feeds

    public func updateTelemetry(_ newTelemetry: SystemTelemetry) {
        self.telemetry = newTelemetry
    }

    public func updateAudioSpectrum(_ data: AudioSpectrumData) {
        self.audioSpectrum = data
    }

    public func updateNowPlaying(_ info: NowPlayingInfo?) {
        self.nowPlaying = info ?? NowPlayingInfo()
    }

    public func updateDisplays(_ newDisplays: [DisplayInfo]) {
        self.displays = newDisplays
        if selectedDisplayID == nil || !newDisplays.contains(where: { $0.displayID == selectedDisplayID }) {
            self.selectedDisplayID = newDisplays.first(where: { $0.isMain })?.displayID ?? newDisplays.first?.displayID
        }
    }

    public func updateActiveWallpaperAccentColor() {
        let active = activeWallpaper()
        self.activeWallpaperAccentColor = WallpaperColorExtractor.shared.dominantAccentColor(for: active)
    }

    public func updateActiveTheme(_ theme: WallpaperTheme) {
        self.activeWallpaperTheme = theme
        self.activeWallpaperAccentColor = theme.accent
    }

    public func updateThemeSettings(_ block: (inout ThemeSettings) -> Void) {
        var settings = config.hudConfig.themeSettings
        block(&settings)
        updateHUDConfig { $0.themeSettings = settings }
    }

    public func lockCurrentTheme() {
        guard let id = selectedDisplayID ?? displays.first?.displayID else { return }
        coordinator?.themeManager.lockCurrentPalette(for: id)
        if let currentTheme = coordinator?.themeManager.themes[id] {
            updateThemeSettings {
                $0.isLocked = true
                $0.manualTheme = currentTheme
            }
            showToast("Locked current wallpaper theme")
        }
    }

    public func resetThemeToAutomatic() {
        guard let id = selectedDisplayID ?? displays.first?.displayID else { return }
        coordinator?.themeManager.resetToAutomatic(for: id)
        updateThemeSettings {
            $0.isLocked = false
            $0.mode = .automatic
            $0.manualTheme = nil
        }
        showToast("Reset theme to automatic wallpaper adaptation")
    }

    // MARK: - Engine Control Actions

    public func applyShader(preset: ProceduralShaderPreset, displayID: CGDirectDisplayID? = nil) {
        activeShaderPreset = preset
        coordinator?.setShader(preset: preset, for: displayID, speed: shaderSpeed)
        if let updated = coordinator?.config {
            self.config = updated
        }
        updateActiveWallpaperAccentColor()
        showToast("Applied shader '\(preset.displayName)' to \(displayName(for: displayID))")
    }

    public func applyShaderFile(url: URL, displayID: CGDirectDisplayID? = nil) {
        coordinator?.setShader(url: url, for: displayID, speed: shaderSpeed)
        if let updated = coordinator?.config {
            self.config = updated
        }
        updateActiveWallpaperAccentColor()
        showToast("Applied custom shader '\(url.lastPathComponent)'")
    }

    public func applyParallax(url: URL, displayID: CGDirectDisplayID? = nil) {
        coordinator?.setParallaxPhoto(url: url, for: displayID, useHeadTracking: config.useHeadTracking)
        if let updated = coordinator?.config {
            self.config = updated
        }
        updateActiveWallpaperAccentColor()
        showToast("Applied 3D Parallax Scene '\(url.lastPathComponent)'")
    }

    public func applyVideo(url: URL, displayID: CGDirectDisplayID? = nil) {
        Task { @MainActor in
            do {
                try await coordinator?.setVideo(url: url, for: displayID)
                if let updated = coordinator?.config {
                    self.config = updated
                }
                refreshDiscoveredVideos()
                updateActiveWallpaperAccentColor()
                showToast("Applied video wallpaper '\(url.lastPathComponent)' to \(displayName(for: displayID))")
            } catch {
                showToast("Error setting video: \(error.localizedDescription)")
            }
        }
    }

    public func togglePlayback() {
        if isPlaybackPaused {
            coordinator?.resume()
            isPlaybackPaused = false
            showToast("Resumed desktop wallpaper playback")
        } else {
            coordinator?.pause()
            isPlaybackPaused = true
            showToast("Paused desktop wallpaper playback")
        }
    }

    public func setShaderSpeed(_ speed: Float) {
        shaderSpeed = speed
        coordinator?.updateConfig { cfg in
            cfg.shaderSpeed = speed
        }
        coordinator?.shaderViews.values.forEach { $0.setSpeed(speed) }
    }

    public func toggleAudioReactive() {
        let newValue = !isAudioReactive
        isAudioReactive = newValue
        coordinator?.updateConfig { cfg in
            cfg.isAudioReactive = newValue
        }
        showToast(newValue ? "Audio-Reactive pulsing enabled" : "Audio-Reactive pulsing disabled")
    }

    public func updateHUDConfig(_ block: (inout EngineConfig.HUDConfig) -> Void) {
        var hud = config.hudConfig
        block(&hud)
        config.hudConfig = hud

        coordinator?.updateConfig { cfg in
            cfg.hudConfig = hud
        }
        showToast("Desktop HUD updated")
    }

    public func setTargetFrameRate(_ fps: Int) {
        config.targetFrameRate = fps
        coordinator?.updateConfig { cfg in
            cfg.targetFrameRate = fps
        }
        showToast("Target frame rate set to \(fps) FPS")
    }

    public func updatePowerConfig(_ block: (inout EngineConfig) -> Void) {
        block(&config)
        coordinator?.updateConfig { cfg in
            cfg = self.config
        }
        showToast("Power & Performance preferences updated")
    }

    // MARK: - Toast Banner Helpers

    public func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                self.toastMessage = nil
            }
        }
    }

    private func displayName(for displayID: CGDirectDisplayID?) -> String {
        guard let id = displayID else { return "All Displays" }
        return displays.first(where: { $0.displayID == id })?.name ?? "Display \(id)"
    }
}

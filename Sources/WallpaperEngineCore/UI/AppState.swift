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

    // MARK: - Engine Control Actions

    public func applyShader(preset: ProceduralShaderPreset, displayID: CGDirectDisplayID? = nil) {
        activeShaderPreset = preset
        coordinator?.setShader(preset: preset, for: displayID, speed: shaderSpeed)
        showToast("Applied shader '\(preset.displayName)' to \(displayName(for: displayID))")
    }

    public func applyShaderFile(url: URL, displayID: CGDirectDisplayID? = nil) {
        coordinator?.setShader(url: url, for: displayID, speed: shaderSpeed)
        showToast("Applied custom shader '\(url.lastPathComponent)'")
    }

    public func applyParallax(url: URL, displayID: CGDirectDisplayID? = nil) {
        coordinator?.setParallaxPhoto(url: url, for: displayID, useHeadTracking: config.useHeadTracking)
        showToast("Applied 3D Parallax Scene '\(url.lastPathComponent)'")
    }

    public func applyVideo(url: URL, displayID: CGDirectDisplayID? = nil) {
        Task { @MainActor in
            do {
                try await coordinator?.setVideo(url: url, for: displayID)
                showToast("Applied video wallpaper '\(url.lastPathComponent)'")
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

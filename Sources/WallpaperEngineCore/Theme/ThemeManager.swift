//
//  ThemeManager.swift
//  WallpaperEngineCore
//
//  Feature: Automatic Wallpaper-Aware Dynamic Widget Theming
//  Central coordinator managing wallpaper detection, color extraction,
//  semantic theme generation, hysteresis stabilization, and live video sampling.
//

import AppKit
import CoreGraphics
import CoreMedia
import Foundation
import os

@MainActor
public protocol ThemeManagerDelegate: AnyObject {
    func themeManager(_ manager: ThemeManager, didUpdateTheme theme: WallpaperTheme, for displayID: CGDirectDisplayID)
}

@MainActor
public final class ThemeManager: WallpaperMonitorDelegate {

    public static let shared = ThemeManager()
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "ThemeManager")

    public weak var delegate: ThemeManagerDelegate?
    public var onThemeUpdate: ((CGDirectDisplayID, WallpaperTheme) -> Void)?

    // Subsystems
    public let monitor: WallpaperMonitor
    public let imageProvider: WallpaperImageProvider
    public let extractor: WallpaperColorExtractor
    public let generator: AdaptiveThemeGenerator

    // State & Settings
    public var settings: ThemeSettings {
        didSet {
            handleSettingsChanged()
        }
    }

    public private(set) var themes: [CGDirectDisplayID: WallpaperTheme] = [:]
    private var generationIDs: [CGDirectDisplayID: UInt64] = [:]
    private var liveSamplingTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]

    // Video Player Provider closure (to access currentTime and video frames for Mode B)
    public var videoTimeProvider: ((CGDirectDisplayID) -> CMTime?)?
    public var videoURLProvider: ((CGDirectDisplayID) -> URL?)?
    public var isEnginePaused: (() -> Bool)?

    public init(
        monitor: WallpaperMonitor = WallpaperMonitor(),
        imageProvider: WallpaperImageProvider = WallpaperImageProvider.shared,
        extractor: WallpaperColorExtractor = WallpaperColorExtractor.shared,
        generator: AdaptiveThemeGenerator = AdaptiveThemeGenerator.shared,
        settings: ThemeSettings = .default
    ) {
        self.monitor = monitor
        self.imageProvider = imageProvider
        self.extractor = extractor
        self.generator = generator
        self.settings = settings

        self.monitor.delegate = self
    }

    public func start() {
        monitor.start()
        logger.info("ThemeManager started.")
    }

    public func stop() {
        monitor.stop()
        stopAllLiveSampling()
        logger.info("ThemeManager stopped.")
    }

    // MARK: - Settings Updates

    private func handleSettingsChanged() {
        if settings.isLocked || settings.mode == .manual {
            stopAllLiveSampling()
            if let manual = settings.manualTheme {
                for id in themes.keys {
                    applyTheme(manual, for: id, notify: true)
                }
            }
            return
        }

        // Restart or reconcile live sampling
        for (id, _) in themes {
            reconcileLiveSampling(for: id)
        }
    }

    public func lockCurrentPalette(for displayID: CGDirectDisplayID) {
        settings.isLocked = true
        if let current = themes[displayID] {
            settings.manualTheme = current
        }
    }

    public func resetToAutomatic(for displayID: CGDirectDisplayID) {
        settings.isLocked = false
        settings.mode = .automatic
        settings.manualTheme = nil
        recheckWallpaper(for: displayID)
    }

    // MARK: - WallpaperMonitorDelegate Callback

    public func wallpaperMonitorDidDetectChange(
        _ monitor: WallpaperMonitor,
        displayID: CGDirectDisplayID,
        info: WallpaperSourceInfo
    ) {
        Task { @MainActor [weak self] in
            await self?.processWallpaperChange(displayID: displayID, info: info)
        }
    }

    public func recheckWallpaper(for displayID: CGDirectDisplayID) {
        monitor.recheckSystemWallpapers()
    }

    // MARK: - Asynchronous Theme Extraction Pipeline

    public func processWallpaperChange(displayID: CGDirectDisplayID, info: WallpaperSourceInfo) async {
        guard !settings.isLocked && settings.mode != .manual else {
            logger.info("Theme is locked or manual; skipping automatic change.")
            return
        }

        // Increment generation ID to invalidate any prior in-flight task for this display
        let currentGen = (generationIDs[displayID] ?? 0) + 1
        generationIDs[displayID] = currentGen

        let palette: ExtractedPalette
        switch info.type {
        case .applicationShader(let preset):
            palette = imageProvider.proceduralShaderPalette(for: preset)

        case .applicationCustomShader:
            palette = ExtractedPalette(
                dominant: CodableRGBA(red: 0.00, green: 0.88, blue: 0.98),
                vibrant: CodableRGBA(red: 0.00, green: 0.94, blue: 1.00),
                secondary: CodableRGBA(red: 0.45, green: 0.40, blue: 0.95),
                darkMuted: CodableRGBA(red: 0.06, green: 0.08, blue: 0.12),
                lightMuted: CodableRGBA(red: 0.92, green: 0.96, blue: 0.98),
                averageLuminance: 0.20,
                isPredominantlyDark: true
            )

        case .applicationVideo(let path):
            let url = URL(fileURLWithPath: path)
            if let pal = await extractor.extractPalette(fromVideoAt: url) {
                palette = pal
            } else {
                palette = .fallback
            }

        case .applicationParallax(let path):
            let url = URL(fileURLWithPath: path)
            if let pal = await extractor.extractPalette(fromImageAt: url) {
                palette = pal
            } else {
                palette = .fallback
            }

        case .applicationStaticImage(let path):
            let url = URL(fileURLWithPath: path)
            if let pal = await extractor.extractPalette(fromImageAt: url) {
                palette = pal
            } else {
                palette = .fallback
            }

        case .applicationWeb:
            palette = ExtractedPalette(
                dominant: CodableRGBA(red: 0.15, green: 0.20, blue: 0.30),
                vibrant: CodableRGBA(red: 0.20, green: 0.60, blue: 1.00),
                secondary: CodableRGBA(red: 0.10, green: 0.80, blue: 0.90),
                darkMuted: CodableRGBA(red: 0.05, green: 0.07, blue: 0.10),
                lightMuted: CodableRGBA(red: 0.92, green: 0.96, blue: 0.98),
                averageLuminance: 0.25,
                isPredominantlyDark: true
            )

        case .applicationParticles(let scene):
            switch scene {
            case .rain:
                palette = ExtractedPalette(
                    dominant: CodableRGBA(red: 0.10, green: 0.15, blue: 0.25),
                    vibrant: CodableRGBA(red: 0.40, green: 0.70, blue: 0.95),
                    secondary: CodableRGBA(red: 0.20, green: 0.40, blue: 0.60),
                    darkMuted: CodableRGBA(red: 0.05, green: 0.08, blue: 0.12),
                    lightMuted: CodableRGBA(red: 0.80, green: 0.90, blue: 0.98),
                    averageLuminance: 0.20,
                    isPredominantlyDark: true
                )
            case .snow:
                palette = ExtractedPalette(
                    dominant: CodableRGBA(red: 0.20, green: 0.25, blue: 0.35),
                    vibrant: CodableRGBA(red: 0.85, green: 0.92, blue: 1.00),
                    secondary: CodableRGBA(red: 0.50, green: 0.65, blue: 0.80),
                    darkMuted: CodableRGBA(red: 0.10, green: 0.12, blue: 0.18),
                    lightMuted: CodableRGBA(red: 0.95, green: 0.98, blue: 1.00),
                    averageLuminance: 0.35,
                    isPredominantlyDark: false
                )
            case .ambientFireflies:
                palette = ExtractedPalette(
                    dominant: CodableRGBA(red: 0.05, green: 0.12, blue: 0.08),
                    vibrant: CodableRGBA(red: 0.80, green: 1.00, blue: 0.20),
                    secondary: CodableRGBA(red: 0.40, green: 0.80, blue: 0.30),
                    darkMuted: CodableRGBA(red: 0.02, green: 0.06, blue: 0.03),
                    lightMuted: CodableRGBA(red: 0.90, green: 0.98, blue: 0.85),
                    averageLuminance: 0.15,
                    isPredominantlyDark: true
                )
            }


        case .systemDesktopImage(let url):
            if let pal = await extractor.extractPalette(fromImageAt: url) {
                palette = pal
            } else {
                palette = .fallback
            }

        case .none:
            // Fallback to system desktop image
            if let sysURL = imageProvider.systemWallpaperURL(for: displayID),
               let pal = await extractor.extractPalette(fromImageAt: sysURL) {
                palette = pal
            } else {
                palette = .fallback
            }
        }

        // Verify task is still current (cancellation check)
        guard generationIDs[displayID] == currentGen else {
            logger.info("Discarding stale theme extraction (Gen \(currentGen) superseded by \(self.generationIDs[displayID] ?? 0)).")
            return
        }

        let newTheme = generator.generateTheme(from: palette, settings: settings, identifier: info.identifier)
        applyTheme(newTheme, for: displayID, notify: true)
        reconcileLiveSampling(for: displayID)
    }

    // MARK: - Theme Application & Hysteresis Check

    public func applyTheme(_ theme: WallpaperTheme, for displayID: CGDirectDisplayID, notify: Bool) {
        if let existing = themes[displayID] {
            let diff = theme.difference(from: existing)
            // Hysteresis threshold: if difference is < 0.06, suppress update to prevent flicker
            if diff < 0.06 && theme.isDark == existing.isDark {
                return
            }
        }

        themes[displayID] = theme
        if notify {
            delegate?.themeManager(self, didUpdateTheme: theme, for: displayID)
            onThemeUpdate?(displayID, theme)
        }
    }

    // MARK: - Mode B: Live Adaptive Video Sampling

    private func reconcileLiveSampling(for displayID: CGDirectDisplayID) {
        liveSamplingTasks[displayID]?.cancel()
        liveSamplingTasks.removeValue(forKey: displayID)

        let shouldSample: Bool
        switch settings.mode {
        case .liveAdaptive:
            shouldSample = true
        case .automatic:
            // In automatic mode, enable live sampling if playing a video
            shouldSample = videoURLProvider?(displayID) != nil
        case .staticAdaptive, .manual:
            shouldSample = false
        }

        guard shouldSample, let videoURL = videoURLProvider?(displayID) else { return }

        let interval = UInt64(settings.liveUpdateInterval * 1_000_000_000)
        let task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    break
                }

                guard let self = self, !Task.isCancelled else { break }
                if self.isEnginePaused?() == true { continue }

                let time = self.videoTimeProvider?(displayID) ?? CMTime(seconds: 0, preferredTimescale: 600)
                if let pal = await self.extractor.extractPalette(fromVideoAt: videoURL, at: time) {
                    let liveTheme = self.generator.generateTheme(from: pal, settings: self.settings, identifier: "live:\(videoURL.lastPathComponent)")
                    self.applyTheme(liveTheme, for: displayID, notify: true)
                }
            }
        }
        liveSamplingTasks[displayID] = task
    }

    private func stopAllLiveSampling() {
        for (_, task) in liveSamplingTasks {
            task.cancel()
        }
        liveSamplingTasks.removeAll()
    }
}

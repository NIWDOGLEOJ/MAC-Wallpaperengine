//
//  AppCoordinator.swift
//  WallpaperEngineCore
//
//  Feature F18: Central lifecycle orchestrator and state synchronization engine.
//

import AppKit
import CoreGraphics
import Foundation
import OSLog

// MARK: - App Coordinator Protocol

@MainActor
public protocol AppCoordinatorProtocol: AnyObject {
    var isRunning: Bool { get }
    var config: EngineConfig { get }
    var windowManager: DesktopWindowManagerProtocol { get }
    var videoEngine: VideoEngineProtocol { get }
    var powerObserver: PowerObserverProtocol { get }
    var sleepLockObserver: SleepLockObserverProtocol { get }
    var occlusionManager: OcclusionManagerProtocol { get }
    var menuBarController: MenuBarControllerProtocol? { get }
    var lastDecisions: [CGDirectDisplayID: PlaybackDecision] { get }

    var parallaxViews: [CGDirectDisplayID: ParallaxWallpaperView] { get }
    var shaderViews: [CGDirectDisplayID: ShaderWallpaperView] { get }
    var cpuWallpaperViews: [CGDirectDisplayID: CPULiveWallpaperView] { get }
    var staticWallpaperViews: [CGDirectDisplayID: StaticWallpaperView] { get }
    var webWallpaperViews: [CGDirectDisplayID: WebWallpaperView] { get }
    var particleViews: [CGDirectDisplayID: InteractiveParticleWallpaperView] { get }
    var hudViews: [CGDirectDisplayID: DesktopHUDView] { get }
    var audioCapture: SystemAudioCapture { get }
    var nowPlayingMonitor: NowPlayingMonitor { get }
    var telemetryMonitor: SystemTelemetryMonitor { get }
    var memoryPressureMonitor: MemoryPressureMonitor { get }
    var performanceRulesManager: PerformanceRulesManager { get }
    var libraryManager: WallpaperLibraryManager { get }
    var playlistManager: WallpaperPlaylistManager { get }
    var profileManager: ProfileManager { get }
    var editor: WallpaperEditor { get }
    var displaySpanManager: DisplaySpanManager { get }
    var appState: AppState? { get }
    var mainWindowController: MainWindowController? { get }
    var themeManager: ThemeManager { get }

    func start()
    func stop()
    func togglePlayback()
    func pause()
    func resume()
    func showMainWindow()
    func toggleMainWindow()
    func setVideo(url: URL, for displayID: CGDirectDisplayID?) async throws
    func setPhoto(url: URL, for displayID: CGDirectDisplayID?, useHeadTracking: Bool?) async throws
    func setParallaxPhoto(url: URL, for displayID: CGDirectDisplayID?, useHeadTracking: Bool?)
    func setStaticImage(url: URL, for displayID: CGDirectDisplayID?, scalingMode: StaticWallpaperView.ScalingMode) async throws
    func setWebWallpaper(url: URL, for displayID: CGDirectDisplayID?, allowNetwork: Bool)
    func setParticles(scene: ParticleSceneType, for displayID: CGDirectDisplayID?)
    func setSpanned(_ spanned: Bool)
    func applyProfile(_ profile: EngineProfile)
    func setShader(preset: ProceduralShaderPreset, for displayID: CGDirectDisplayID?, speed: Float?)
    func setShader(url: URL, for displayID: CGDirectDisplayID?, speed: Float?)
    func attachOrUpdateHUD(for displayID: CGDirectDisplayID, in window: DesktopWindowProtocol)
    func activeWallpaperType(for displayID: CGDirectDisplayID) -> ActiveWallpaperType
    func syncWallpaperAccentColor(for displayID: CGDirectDisplayID)
    func updateConfig(_ update: (inout EngineConfig) -> Void)
    func setCPUOnlyEngine(_ enabled: Bool)
    func reconcileAllScreens()
    func flushConfigToDisk()
}

// MARK: - Concrete AppCoordinator Implementation

@MainActor
public final class AppCoordinator: NSObject,
    AppCoordinatorProtocol,
    DesktopWindowManagerDelegate,
    PowerObserverDelegate,
    SleepLockObserverDelegate,
    OcclusionManagerDelegate,
    VideoEngineDelegate,
    MenuBarControllerDelegate,
    MemoryPressureDelegate,
    PerformanceRulesDelegate,
    WallpaperPlaylistDelegate
{
    public private(set) var isRunning: Bool = false
    public private(set) var config: EngineConfig
    public let windowManager: DesktopWindowManagerProtocol
    public let videoEngine: VideoEngineProtocol
    public let powerObserver: PowerObserverProtocol
    public let sleepLockObserver: SleepLockObserverProtocol
    public let occlusionManager: OcclusionManagerProtocol
    public let menuBarController: MenuBarControllerProtocol?
    public private(set) var lastDecisions: [CGDirectDisplayID: PlaybackDecision] = [:]

    private var activeDisplayIDs: Set<CGDirectDisplayID> = []
    private var attachedWindows: [CGDirectDisplayID: DesktopWindowProtocol] = [:]
    public private(set) var parallaxViews: [CGDirectDisplayID: ParallaxWallpaperView] = [:]
    public private(set) var shaderViews: [CGDirectDisplayID: ShaderWallpaperView] = [:]
    public private(set) var cpuWallpaperViews: [CGDirectDisplayID: CPULiveWallpaperView] = [:]
    public private(set) var staticWallpaperViews: [CGDirectDisplayID: StaticWallpaperView] = [:]
    public private(set) var webWallpaperViews: [CGDirectDisplayID: WebWallpaperView] = [:]
    public private(set) var particleViews: [CGDirectDisplayID: InteractiveParticleWallpaperView] = [:]
    public private(set) var hudViews: [CGDirectDisplayID: DesktopHUDView] = [:]
    public let audioCapture: SystemAudioCapture
    public let nowPlayingMonitor: NowPlayingMonitor
    public let telemetryMonitor: SystemTelemetryMonitor
    public let memoryPressureMonitor: MemoryPressureMonitor
    public let performanceRulesManager: PerformanceRulesManager
    public let libraryManager: WallpaperLibraryManager
    public let playlistManager: WallpaperPlaylistManager
    public let profileManager: ProfileManager
    public let editor: WallpaperEditor
    public let displaySpanManager: DisplaySpanManager
    public let themeManager: ThemeManager
    public private(set) var appState: AppState?
    public private(set) var mainWindowController: MainWindowController?
    private let configStorage: ConfigStorageProtocol
    private var configSaveTask: Task<Void, Never>?
    public let isHeadless: Bool
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "AppCoordinator")

    private var currentPowerState: PowerState
    private var currentSleepLockState: SleepLockState

    public init(
        config: EngineConfig? = nil,
        configStorage: ConfigStorageProtocol = FileConfigStorage(),
        windowManager: DesktopWindowManagerProtocol = DesktopWindowManager(),
        videoEngine: VideoEngineProtocol? = nil,
        powerObserver: PowerObserverProtocol = PowerObserver(),
        sleepLockObserver: SleepLockObserverProtocol = SleepLockObserver(),
        occlusionManager: OcclusionManagerProtocol = OcclusionManager(),
        menuBarController: MenuBarControllerProtocol? = nil,
        audioCapture: SystemAudioCapture = SystemAudioCapture(),
        nowPlayingMonitor: NowPlayingMonitor = NowPlayingMonitor(),
        telemetryMonitor: SystemTelemetryMonitor = SystemTelemetryMonitor(),
        cliOptions: CommandLineOptions? = nil,
        performanceRulesManager: PerformanceRulesManager? = nil,
        memoryPressureMonitor: MemoryPressureMonitor? = nil
    ) {
        var resolvedConfig = config ?? configStorage.load() ?? EngineConfig.default

        // Apply CLI overrides if provided
        if let cli = cliOptions {
            cli.apply(to: &resolvedConfig)
        }

        self.config = resolvedConfig
        self.configStorage = configStorage
        self.windowManager = windowManager
        self.videoEngine = videoEngine ?? VideoEngine(windowManager: nil, configuration: .default)
        self.powerObserver = powerObserver
        self.sleepLockObserver = sleepLockObserver
        self.occlusionManager = occlusionManager
        self.audioCapture = audioCapture
        self.nowPlayingMonitor = nowPlayingMonitor
        self.telemetryMonitor = telemetryMonitor
        self.telemetryMonitor.isCPUOnlyMode = resolvedConfig.useCPUOnlyEngine
        self.memoryPressureMonitor = memoryPressureMonitor ?? MemoryPressureMonitor()
        self.performanceRulesManager = performanceRulesManager ?? PerformanceRulesManager()
        self.libraryManager = WallpaperLibraryManager()
        self.playlistManager = WallpaperPlaylistManager()
        self.profileManager = ProfileManager()
        self.editor = WallpaperEditor()
        self.displaySpanManager = DisplaySpanManager.shared
        self.themeManager = ThemeManager(settings: resolvedConfig.hudConfig.themeSettings)
        self.currentPowerState = powerObserver.currentState
        self.currentSleepLockState = sleepLockObserver.currentState

        let headlessFlag = cliOptions?.isHeadless ?? false
        self.isHeadless = headlessFlag

        if let explicitMenuBar = menuBarController {
            self.menuBarController = explicitMenuBar
        } else if !headlessFlag {
            self.menuBarController = MenuBarController(isHeadless: false, config: resolvedConfig)
        } else {
            self.menuBarController = nil
        }

        super.init()

        // Initialize central observable UI state & window controller
        let state = AppState(config: resolvedConfig, coordinator: self)
        self.appState = state
        if !headlessFlag {
            self.mainWindowController = MainWindowController(appState: state)
        }

        // Wire delegate relationships
        self.windowManager.delegate = self
        self.powerObserver.delegate = self
        self.sleepLockObserver.delegate = self
        self.occlusionManager.delegate = self
        self.videoEngine.delegate = self
        self.memoryPressureMonitor.delegate = self
        self.performanceRulesManager.delegate = self
        self.playlistManager.delegate = self
        self.menuBarController?.delegate = self

        // Wire ThemeManager Callbacks
        self.themeManager.videoTimeProvider = { [weak self] displayID in
            self?.videoEngine.player(for: displayID)?.currentTime
        }
        self.themeManager.videoURLProvider = { [weak self] displayID in
            guard let self = self else { return nil }
            let key = String(displayID)
            if let path = self.config.displayConfigurations[key]?.assetPath {
                return URL(fileURLWithPath: path)
            }
            if let path = self.config.defaultAssetPath {
                return URL(fileURLWithPath: path)
            }
            return nil
        }
        self.themeManager.isEnginePaused = { [weak self] in
            self?.config.isPaused ?? false
        }
        self.themeManager.onThemeUpdate = { [weak self] displayID, theme in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.hudViews[displayID]?.applyTheme(theme, animated: true)
                self.appState?.updateActiveTheme(theme)
            }
        }

        // Wire Audio & Telemetry Callbacks
        self.audioCapture.onSpectrumUpdate = { [weak self] spectrum in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                if self.appState?.selectedTab == .audio {
                    self.appState?.updateAudioSpectrum(spectrum)
                }
                if self.config.isAudioReactive {
                    for sView in self.shaderViews.values {
                        sView.updateAudio(spectrum: spectrum)
                    }
                    for cView in self.cpuWallpaperViews.values {
                        cView.updateAudio(spectrum: spectrum)
                    }
                }
                if self.config.hudConfig.isEnabled && self.config.hudConfig.showAudioVisualizer {
                    for hView in self.hudViews.values {
                        hView.updateSpectrum(spectrum)
                    }
                }
            }
        }

        self.telemetryMonitor.onTelemetryUpdate = { [weak self] telemetry in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                self.appState?.updateTelemetry(telemetry)
                if self.config.hudConfig.isEnabled && self.config.hudConfig.showSystemStats {
                    for hView in self.hudViews.values {
                        hView.updateTelemetry(telemetry)
                    }
                }
            }
        }

        self.nowPlayingMonitor.onNowPlayingChange = { [weak self] info in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                self.appState?.updateNowPlaying(info)
                if self.config.hudConfig.isEnabled && self.config.hudConfig.showNowPlaying {
                    for hView in self.hudViews.values {
                        hView.updateNowPlaying(info)
                    }
                }
            }
        }
    }

    // MARK: - Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        logger.info("Starting AppCoordinator...")

        // 1. Initialize and configure Menu Bar
        if let menu = menuBarController {
            menu.start()
            menu.updateConfig(config)
        }

        // 2. Start Window Manager & Screen Monitoring
        windowManager.start()

        // 3. Start Video Playback Engine
        videoEngine.start()

        // 4. Register initial windows and connect display video players
        for (displayID, window) in windowManager.managedWindows {
            attachDisplay(displayID: displayID, window: window)
        }

        // 5. Start Power & Sleep/Lock Observers, Rules & Memory Pressure
        powerObserver.start()
        sleepLockObserver.start()
        memoryPressureMonitor.start()
        if !isHeadless {
            performanceRulesManager.start()
        }
        self.currentPowerState = powerObserver.currentState
        self.currentSleepLockState = sleepLockObserver.currentState

        // 6. Start Audio Capture, Media & Telemetry Monitors
        if config.isAudioReactive {
            audioCapture.start()
        }
        nowPlayingMonitor.start()
        telemetryMonitor.start()

        // 7. Perform initial state reconciliation & populate Menu Bar displays
        reconcileAllScreens()
        refreshMenuBarDisplays()

        // 8. Start Dynamic Wallpaper Theme Manager
        themeManager.start()
        logger.info("AppCoordinator started successfully with \(self.windowManager.managedWindows.count) displays.")
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        logger.info("Stopping AppCoordinator...")

        // 0. Halt Dynamic Wallpaper Theme Manager & Playlists
        themeManager.stop()
        playlistManager.stop()
        editor.stopPreview()

        // 1. Halt observers to prevent callbacks during teardown
        powerObserver.stop()
        sleepLockObserver.stop()
        memoryPressureMonitor.stop()
        performanceRulesManager.stop()

        // 2. Halt audio & telemetry monitors
        audioCapture.stop()
        nowPlayingMonitor.stop()
        telemetryMonitor.stop()

        // 3. Flush pending config persistence synchronously
        flushConfigToDisk()

        // 4. Tear down Menu Bar UI
        menuBarController?.stop()

        // 5. Tear down video players and windows
        videoEngine.stop()
        windowManager.stop()

        for (_, pView) in parallaxViews {
            pView.pause()
            pView.removeFromSuperview()
        }
        parallaxViews.removeAll()

        for (_, sView) in shaderViews {
            sView.pause()
            sView.removeFromSuperview()
        }
        shaderViews.removeAll()

        for (_, cView) in cpuWallpaperViews {
            cView.pause()
            cView.removeFromSuperview()
        }
        cpuWallpaperViews.removeAll()

        for (_, stView) in staticWallpaperViews {
            stView.clear()
            stView.removeFromSuperview()
        }
        staticWallpaperViews.removeAll()

        for (_, wView) in webWallpaperViews {
            wView.teardownWebView()
            wView.removeFromSuperview()
        }
        webWallpaperViews.removeAll()

        for (_, ptView) in particleViews {
            ptView.stopRenderLoop()
            ptView.removeFromSuperview()
        }
        particleViews.removeAll()

        for (_, hView) in hudViews {
            hView.removeFromSuperview()
        }
        hudViews.removeAll()

        // 6. Reset cached decisions
        activeDisplayIDs.removeAll()
        attachedWindows.removeAll()
        lastDecisions.removeAll()
        logger.info("AppCoordinator stopped cleanly.")
    }

    // MARK: - Display Wiring Helper

    private func attachDisplay(displayID: CGDirectDisplayID, window: DesktopWindowProtocol) {
        activeDisplayIDs.insert(displayID)
        attachedWindows[displayID] = window
        occlusionManager.registerDisplay(displayID, isVisible: true)
        videoEngine.registerDisplay(displayID)

        let dispConfig = config.displayConfigurations[String(displayID)]

        // 0. CPU-Only Engine Mode Priority (Strictly 0% GPU)
        if config.useCPUOnlyEngine {
            let preset: ProceduralShaderPreset
            if let dCfg = dispConfig, let sName = dCfg.shaderName, let p = ProceduralShaderPreset(rawValue: sName) {
                preset = p
            } else if let sName = config.shaderName, let p = ProceduralShaderPreset(rawValue: sName) {
                preset = p
            } else {
                preset = .aurora
            }
            attachCPUShader(to: window, displayID: displayID, preset: preset)
            attachOrUpdateHUD(for: displayID, in: window)
            return
        }

        // 1. Resolve display-specific configuration first
        if let dCfg = dispConfig {
            if let iPath = dCfg.staticImagePath, FileManager.default.fileExists(atPath: iPath) {
                let iURL = URL(fileURLWithPath: iPath)
                attachStaticImage(to: window, displayID: displayID, imageURL: iURL)
                attachOrUpdateHUD(for: displayID, in: window)
                return
            } else if let wPath = dCfg.webPath, FileManager.default.fileExists(atPath: wPath) {
                let wURL = URL(fileURLWithPath: wPath)
                attachWeb(to: window, displayID: displayID, htmlURL: wURL)
                attachOrUpdateHUD(for: displayID, in: window)
                return
            } else if let pScene = dCfg.particleSceneName, let scene = ParticleSceneType(rawValue: pScene) {
                attachParticles(to: window, displayID: displayID, sceneType: scene)
                attachOrUpdateHUD(for: displayID, in: window)
                return
            } else if let sName = dCfg.shaderName, let preset = ProceduralShaderPreset(rawValue: sName) {
                attachShader(to: window, displayID: displayID, preset: preset)
                attachOrUpdateHUD(for: displayID, in: window)
                return
            } else if let sPath = dCfg.shaderPath, FileManager.default.fileExists(atPath: sPath) {
                let sURL = URL(fileURLWithPath: sPath)
                attachShader(to: window, displayID: displayID, fileURL: sURL)
                attachOrUpdateHUD(for: displayID, in: window)
                return
            } else if let pPath = dCfg.photoPath, FileManager.default.fileExists(atPath: pPath) {
                let pURL = URL(fileURLWithPath: pPath)
                attachParallax(to: window, displayID: displayID, photoURL: pURL)
                attachOrUpdateHUD(for: displayID, in: window)
                return
            } else if let vPath = dCfg.assetPath, FileManager.default.fileExists(atPath: vPath) {
                if let player = videoEngine.player(for: displayID) {
                    window.attachPlayerLayer(player.playerLayer)
                }
                let url = URL(fileURLWithPath: vPath)
                Task { @MainActor [weak self] in
                    try? await self?.videoEngine.setVideo(url: url, for: displayID)
                }
                attachOrUpdateHUD(for: displayID, in: window)
                return
            }
        }

        // 2. Fall back to global configuration
        if let iPath = config.staticImagePath, FileManager.default.fileExists(atPath: iPath) {
            let iURL = URL(fileURLWithPath: iPath)
            attachStaticImage(to: window, displayID: displayID, imageURL: iURL)
            attachOrUpdateHUD(for: displayID, in: window)
            return
        } else if let wPath = config.webPath, FileManager.default.fileExists(atPath: wPath) {
            let wURL = URL(fileURLWithPath: wPath)
            attachWeb(to: window, displayID: displayID, htmlURL: wURL)
            attachOrUpdateHUD(for: displayID, in: window)
            return
        } else if let pScene = config.particleSceneName, let scene = ParticleSceneType(rawValue: pScene) {
            attachParticles(to: window, displayID: displayID, sceneType: scene)
            attachOrUpdateHUD(for: displayID, in: window)
            return
        } else if let sName = config.shaderName, let preset = ProceduralShaderPreset(rawValue: sName) {
            attachShader(to: window, displayID: displayID, preset: preset)
            attachOrUpdateHUD(for: displayID, in: window)
            return
        } else if let sPath = config.shaderPath, FileManager.default.fileExists(atPath: sPath) {
            let sURL = URL(fileURLWithPath: sPath)
            attachShader(to: window, displayID: displayID, fileURL: sURL)
            attachOrUpdateHUD(for: displayID, in: window)
            return
        } else if let pPath = config.photoPath, FileManager.default.fileExists(atPath: pPath) {
            let pURL = URL(fileURLWithPath: pPath)
            attachParallax(to: window, displayID: displayID, photoURL: pURL)
            attachOrUpdateHUD(for: displayID, in: window)
            return
        } else if let vPath = config.defaultAssetPath, FileManager.default.fileExists(atPath: vPath) {
            if let player = videoEngine.player(for: displayID) {
                window.attachPlayerLayer(player.playerLayer)
            }
            let url = URL(fileURLWithPath: vPath)
            Task { @MainActor [weak self] in
                try? await self?.videoEngine.setVideo(url: url, for: displayID)
            }
            attachOrUpdateHUD(for: displayID, in: window)
            return
        }

        // 3. Fallback: attach player layer
        if let player = videoEngine.player(for: displayID) {
            window.attachPlayerLayer(player.playerLayer)
        }
        attachOrUpdateHUD(for: displayID, in: window)
    }

    public func attachOrUpdateHUD(for displayID: CGDirectDisplayID, in window: DesktopWindowProtocol) {
        guard config.hudConfig.isEnabled else {
            hudViews[displayID]?.removeFromSuperview()
            hudViews.removeValue(forKey: displayID)
            return
        }

        let hudView: DesktopHUDView
        if let existing = hudViews[displayID] {
            hudView = existing
        } else {
            hudView = DesktopHUDView(frame: .zero)
            hudViews[displayID] = hudView
        }

        hudView.applyConfig(config.hudConfig)
        let bounds = window.underlyingWindow.contentView?.bounds ?? window.frame
        hudView.updatePlacement(in: bounds)

        // Always ensure HUD is frontmost in window's contentView
        window.underlyingWindow.contentView?.addSubview(hudView)

        if let currentTheme = themeManager.themes[displayID] {
            hudView.applyTheme(currentTheme, animated: false)
        }

        syncWallpaperAccentColor(for: displayID)
    }

    public func activeWallpaperType(for displayID: CGDirectDisplayID) -> ActiveWallpaperType {
        if let sView = staticWallpaperViews[displayID], let path = sView.currentImageURL?.path {
            return .staticImage(path: path)
        }
        if let wView = webWallpaperViews[displayID], let path = wView.currentURL?.path {
            return .web(path: path)
        }
        if let ptView = particleViews[displayID] {
            return .particles(ptView.sceneType)
        }
        if let cpuView = cpuWallpaperViews[displayID] {
            return .shader(cpuView.currentPreset)
        }
        let key = String(displayID)
        if let disp = config.displayConfigurations[key] {
            if let iPath = disp.staticImagePath {
                return .staticImage(path: iPath)
            }
            if let wPath = disp.webPath {
                return .web(path: wPath)
            }
            if let pScene = disp.particleSceneName, let scene = ParticleSceneType(rawValue: pScene) {
                return .particles(scene)
            }
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
        if let iPath = config.staticImagePath {
            return .staticImage(path: iPath)
        }
        if let wPath = config.webPath {
            return .web(path: wPath)
        }
        if let pScene = config.particleSceneName, let scene = ParticleSceneType(rawValue: pScene) {
            return .particles(scene)
        }
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

    public func wallpaperSourceType(for displayID: CGDirectDisplayID) -> WallpaperSourceType {
        let active = activeWallpaperType(for: displayID)
        switch active {
        case .shader(let preset):
            return .applicationShader(preset: preset)
        case .customShader(let path):
            return .applicationCustomShader(path: path)
        case .parallax(let path):
            return .applicationParallax(path: path)
        case .video(let path):
            return .applicationVideo(path: path)
        case .staticImage(let path):
            return .applicationStaticImage(path: path)
        case .web(let path):
            return .applicationWeb(path: path)
        case .particles(let scene):
            return .applicationParticles(scene)
        case .none:
            if let screen = windowManager.screenManager.screen(for: displayID),
               let url = NSWorkspace.shared.desktopImageURL(for: screen) {
                return .systemDesktopImage(url: url)
            }
            return .none
        }
    }

    public func syncWallpaperAccentColor(for displayID: CGDirectDisplayID) {
        let sourceType = wallpaperSourceType(for: displayID)
        themeManager.monitor.notifyApplicationWallpaperChange(displayID: displayID, type: sourceType)
    }

    private func cleanDisplayRenderers(displayID: CGDirectDisplayID) {
        if let sView = shaderViews[displayID] {
            sView.pause()
            sView.removeFromSuperview()
            shaderViews.removeValue(forKey: displayID)
        }
        if let cView = cpuWallpaperViews[displayID] {
            cView.pause()
            cView.removeFromSuperview()
            cpuWallpaperViews.removeValue(forKey: displayID)
        }
        if let pView = parallaxViews[displayID] {
            pView.pause()
            pView.removeFromSuperview()
            parallaxViews.removeValue(forKey: displayID)
        }
        if let stView = staticWallpaperViews[displayID] {
            stView.clear()
            stView.removeFromSuperview()
            staticWallpaperViews.removeValue(forKey: displayID)
        }
        if let wView = webWallpaperViews[displayID] {
            wView.teardownWebView()
            wView.removeFromSuperview()
            webWallpaperViews.removeValue(forKey: displayID)
        }
        if let ptView = particleViews[displayID] {
            ptView.stopRenderLoop()
            ptView.removeFromSuperview()
            particleViews.removeValue(forKey: displayID)
        }
    }

    private func attachCPUShader(to window: DesktopWindowProtocol, displayID: CGDirectDisplayID, preset: ProceduralShaderPreset) {
        window.removePlayerLayer()
        videoEngine.setPlaybackState(.paused(reason: .userRequested), for: displayID)

        cleanDisplayRenderers(displayID: displayID)

        let frame = window.underlyingWindow.contentView?.bounds ?? window.frame
        let cpuView = CPULiveWallpaperView(frame: frame, preset: preset)
        cpuView.autoresizingMask = [.width, .height]
        cpuView.setSpeed(config.shaderSpeed)
        cpuView.setTargetFrameRate(min(config.targetFrameRate, 30))

        window.underlyingWindow.contentView?.addSubview(cpuView)
        cpuWallpaperViews[displayID] = cpuView
        logger.info("CPU live wallpaper '\(preset.displayName)' attached to display \(displayID)")

        if let hView = hudViews[displayID] {
            window.underlyingWindow.contentView?.addSubview(hView)
        }
        syncWallpaperAccentColor(for: displayID)
    }

    private func attachShader(to window: DesktopWindowProtocol, displayID: CGDirectDisplayID, preset: ProceduralShaderPreset) {
        if config.useCPUOnlyEngine {
            attachCPUShader(to: window, displayID: displayID, preset: preset)
            return
        }

        window.removePlayerLayer()
        videoEngine.setPlaybackState(.paused(reason: .userRequested), for: displayID)

        cleanDisplayRenderers(displayID: displayID)

        let frame = window.underlyingWindow.contentView?.bounds ?? window.frame
        let shaderView = ShaderWallpaperView(frame: frame)
        shaderView.autoresizingMask = [.width, .height]
        shaderView.setSpeed(config.shaderSpeed)
        shaderView.setTargetFrameRate(config.targetFrameRate)

        do {
            try shaderView.loadPreset(preset)
            window.underlyingWindow.contentView?.addSubview(shaderView)
            shaderViews[displayID] = shaderView
            logger.info("Procedural shader '\(preset.displayName)' attached to display \(displayID)")
        } catch {
            logger.error("Failed to load procedural preset '\(preset.displayName)': \(error.localizedDescription)")
        }

        if let hView = hudViews[displayID] {
            window.underlyingWindow.contentView?.addSubview(hView)
        }
        syncWallpaperAccentColor(for: displayID)
    }

    private func attachShader(to window: DesktopWindowProtocol, displayID: CGDirectDisplayID, fileURL: URL) {
        window.removePlayerLayer()
        videoEngine.setPlaybackState(.paused(reason: .userRequested), for: displayID)

        cleanDisplayRenderers(displayID: displayID)

        let frame = window.underlyingWindow.contentView?.bounds ?? window.frame
        let shaderView = ShaderWallpaperView(frame: frame)
        shaderView.autoresizingMask = [.width, .height]
        shaderView.setSpeed(config.shaderSpeed)
        shaderView.setTargetFrameRate(config.targetFrameRate)

        do {
            try shaderView.loadShader(from: fileURL)
            window.underlyingWindow.contentView?.addSubview(shaderView)
            shaderViews[displayID] = shaderView
            logger.info("Custom shader '\(fileURL.lastPathComponent)' attached to display \(displayID)")
        } catch {
            logger.error("Failed to load custom shader from \(fileURL.path): \(error.localizedDescription)")
        }

        if let hView = hudViews[displayID] {
            window.underlyingWindow.contentView?.addSubview(hView)
        }
        syncWallpaperAccentColor(for: displayID)
    }

    private func attachParallax(to window: DesktopWindowProtocol, displayID: CGDirectDisplayID, photoURL: URL) {
        window.removePlayerLayer()
        videoEngine.setPlaybackState(.paused(reason: .userRequested), for: displayID)

        cleanDisplayRenderers(displayID: displayID)

        let frame = window.underlyingWindow.contentView?.bounds ?? window.frame
        let parallaxView = ParallaxWallpaperView(frame: frame)
        parallaxView.autoresizingMask = [.width, .height]

        let driver: ParallaxTrackingDriver
        if config.useHeadTracking {
            driver = VisionHeadTrackingDriver()
        } else {
            driver = PointerParallaxDriver()
        }
        parallaxView.attachDriver(driver)

        window.underlyingWindow.contentView?.addSubview(parallaxView)
        parallaxViews[displayID] = parallaxView

        if let hView = hudViews[displayID] {
            window.underlyingWindow.contentView?.addSubview(hView)
        }
        syncWallpaperAccentColor(for: displayID)

        Task { @MainActor [weak self] in
            do {
                try await parallaxView.loadPhoto(from: photoURL)
                self?.logger.info("3D Parallax scene attached to display \(displayID) for \(photoURL.lastPathComponent)")
            } catch {
                self?.logger.error("Failed to load 3D Parallax scene for display \(displayID): \(error.localizedDescription)")
            }
        }
    }

    private func attachStaticImage(
        to window: DesktopWindowProtocol,
        displayID: CGDirectDisplayID,
        imageURL: URL,
        scalingMode: StaticWallpaperView.ScalingMode = .aspectFill
    ) {
        window.removePlayerLayer()
        videoEngine.setPlaybackState(.paused(reason: .userRequested), for: displayID)

        cleanDisplayRenderers(displayID: displayID)

        let frame = window.underlyingWindow.contentView?.bounds ?? window.frame
        let staticView = StaticWallpaperView(frame: frame)
        staticView.autoresizingMask = [.width, .height]

        if config.isSpanned {
            staticView.scalingMode = .stretch
            let screenFrames = windowManager.screenManager.activeScreens.reduce(into: [CGDirectDisplayID: CGRect]()) { dict, screen in
                dict[screen.displayID] = screen.frame
            }
            staticView.contentsRect = displaySpanManager.normalizedContentsRect(for: displayID, allScreens: screenFrames)
        } else {
            staticView.scalingMode = scalingMode
            staticView.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        window.underlyingWindow.contentView?.addSubview(staticView)
        staticWallpaperViews[displayID] = staticView

        Task { @MainActor [weak self] in
            do {
                _ = try await staticView.loadWallpaper(from: imageURL)
                self?.logger.info("Static image wallpaper attached to display \(displayID)")
            } catch {
                self?.logger.error("Failed to load static image on display \(displayID): \(error.localizedDescription)")
            }
        }

        if let hView = hudViews[displayID] {
            window.underlyingWindow.contentView?.addSubview(hView)
        }
        syncWallpaperAccentColor(for: displayID)
    }

    private func attachWeb(
        to window: DesktopWindowProtocol,
        displayID: CGDirectDisplayID,
        htmlURL: URL,
        allowNetwork: Bool = false
    ) {
        window.removePlayerLayer()
        videoEngine.setPlaybackState(.paused(reason: .userRequested), for: displayID)

        cleanDisplayRenderers(displayID: displayID)

        let frame = window.underlyingWindow.contentView?.bounds ?? window.frame
        let webView = WebWallpaperView(frame: frame)
        webView.autoresizingMask = [.width, .height]

        window.underlyingWindow.contentView?.addSubview(webView)
        webWallpaperViews[displayID] = webView

        webView.loadWebWallpaper(from: htmlURL, allowNetwork: allowNetwork)

        if let hView = hudViews[displayID] {
            window.underlyingWindow.contentView?.addSubview(hView)
        }
        syncWallpaperAccentColor(for: displayID)
    }

    private func attachParticles(
        to window: DesktopWindowProtocol,
        displayID: CGDirectDisplayID,
        sceneType: ParticleSceneType
    ) {
        window.removePlayerLayer()
        videoEngine.setPlaybackState(.paused(reason: .userRequested), for: displayID)

        cleanDisplayRenderers(displayID: displayID)

        let frame = window.underlyingWindow.contentView?.bounds ?? window.frame
        let particleView = InteractiveParticleWallpaperView(frame: frame, sceneType: sceneType)
        particleView.autoresizingMask = [.width, .height]

        window.underlyingWindow.contentView?.addSubview(particleView)
        particleViews[displayID] = particleView

        if let hView = hudViews[displayID] {
            window.underlyingWindow.contentView?.addSubview(hView)
        }
        syncWallpaperAccentColor(for: displayID)
    }


    // MARK: - State Reconciliation

    public func reconcileAllScreens() {
        guard isRunning else { return }

        var displayVisibilities: [CGDirectDisplayID: Bool] = [:]
        let allDisplayIDs = Set(windowManager.managedWindows.keys).union(activeDisplayIDs)
        for displayID in allDisplayIDs {
            displayVisibilities[displayID] = occlusionManager.isDisplayVisible(displayID)
        }

        let decisions = StateEvaluator.evaluate(
            manualPause: config.isPaused,
            sleepLock: currentSleepLockState,
            power: currentPowerState,
            displays: displayVisibilities,
            config: config,
            fullscreenDisplays: isHeadless ? [] : (performanceRulesManager.pauseOnFullscreen ? performanceRulesManager.fullscreenDisplays : []),
            isGameActive: isHeadless ? false : (performanceRulesManager.pauseOnGame && performanceRulesManager.isGameActive),
            isIdle: isHeadless ? false : (performanceRulesManager.pauseOnIdle && performanceRulesManager.isDesktopIdle),
            memoryPressure: memoryPressureMonitor.currentLevel
        )

        for (displayID, decision) in decisions {
            if lastDecisions[displayID] != decision {
                lastDecisions[displayID] = decision
                apply(decision: decision, to: displayID)
            }
        }

        let anyPlaying = decisions.values.contains {
            if case .play = $0 { return true }
            if case .throttle = $0 { return true }
            return false
        }
        if !anyPlaying {
            audioCapture.pause()
            nowPlayingMonitor.isPollingEnabled = false
        } else {
            if config.isAudioReactive {
                audioCapture.resume()
            }
            let hudActive = config.hudConfig.isEnabled && config.hudConfig.showNowPlaying
            nowPlayingMonitor.isPollingEnabled = hudActive
        }

        updateSpannedGeometryIfNeeded()
        updateMenuBarStatus(with: decisions)
    }

    private func apply(decision: PlaybackDecision, to displayID: CGDirectDisplayID) {
        switch decision {
        case .play(let fps):
            let activeType = activeWallpaperType(for: displayID)
            if case .staticImage = activeType {
                telemetryMonitor.currentFPS = 0
            } else {
                telemetryMonitor.currentFPS = fps
            }
            videoEngine.setPlaybackState(.playing, for: displayID)
            if let pView = parallaxViews[displayID] {
                pView.resume()
                pView.setTargetFrameRate(fps)
            }
            if let sView = shaderViews[displayID] {
                sView.resume()
                sView.setTargetFrameRate(fps)
            }
            if let cView = cpuWallpaperViews[displayID] {
                cView.resume()
                cView.setTargetFrameRate(min(fps, 30))
            }
            webWallpaperViews[displayID]?.resume()
            if let ptView = particleViews[displayID] {
                ptView.resume()
                ptView.setTargetFrameRate(fps)
            }
            hudViews[displayID]?.resume()

        case .pause(let reasons):
            telemetryMonitor.currentFPS = 0
            let primaryReason = reasons.sorted(by: { $0.rawValue < $1.rawValue }).first ?? .userRequested
            videoEngine.setPlaybackState(.paused(reason: primaryReason), for: displayID)
            parallaxViews[displayID]?.pause()
            shaderViews[displayID]?.pause()
            cpuWallpaperViews[displayID]?.pause()
            webWallpaperViews[displayID]?.pause()
            particleViews[displayID]?.pause()
            hudViews[displayID]?.pause()

        case .throttle(let fps, _):
            let activeType = activeWallpaperType(for: displayID)
            if case .staticImage = activeType {
                telemetryMonitor.currentFPS = 0
            } else {
                telemetryMonitor.currentFPS = fps
            }
            videoEngine.setPlaybackState(.throttled(fps: fps), for: displayID)
            if let pView = parallaxViews[displayID] {
                pView.resume()
                pView.setTargetFrameRate(fps)
            }
            if let sView = shaderViews[displayID] {
                sView.resume()
                sView.setTargetFrameRate(fps)
            }
            if let cView = cpuWallpaperViews[displayID] {
                cView.resume()
                cView.setTargetFrameRate(min(fps, 30))
            }
            webWallpaperViews[displayID]?.resume()
            if let ptView = particleViews[displayID] {
                ptView.resume()
                ptView.setTargetFrameRate(fps)
            }
            hudViews[displayID]?.resume()
        }
    }

    private func updateMenuBarStatus(with decisions: [CGDirectDisplayID: PlaybackDecision]) {
        guard let menu = menuBarController else { return }

        let hasPlayingScreen = decisions.values.contains {
            if case .play = $0 { return true }
            if case .throttle = $0 { return true }
            return false
        }

        let isThrottled = decisions.values.contains {
            if case .throttle = $0 { return true }
            return false
        }

        let activeFPS: Int
        if isThrottled {
            activeFPS = config.throttledFrameRate
        } else if hasPlayingScreen {
            activeFPS = config.targetFrameRate
        } else {
            activeFPS = 0
        }

        let powerInfo: String
        if config.isPaused {
            powerInfo = "Paused (User)"
        } else if currentSleepLockState.isScreenLocked {
            powerInfo = "Paused (Locked)"
        } else if currentSleepLockState.areScreensSleeping {
            powerInfo = "Paused (Display Sleep)"
        } else if currentPowerState.isLowPowerModeEnabled {
            powerInfo = "Low Power Mode"
        } else if currentPowerState.isOnBattery {
            let pct = Int((currentPowerState.batteryLevel ?? 0.0) * 100)
            powerInfo = "Battery (\(pct)%)"
        } else {
            powerInfo = "AC Power"
        }

        menu.updateStatus(isPlaying: hasPlayingScreen, fps: activeFPS, powerInfo: powerInfo)
    }

    public func refreshMenuBarDisplays() {
        appState?.updateDisplays(windowManager.screenManager.activeScreens)
        guard let menu = menuBarController else { return }

        var displayModels: [DisplayMenuItemModel] = []
        let allDisplayIDs = Set(windowManager.managedWindows.keys).union(activeDisplayIDs)
        for id in allDisplayIDs {
            let window = windowManager.managedWindows[id] ?? attachedWindows[id]
            let screen = windowManager.screenManager.screen(for: id)
            let name = screen?.localizedName ?? "Display \(id)"
            let asset = config.displayConfigurations[String(id)]?.assetPath ?? config.defaultAssetPath
            let isPaused = !(config.displayConfigurations[String(id)]?.isEnabled ?? true)

            displayModels.append(
                DisplayMenuItemModel(
                    displayID: id,
                    name: name,
                    frame: window?.frame ?? .zero,
                    currentAssetPath: asset,
                    isPaused: isPaused
                )
            )
        }
        displayModels.sort(by: { $0.displayID < $1.displayID })
        menu.updateDisplays(displayModels)
    }

    // MARK: - Playback & Media Management

    public func togglePlayback() {
        updateConfig { cfg in
            cfg.isPaused.toggle()
        }
    }

    public func pause() {
        updateConfig { cfg in
            cfg.isPaused = true
        }
    }

    public func resume() {
        updateConfig { cfg in
            cfg.isPaused = false
        }
    }

    // MARK: - Application Window Lifecycle

    public func showMainWindow() {
        mainWindowController?.showMainWindow()
    }

    public func toggleMainWindow() {
        mainWindowController?.toggleMainWindow()
    }

    public func menuBarDidRequestOpenApp(_ controller: MenuBarControllerProtocol) {
        showMainWindow()
    }

    public func setVideo(url: URL, for displayID: CGDirectDisplayID?) async throws {
        // 1. Update config cleanly enforcing mutual exclusivity
        updateConfig { cfg in
            if let id = displayID {
                let key = String(id)
                var disp = cfg.displayConfigurations[key] ?? DisplayConfig()
                disp.assetPath = url.path
                disp.photoPath = nil
                disp.shaderName = nil
                disp.shaderPath = nil
                disp.staticImagePath = nil
                disp.webPath = nil
                disp.particleSceneName = nil
                disp.isEnabled = true
                cfg.displayConfigurations[key] = disp
            } else {
                cfg.defaultAssetPath = url.path
                cfg.photoPath = nil
                cfg.shaderName = nil
                cfg.shaderPath = nil
                cfg.staticImagePath = nil
                cfg.webPath = nil
                cfg.particleSceneName = nil
                for key in cfg.displayConfigurations.keys {
                    cfg.displayConfigurations[key]?.shaderName = nil
                    cfg.displayConfigurations[key]?.shaderPath = nil
                    cfg.displayConfigurations[key]?.photoPath = nil
                    cfg.displayConfigurations[key]?.staticImagePath = nil
                    cfg.displayConfigurations[key]?.webPath = nil
                    cfg.displayConfigurations[key]?.particleSceneName = nil
                    cfg.displayConfigurations[key]?.assetPath = url.path
                }
            }
        }

        // 2. Delegate video loading to videoEngine
        try await videoEngine.setVideo(url: url, for: displayID)

        // 3. For all target displays, remove existing renderers and re-attach playerLayer
        let targetIDs: [CGDirectDisplayID]
        if let id = displayID {
            targetIDs = [id]
        } else {
            targetIDs = Array(Set(windowManager.managedWindows.keys).union(activeDisplayIDs))
        }

        for id in targetIDs {
            cleanDisplayRenderers(displayID: id)
            if let window = attachedWindows[id] ?? windowManager.managedWindows[id],
               let player = videoEngine.player(for: id) {
                window.attachPlayerLayer(player.playerLayer)
                if let hView = hudViews[id] {
                    window.underlyingWindow.contentView?.addSubview(hView)
                }
            }
            syncWallpaperAccentColor(for: id)
        }

        reconcileAllScreens()
        refreshMenuBarDisplays()
    }

    public func setPhoto(url: URL, for displayID: CGDirectDisplayID?, useHeadTracking: Bool? = nil) async throws {
        if let useHead = useHeadTracking {
            updateConfig { cfg in
                cfg.useHeadTracking = useHead
            }
        }
        updateConfig { cfg in
            if let id = displayID {
                let key = String(id)
                var disp = cfg.displayConfigurations[key] ?? DisplayConfig()
                disp.photoPath = url.path
                disp.assetPath = nil
                disp.shaderName = nil
                disp.shaderPath = nil
                disp.staticImagePath = nil
                disp.webPath = nil
                disp.particleSceneName = nil
                disp.isEnabled = true
                cfg.displayConfigurations[key] = disp
            } else {
                cfg.photoPath = url.path
                cfg.defaultAssetPath = nil
                cfg.shaderName = nil
                cfg.shaderPath = nil
                cfg.staticImagePath = nil
                cfg.webPath = nil
                cfg.particleSceneName = nil
                for key in cfg.displayConfigurations.keys {
                    cfg.displayConfigurations[key]?.assetPath = nil
                    cfg.displayConfigurations[key]?.shaderName = nil
                    cfg.displayConfigurations[key]?.shaderPath = nil
                    cfg.displayConfigurations[key]?.staticImagePath = nil
                    cfg.displayConfigurations[key]?.webPath = nil
                    cfg.displayConfigurations[key]?.particleSceneName = nil
                    cfg.displayConfigurations[key]?.photoPath = url.path
                }
            }
        }

        let targetIDs: [CGDirectDisplayID]
        if let id = displayID {
            targetIDs = [id]
        } else {
            targetIDs = Array(Set(windowManager.managedWindows.keys).union(activeDisplayIDs))
        }

        for id in targetIDs {
            if let window = attachedWindows[id] ?? windowManager.managedWindows[id] {
                attachParallax(to: window, displayID: id, photoURL: url)
            }
        }
        reconcileAllScreens()
        refreshMenuBarDisplays()
    }

    public func setParallaxPhoto(url: URL, for displayID: CGDirectDisplayID?, useHeadTracking: Bool? = nil) {
        Task { @MainActor [weak self] in
            try? await self?.setPhoto(url: url, for: displayID, useHeadTracking: useHeadTracking)
        }
    }

    public func setShader(preset: ProceduralShaderPreset, for displayID: CGDirectDisplayID? = nil, speed: Float? = nil) {
        if let sp = speed {
            updateConfig { cfg in
                cfg.shaderSpeed = sp
            }
        }
        updateConfig { cfg in
            if let id = displayID {
                let key = String(id)
                var disp = cfg.displayConfigurations[key] ?? DisplayConfig()
                disp.shaderName = preset.rawValue
                disp.shaderPath = nil
                disp.photoPath = nil
                disp.assetPath = nil
                disp.staticImagePath = nil
                disp.webPath = nil
                disp.particleSceneName = nil
                disp.isEnabled = true
                cfg.displayConfigurations[key] = disp
            } else {
                cfg.shaderName = preset.rawValue
                cfg.shaderPath = nil
                cfg.photoPath = nil
                cfg.defaultAssetPath = nil
                cfg.staticImagePath = nil
                cfg.webPath = nil
                cfg.particleSceneName = nil
                for key in cfg.displayConfigurations.keys {
                    cfg.displayConfigurations[key]?.assetPath = nil
                    cfg.displayConfigurations[key]?.photoPath = nil
                    cfg.displayConfigurations[key]?.shaderPath = nil
                    cfg.displayConfigurations[key]?.staticImagePath = nil
                    cfg.displayConfigurations[key]?.webPath = nil
                    cfg.displayConfigurations[key]?.particleSceneName = nil
                    cfg.displayConfigurations[key]?.shaderName = preset.rawValue
                }
            }
        }

        let targetIDs: [CGDirectDisplayID]
        if let id = displayID {
            targetIDs = [id]
        } else {
            targetIDs = Array(Set(windowManager.managedWindows.keys).union(activeDisplayIDs))
        }

        for id in targetIDs {
            if let window = attachedWindows[id] ?? windowManager.managedWindows[id] {
                attachShader(to: window, displayID: id, preset: preset)
            }
        }
        reconcileAllScreens()
        refreshMenuBarDisplays()
    }

    public func setShader(url: URL, for displayID: CGDirectDisplayID? = nil, speed: Float? = nil) {
        if let sp = speed {
            updateConfig { cfg in
                cfg.shaderSpeed = sp
            }
        }
        updateConfig { cfg in
            if let id = displayID {
                let key = String(id)
                var disp = cfg.displayConfigurations[key] ?? DisplayConfig()
                disp.shaderPath = url.path
                disp.shaderName = nil
                disp.photoPath = nil
                disp.assetPath = nil
                disp.staticImagePath = nil
                disp.webPath = nil
                disp.particleSceneName = nil
                disp.isEnabled = true
                cfg.displayConfigurations[key] = disp
            } else {
                cfg.shaderPath = url.path
                cfg.shaderName = nil
                cfg.photoPath = nil
                cfg.defaultAssetPath = nil
                cfg.staticImagePath = nil
                cfg.webPath = nil
                cfg.particleSceneName = nil
                for key in cfg.displayConfigurations.keys {
                    cfg.displayConfigurations[key]?.assetPath = nil
                    cfg.displayConfigurations[key]?.photoPath = nil
                    cfg.displayConfigurations[key]?.shaderName = nil
                    cfg.displayConfigurations[key]?.staticImagePath = nil
                    cfg.displayConfigurations[key]?.webPath = nil
                    cfg.displayConfigurations[key]?.particleSceneName = nil
                    cfg.displayConfigurations[key]?.shaderPath = url.path
                }
            }
        }

        let targetIDs: [CGDirectDisplayID]
        if let id = displayID {
            targetIDs = [id]
        } else {
            targetIDs = Array(Set(windowManager.managedWindows.keys).union(activeDisplayIDs))
        }

        for id in targetIDs {
            if let window = attachedWindows[id] ?? windowManager.managedWindows[id] {
                attachShader(to: window, displayID: id, fileURL: url)
            }
        }
        reconcileAllScreens()
        refreshMenuBarDisplays()
    }

    public func setStaticImage(url: URL, for displayID: CGDirectDisplayID? = nil, scalingMode: StaticWallpaperView.ScalingMode = .aspectFill) async throws {
        updateConfig { cfg in
            if let id = displayID {
                let key = String(id)
                var disp = cfg.displayConfigurations[key] ?? DisplayConfig()
                disp.staticImagePath = url.path
                disp.webPath = nil
                disp.particleSceneName = nil
                disp.photoPath = nil
                disp.assetPath = nil
                disp.shaderName = nil
                disp.shaderPath = nil
                disp.isEnabled = true
                cfg.displayConfigurations[key] = disp
            } else {
                cfg.staticImagePath = url.path
                cfg.webPath = nil
                cfg.particleSceneName = nil
                cfg.photoPath = nil
                cfg.defaultAssetPath = nil
                cfg.shaderName = nil
                cfg.shaderPath = nil
                for key in cfg.displayConfigurations.keys {
                    cfg.displayConfigurations[key]?.assetPath = nil
                    cfg.displayConfigurations[key]?.photoPath = nil
                    cfg.displayConfigurations[key]?.shaderName = nil
                    cfg.displayConfigurations[key]?.shaderPath = nil
                    cfg.displayConfigurations[key]?.webPath = nil
                    cfg.displayConfigurations[key]?.particleSceneName = nil
                    cfg.displayConfigurations[key]?.staticImagePath = url.path
                }
            }
        }

        let targetIDs: [CGDirectDisplayID]
        if let id = displayID {
            targetIDs = [id]
        } else {
            targetIDs = Array(Set(windowManager.managedWindows.keys).union(activeDisplayIDs))
        }

        for id in targetIDs {
            if let window = attachedWindows[id] ?? windowManager.managedWindows[id] {
                attachStaticImage(to: window, displayID: id, imageURL: url, scalingMode: scalingMode)
            }
        }
        reconcileAllScreens()
        refreshMenuBarDisplays()
    }

    public func setWebWallpaper(url: URL, for displayID: CGDirectDisplayID? = nil, allowNetwork: Bool = false) {
        updateConfig { cfg in
            if let id = displayID {
                let key = String(id)
                var disp = cfg.displayConfigurations[key] ?? DisplayConfig()
                disp.webPath = url.path
                disp.staticImagePath = nil
                disp.particleSceneName = nil
                disp.photoPath = nil
                disp.assetPath = nil
                disp.shaderName = nil
                disp.shaderPath = nil
                disp.isEnabled = true
                cfg.displayConfigurations[key] = disp
            } else {
                cfg.webPath = url.path
                cfg.staticImagePath = nil
                cfg.particleSceneName = nil
                cfg.photoPath = nil
                cfg.defaultAssetPath = nil
                cfg.shaderName = nil
                cfg.shaderPath = nil
                for key in cfg.displayConfigurations.keys {
                    cfg.displayConfigurations[key]?.assetPath = nil
                    cfg.displayConfigurations[key]?.photoPath = nil
                    cfg.displayConfigurations[key]?.shaderName = nil
                    cfg.displayConfigurations[key]?.shaderPath = nil
                    cfg.displayConfigurations[key]?.staticImagePath = nil
                    cfg.displayConfigurations[key]?.particleSceneName = nil
                    cfg.displayConfigurations[key]?.webPath = url.path
                }
            }
        }

        let targetIDs: [CGDirectDisplayID]
        if let id = displayID {
            targetIDs = [id]
        } else {
            targetIDs = Array(Set(windowManager.managedWindows.keys).union(activeDisplayIDs))
        }

        for id in targetIDs {
            if let window = attachedWindows[id] ?? windowManager.managedWindows[id] {
                attachWeb(to: window, displayID: id, htmlURL: url, allowNetwork: allowNetwork)
            }
        }
        reconcileAllScreens()
        refreshMenuBarDisplays()
    }

    public func setParticles(scene: ParticleSceneType, for displayID: CGDirectDisplayID? = nil) {
        updateConfig { cfg in
            if let id = displayID {
                let key = String(id)
                var disp = cfg.displayConfigurations[key] ?? DisplayConfig()
                disp.particleSceneName = scene.rawValue
                disp.staticImagePath = nil
                disp.webPath = nil
                disp.photoPath = nil
                disp.assetPath = nil
                disp.shaderName = nil
                disp.shaderPath = nil
                disp.isEnabled = true
                cfg.displayConfigurations[key] = disp
            } else {
                cfg.particleSceneName = scene.rawValue
                cfg.staticImagePath = nil
                cfg.webPath = nil
                cfg.photoPath = nil
                cfg.defaultAssetPath = nil
                cfg.shaderName = nil
                cfg.shaderPath = nil
                for key in cfg.displayConfigurations.keys {
                    cfg.displayConfigurations[key]?.assetPath = nil
                    cfg.displayConfigurations[key]?.photoPath = nil
                    cfg.displayConfigurations[key]?.shaderName = nil
                    cfg.displayConfigurations[key]?.shaderPath = nil
                    cfg.displayConfigurations[key]?.staticImagePath = nil
                    cfg.displayConfigurations[key]?.webPath = nil
                    cfg.displayConfigurations[key]?.particleSceneName = scene.rawValue
                }
            }
        }

        let targetIDs: [CGDirectDisplayID]
        if let id = displayID {
            targetIDs = [id]
        } else {
            targetIDs = Array(Set(windowManager.managedWindows.keys).union(activeDisplayIDs))
        }

        for id in targetIDs {
            if let window = attachedWindows[id] ?? windowManager.managedWindows[id] {
                attachParticles(to: window, displayID: id, sceneType: scene)
            }
        }
        reconcileAllScreens()
        refreshMenuBarDisplays()
    }

    public func updateSpannedGeometryIfNeeded() {
        guard config.isSpanned else { return }
        let screenFrames = windowManager.screenManager.activeScreens.reduce(into: [CGDirectDisplayID: CGRect]()) { dict, screen in
            dict[screen.displayID] = screen.frame
        }
        for (id, sView) in staticWallpaperViews {
            sView.scalingMode = .stretch
            sView.contentsRect = displaySpanManager.normalizedContentsRect(for: id, allScreens: screenFrames)
        }
    }

    public func setSpanned(_ spanned: Bool) {
        updateConfig { cfg in
            cfg.isSpanned = spanned
        }
        let screenFrames = windowManager.screenManager.activeScreens.reduce(into: [CGDirectDisplayID: CGRect]()) { dict, screen in
            dict[screen.displayID] = screen.frame
        }
        for (id, sView) in staticWallpaperViews {
            if spanned {
                sView.scalingMode = .stretch
                sView.contentsRect = displaySpanManager.normalizedContentsRect(for: id, allScreens: screenFrames)
            } else {
                sView.scalingMode = .aspectFill
                sView.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            }
        }
    }

    public func applyProfile(_ profile: EngineProfile) {
        updateConfig { cfg in
            self.profileManager.applyProfile(profile, to: &cfg)
        }
        performanceRulesManager.pauseOnFullscreen = profile.pauseOnFullscreen
        performanceRulesManager.pauseOnGame = profile.pauseOnGame
        reconcileAllScreens()
    }


    // MARK: - Configuration Mutations & Debounced Persistence

    public func updateConfig(_ update: (inout EngineConfig) -> Void) {
        update(&config)
        telemetryMonitor.isCPUOnlyMode = config.useCPUOnlyEngine
        appState?.config = config
        menuBarController?.updateConfig(config)
        themeManager.settings = config.hudConfig.themeSettings
        for (id, window) in attachedWindows {
            attachOrUpdateHUD(for: id, in: window)
        }
        reconcileAllScreens()
        scheduleConfigSave()
    }

    public func setCPUOnlyEngine(_ enabled: Bool) {
        updateConfig { cfg in
            cfg.useCPUOnlyEngine = enabled
        }
        telemetryMonitor.isCPUOnlyMode = enabled

        let targetIDs = Array(Set(windowManager.managedWindows.keys).union(activeDisplayIDs))
        for id in targetIDs {
            guard let window = attachedWindows[id] ?? windowManager.managedWindows[id] else { continue }
            if enabled {
                // Switch from GPU/Metal/Video to 100% CPU Live Wallpaper
                let preset: ProceduralShaderPreset
                if let shaderView = shaderViews[id], let current = shaderView.currentPreset {
                    preset = current
                } else if let sName = config.shaderName, let p = ProceduralShaderPreset(rawValue: sName) {
                    preset = p
                } else {
                    preset = .aurora
                }
                attachCPUShader(to: window, displayID: id, preset: preset)
            } else {
                // Switch back from CPU to Metal GPU acceleration
                if let cpuView = cpuWallpaperViews[id] {
                    attachShader(to: window, displayID: id, preset: cpuView.currentPreset)
                } else if let sName = config.shaderName, let preset = ProceduralShaderPreset(rawValue: sName) {
                    attachShader(to: window, displayID: id, preset: preset)
                }
            }
        }
        reconcileAllScreens()
        refreshMenuBarDisplays()
    }

    private func scheduleConfigSave() {
        configSaveTask?.cancel()
        configSaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
                guard !Task.isCancelled else { return }
                self?.flushConfigToDisk()
            } catch {
                // Task cancelled
            }
        }
    }

    public func flushConfigToDisk() {
        configSaveTask?.cancel()
        configSaveTask = nil
        do {
            try configStorage.save(config)
        } catch {
            logger.error("Failed to persist EngineConfig: \(error.localizedDescription)")
        }
    }

    // MARK: - Observer Delegate Callbacks

    public func powerStateDidChange(_ newState: PowerState) {
        self.currentPowerState = newState
        reconcileAllScreens()
    }

    public func sleepLockStateDidChange(_ newState: SleepLockState) {
        self.currentSleepLockState = newState
        reconcileAllScreens()
    }

    public func occlusionDidChange(for displayID: CGDirectDisplayID, isVisible: Bool) {
        occlusionManager.setDisplayVisibility(displayID, isVisible: isVisible)
        reconcileAllScreens()
    }

    // MARK: - VideoEngineDelegate

    public func videoEngine(_ engine: VideoEngineProtocol, didChangePlaybackState state: PlaybackState, for displayID: CGDirectDisplayID) {
        reconcileAllScreens()
    }

    public func videoEngine(_ engine: VideoEngineProtocol, didEncounterError error: VideoEngineError, for displayID: CGDirectDisplayID) {
        logger.error("VideoEngine encountered error on display \(displayID): \(error.localizedDescription)")
    }

    public func videoEngine(_ engine: VideoEngineProtocol, didRecoverFromStallOn displayID: CGDirectDisplayID) {
        logger.info("VideoEngine successfully recovered from stall on display \(displayID)")
    }

    // MARK: - DesktopWindowManagerDelegate

    public func desktopWindowManager(_ manager: DesktopWindowManagerProtocol, didAddWindow window: DesktopWindowProtocol, for displayID: CGDirectDisplayID) {
        attachDisplay(displayID: displayID, window: window)
        reconcileAllScreens()
        refreshMenuBarDisplays()
    }

    public func desktopWindowManager(_ manager: DesktopWindowManagerProtocol, didRemoveWindowFor displayID: CGDirectDisplayID) {
        cleanDisplayRenderers(displayID: displayID)
        if let hView = hudViews[displayID] {
            hView.removeFromSuperview()
            hudViews.removeValue(forKey: displayID)
        }
        activeDisplayIDs.remove(displayID)
        attachedWindows.removeValue(forKey: displayID)
        lastDecisions.removeValue(forKey: displayID)
        occlusionManager.unregisterDisplay(displayID)
        videoEngine.detach(displayID: displayID)
        reconcileAllScreens()
        refreshMenuBarDisplays()
    }

    public func desktopWindowManager(_ manager: DesktopWindowManagerProtocol, didUpdateWindow window: DesktopWindowProtocol, for displayID: CGDirectDisplayID) {
        if let hudView = hudViews[displayID] {
            let bounds = window.underlyingWindow.contentView?.bounds ?? window.frame
            hudView.updatePlacement(in: bounds)
        }
        reconcileAllScreens()
        refreshMenuBarDisplays()
    }

    public func desktopWindowManager(_ manager: DesktopWindowManagerProtocol, didReconcileWindows added: [CGDirectDisplayID], removed: [CGDirectDisplayID], updated: [CGDirectDisplayID]) {
        updateSpannedGeometryIfNeeded()
        reconcileAllScreens()
        refreshMenuBarDisplays()
    }

    public func displayConfigurationDidChange(added: [CGDirectDisplayID], removed: [CGDirectDisplayID], updated: [CGDirectDisplayID]) {
        updateSpannedGeometryIfNeeded()
        reconcileAllScreens()
        refreshMenuBarDisplays()
    }

    // MARK: - MenuBarControllerDelegate

    public func menuBarDidTogglePlayback(_ controller: MenuBarControllerProtocol) {
        togglePlayback()
    }

    public func menuBar(_ controller: MenuBarControllerProtocol, didSelectAssetURL url: URL, for displayID: CGDirectDisplayID?) {
        let ext = url.pathExtension.lowercased()
        let imageExtensions = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "webp"]
        let shaderExtensions = ["metal", "shadertoy", "frag", "glsl", "txt"]
        let webExtensions = ["html", "htm"]

        if shaderExtensions.contains(ext) {
            setShader(url: url, for: displayID)
            return
        }

        if webExtensions.contains(ext) {
            setWebWallpaper(url: url, for: displayID)
            return
        }

        Task { @MainActor [weak self] in
            if imageExtensions.contains(ext) {
                try? await self?.setStaticImage(url: url, for: displayID)
            } else {
                try? await self?.setVideo(url: url, for: displayID)
            }
        }
    }

    public func menuBar(_ controller: MenuBarControllerProtocol, didSelectShaderPreset preset: String, for displayID: CGDirectDisplayID?) {
        if let p = ProceduralShaderPreset(nameOrKey: preset) {
            setShader(preset: p, for: displayID)
        }
    }

    public func menuBar(_ controller: MenuBarControllerProtocol, didSelectShaderSpeed speed: Float) {
        updateConfig { cfg in
            cfg.shaderSpeed = speed
        }
        for view in shaderViews.values {
            view.speed = speed
        }
    }

    public func menuBar(_ controller: MenuBarControllerProtocol, didUpdateConfig newConfig: EngineConfig) {
        updateConfig { cfg in
            cfg = newConfig
        }
    }

    public func menuBar(_ controller: MenuBarControllerProtocol, didSelectTargetFrameRate fps: Int) {
        updateConfig { cfg in
            cfg.targetFrameRate = fps
        }
    }

    public func menuBar(_ controller: MenuBarControllerProtocol, didTogglePauseFor displayID: CGDirectDisplayID) {
        updateConfig { cfg in
            let key = String(displayID)
            var disp = cfg.displayConfigurations[key] ?? DisplayConfig()
            disp.isEnabled.toggle()
            cfg.displayConfigurations[key] = disp
        }
    }

    public func menuBar(_ controller: MenuBarControllerProtocol, didUpdateHUDConfig hudConfig: EngineConfig.HUDConfig) {
        updateConfig { cfg in
            cfg.hudConfig = hudConfig
        }
    }

    public func menuBar(_ controller: MenuBarControllerProtocol, didToggleAudioReactive enabled: Bool) {
        updateConfig { cfg in
            cfg.isAudioReactive = enabled
        }
    }

    public func menuBarDidRequestRevealWallpapers(_ controller: MenuBarControllerProtocol) {
        let appSupport = ConfigPersistenceManager.defaultConfigDirectoryURL
        let wallpapersDir = appSupport.appendingPathComponent("Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: wallpapersDir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([wallpapersDir])
    }

    public func menuBarDidRequestQuit(_ controller: MenuBarControllerProtocol) {
        stop()
        NSApp.terminate(nil)
    }

    // MARK: - MemoryPressureDelegate

    public func memoryPressureDidChange(to level: MemoryPressureLevel) {
        if level == .warning {
            StaticWallpaperCache.shared.trim(toRatio: 0.5)
            WallpaperThumbnailCache.shared.clearMemoryCache()
            MotionBGsThumbnailCache.shared.clearMemoryCache()
            appState?.purgeDiscoverMemory()
        } else if level == .critical {
            StaticWallpaperCache.shared.clear()
            WallpaperThumbnailCache.shared.clearMemoryCache()
            MotionBGsThumbnailCache.shared.clearMemoryCache()
            appState?.teardownDiscover()
        }
        reconcileAllScreens()
    }

    // MARK: - PerformanceRulesDelegate

    public func performanceRulesDidChange(fullscreenOnDisplays: Set<CGDirectDisplayID>, isGameActive: Bool, isIdle: Bool) {
        reconcileAllScreens()
    }

    // MARK: - WallpaperPlaylistDelegate

    public func playlistManager(_ manager: WallpaperPlaylistManager, didRequestSwitchTo item: PlaylistItem, for displayID: CGDirectDisplayID?) {
        let ext = item.url.pathExtension.lowercased()
        let imageExtensions = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "webp"]
        let webExtensions = ["html", "htm"]
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if imageExtensions.contains(ext) {
                try? await self.setStaticImage(url: item.url, for: displayID, scalingMode: .aspectFill)
            } else if webExtensions.contains(ext) {
                self.setWebWallpaper(url: item.url, for: displayID, allowNetwork: false)
            } else {
                try? await self.setVideo(url: item.url, for: displayID)
            }
        }
    }
}


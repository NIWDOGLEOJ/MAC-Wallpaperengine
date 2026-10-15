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
    var hudViews: [CGDirectDisplayID: DesktopHUDView] { get }
    var audioCapture: SystemAudioCapture { get }
    var nowPlayingMonitor: NowPlayingMonitor { get }
    var telemetryMonitor: SystemTelemetryMonitor { get }

    func start()
    func stop()
    func togglePlayback()
    func setVideo(url: URL, for displayID: CGDirectDisplayID?) async throws
    func setPhoto(url: URL, for displayID: CGDirectDisplayID?, useHeadTracking: Bool?) async throws
    func setShader(preset: ProceduralShaderPreset, for displayID: CGDirectDisplayID?, speed: Float?)
    func setShader(url: URL, for displayID: CGDirectDisplayID?, speed: Float?)
    func attachOrUpdateHUD(for displayID: CGDirectDisplayID, in window: DesktopWindowProtocol)
    func updateConfig(_ update: (inout EngineConfig) -> Void)
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
    MenuBarControllerDelegate
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
    public private(set) var hudViews: [CGDirectDisplayID: DesktopHUDView] = [:]
    public let audioCapture: SystemAudioCapture
    public let nowPlayingMonitor: NowPlayingMonitor
    public let telemetryMonitor: SystemTelemetryMonitor
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
        cliOptions: CommandLineOptions? = nil
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

        // Wire delegate relationships
        self.windowManager.delegate = self
        self.powerObserver.delegate = self
        self.sleepLockObserver.delegate = self
        self.occlusionManager.delegate = self
        self.videoEngine.delegate = self
        self.menuBarController?.delegate = self

        // Wire Audio & Telemetry Callbacks
        self.audioCapture.onSpectrumUpdate = { [weak self] spectrum in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                if self.config.isAudioReactive {
                    for sView in self.shaderViews.values {
                        sView.updateAudio(spectrum: spectrum)
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

        // 5. Start Power & Sleep/Lock Observers
        powerObserver.start()
        sleepLockObserver.start()
        self.currentPowerState = powerObserver.currentState
        self.currentSleepLockState = sleepLockObserver.currentState

        // 6. Start Audio Capture, Media & Telemetry Monitors
        audioCapture.start()
        nowPlayingMonitor.start()
        telemetryMonitor.start()

        // 7. Perform initial state reconciliation & populate Menu Bar displays
        reconcileAllScreens()
        refreshMenuBarDisplays()
        logger.info("AppCoordinator started successfully with \(self.windowManager.managedWindows.count) displays.")
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        logger.info("Stopping AppCoordinator...")

        // 1. Halt observers to prevent callbacks during teardown
        powerObserver.stop()
        sleepLockObserver.stop()

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

        // 1. Resolve procedural or imported shader
        let dispConfig = config.displayConfigurations[String(displayID)]
        let shaderName = dispConfig?.shaderName ?? config.shaderName
        let shaderPath = dispConfig?.shaderPath ?? config.shaderPath

        if let sName = shaderName, let preset = ProceduralShaderPreset(rawValue: sName) {
            attachShader(to: window, displayID: displayID, preset: preset)
            attachOrUpdateHUD(for: displayID, in: window)
            return
        } else if let sPath = shaderPath, FileManager.default.fileExists(atPath: sPath) {
            let sURL = URL(fileURLWithPath: sPath)
            attachShader(to: window, displayID: displayID, fileURL: sURL)
            attachOrUpdateHUD(for: displayID, in: window)
            return
        }

        // 2. Resolve assigned photo path for 3D parallax scene
        let photoPath = dispConfig?.photoPath ?? config.photoPath
        if let pPath = photoPath, FileManager.default.fileExists(atPath: pPath) {
            let pURL = URL(fileURLWithPath: pPath)
            attachParallax(to: window, displayID: displayID, photoURL: pURL)
            attachOrUpdateHUD(for: displayID, in: window)
            return
        }

        if let player = videoEngine.player(for: displayID) {
            window.attachPlayerLayer(player.playerLayer)
        }

        // 3. Resolve assigned video path
        let assetPath = dispConfig?.assetPath ?? config.defaultAssetPath
        if let path = assetPath, FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            Task { @MainActor [weak self] in
                try? await self?.videoEngine.setVideo(url: url, for: displayID)
            }
        }

        // 4. Attach or update Desktop HUD overlay
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
    }

    private func attachShader(to window: DesktopWindowProtocol, displayID: CGDirectDisplayID, preset: ProceduralShaderPreset) {
        window.removePlayerLayer()
        parallaxViews[displayID]?.pause()
        parallaxViews[displayID]?.removeFromSuperview()
        parallaxViews.removeValue(forKey: displayID)

        shaderViews[displayID]?.pause()
        shaderViews[displayID]?.removeFromSuperview()

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
    }

    private func attachShader(to window: DesktopWindowProtocol, displayID: CGDirectDisplayID, fileURL: URL) {
        window.removePlayerLayer()
        parallaxViews[displayID]?.pause()
        parallaxViews[displayID]?.removeFromSuperview()
        parallaxViews.removeValue(forKey: displayID)

        shaderViews[displayID]?.pause()
        shaderViews[displayID]?.removeFromSuperview()

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
    }

    private func attachParallax(to window: DesktopWindowProtocol, displayID: CGDirectDisplayID, photoURL: URL) {
        window.removePlayerLayer()
        shaderViews[displayID]?.pause()
        shaderViews[displayID]?.removeFromSuperview()
        shaderViews.removeValue(forKey: displayID)

        parallaxViews[displayID]?.removeFromSuperview()

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

        Task { @MainActor [weak self] in
            do {
                try await parallaxView.loadPhoto(from: photoURL)
                self?.logger.info("3D Parallax scene attached to display \(displayID) for \(photoURL.lastPathComponent)")
            } catch {
                self?.logger.error("Failed to load 3D Parallax scene for display \(displayID): \(error.localizedDescription)")
            }
        }
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
            config: config
        )

        for (displayID, decision) in decisions {
            if lastDecisions[displayID] != decision {
                lastDecisions[displayID] = decision
                apply(decision: decision, to: displayID)
            }
        }

        updateMenuBarStatus(with: decisions)
    }

    private func apply(decision: PlaybackDecision, to displayID: CGDirectDisplayID) {
        switch decision {
        case .play(let fps):
            telemetryMonitor.currentFPS = fps
            videoEngine.setPlaybackState(.playing, for: displayID)
            if let pView = parallaxViews[displayID] {
                pView.resume()
                pView.setTargetFrameRate(fps)
            }
            if let sView = shaderViews[displayID] {
                sView.resume()
                sView.setTargetFrameRate(fps)
            }
        case .pause(let reasons):
            telemetryMonitor.currentFPS = 0
            let primaryReason = reasons.sorted(by: { $0.rawValue < $1.rawValue }).first ?? .userRequested
            videoEngine.setPlaybackState(.paused(reason: primaryReason), for: displayID)
            parallaxViews[displayID]?.pause()
            shaderViews[displayID]?.pause()
        case .throttle(let fps, _):
            telemetryMonitor.currentFPS = fps
            videoEngine.setPlaybackState(.throttled(fps: fps), for: displayID)
            if let pView = parallaxViews[displayID] {
                pView.resume()
                pView.setTargetFrameRate(fps)
            }
            if let sView = shaderViews[displayID] {
                sView.resume()
                sView.setTargetFrameRate(fps)
            }
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

    public func setVideo(url: URL, for displayID: CGDirectDisplayID?) async throws {
        try await videoEngine.setVideo(url: url, for: displayID)

        updateConfig { cfg in
            if let id = displayID {
                let key = String(id)
                var disp = cfg.displayConfigurations[key] ?? DisplayConfig()
                disp.assetPath = url.path
                disp.photoPath = nil
                disp.isEnabled = true
                cfg.displayConfigurations[key] = disp
            } else {
                cfg.defaultAssetPath = url.path
                cfg.photoPath = nil
            }
        }
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
                disp.isEnabled = true
                cfg.displayConfigurations[key] = disp
            } else {
                cfg.photoPath = url.path
            }
        }

        if let id = displayID, let window = attachedWindows[id] {
            attachParallax(to: window, displayID: id, photoURL: url)
        } else {
            for (id, window) in attachedWindows {
                attachParallax(to: window, displayID: id, photoURL: url)
            }
        }
        refreshMenuBarDisplays()
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
                disp.isEnabled = true
                cfg.displayConfigurations[key] = disp
            } else {
                cfg.shaderName = preset.rawValue
                cfg.shaderPath = nil
                cfg.photoPath = nil
            }
        }

        if let id = displayID, let window = attachedWindows[id] {
            attachShader(to: window, displayID: id, preset: preset)
        } else {
            for (id, window) in attachedWindows {
                attachShader(to: window, displayID: id, preset: preset)
            }
        }
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
                disp.isEnabled = true
                cfg.displayConfigurations[key] = disp
            } else {
                cfg.shaderPath = url.path
                cfg.shaderName = nil
                cfg.photoPath = nil
            }
        }

        if let id = displayID, let window = attachedWindows[id] {
            attachShader(to: window, displayID: id, fileURL: url)
        } else {
            for (id, window) in attachedWindows {
                attachShader(to: window, displayID: id, fileURL: url)
            }
        }
        refreshMenuBarDisplays()
    }

    // MARK: - Configuration Mutations & Debounced Persistence

    public func updateConfig(_ update: (inout EngineConfig) -> Void) {
        update(&config)
        menuBarController?.updateConfig(config)
        for (id, window) in attachedWindows {
            attachOrUpdateHUD(for: id, in: window)
        }
        reconcileAllScreens()
        scheduleConfigSave()
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
        if let sView = shaderViews[displayID] {
            sView.pause()
            sView.removeFromSuperview()
            shaderViews.removeValue(forKey: displayID)
        }
        if let pView = parallaxViews[displayID] {
            pView.pause()
            pView.removeFromSuperview()
            parallaxViews.removeValue(forKey: displayID)
        }
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
        refreshMenuBarDisplays()
    }

    public func displayConfigurationDidChange(added: [CGDirectDisplayID], removed: [CGDirectDisplayID], updated: [CGDirectDisplayID]) {
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

        if shaderExtensions.contains(ext) {
            setShader(url: url, for: displayID)
            return
        }

        Task { @MainActor [weak self] in
            if imageExtensions.contains(ext) {
                try? await self?.setPhoto(url: url, for: displayID)
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
}

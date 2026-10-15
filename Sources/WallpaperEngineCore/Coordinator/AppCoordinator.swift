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

    func start()
    func stop()
    func togglePlayback()
    func setVideo(url: URL, for displayID: CGDirectDisplayID?) async throws
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

        // 6. Perform initial state reconciliation & populate Menu Bar displays
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

        // 2. Flush pending config persistence synchronously
        flushConfigToDisk()

        // 3. Tear down Menu Bar UI
        menuBarController?.stop()

        // 4. Tear down video players and windows
        videoEngine.stop()
        windowManager.stop()

        // 5. Reset cached decisions
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

        if let player = videoEngine.player(for: displayID) {
            window.attachPlayerLayer(player.playerLayer)
        }

        // Resolve assigned video path
        let assetPath = config.displayConfigurations[String(displayID)]?.assetPath ?? config.defaultAssetPath
        if let path = assetPath, FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            Task { @MainActor [weak self] in
                try? await self?.videoEngine.setVideo(url: url, for: displayID)
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
            _ = fps
            videoEngine.setPlaybackState(.playing, for: displayID)
        case .pause(let reasons):
            let primaryReason = reasons.sorted(by: { $0.rawValue < $1.rawValue }).first ?? .userRequested
            videoEngine.setPlaybackState(.paused(reason: primaryReason), for: displayID)
        case .throttle(let fps, _):
            videoEngine.setPlaybackState(.throttled(fps: fps), for: displayID)
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
                disp.isEnabled = true
                cfg.displayConfigurations[key] = disp
            } else {
                cfg.defaultAssetPath = url.path
            }
        }
        refreshMenuBarDisplays()
    }

    // MARK: - Configuration Mutations & Debounced Persistence

    public func updateConfig(_ update: (inout EngineConfig) -> Void) {
        update(&config)
        menuBarController?.updateConfig(config)
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
        activeDisplayIDs.remove(displayID)
        attachedWindows.removeValue(forKey: displayID)
        lastDecisions.removeValue(forKey: displayID)
        occlusionManager.unregisterDisplay(displayID)
        videoEngine.detach(displayID: displayID)
        reconcileAllScreens()
        refreshMenuBarDisplays()
    }

    public func desktopWindowManager(_ manager: DesktopWindowManagerProtocol, didUpdateWindow window: DesktopWindowProtocol, for displayID: CGDirectDisplayID) {
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
        Task { @MainActor [weak self] in
            try? await self?.setVideo(url: url, for: displayID)
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

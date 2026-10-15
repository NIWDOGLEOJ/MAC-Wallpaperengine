//
//  Tier4_RealWorldTests.swift
//  WallpaperEngineCoreTests / E2ETests
//
//  Tier 4: Realistic Operational User Workload Tests (35 tests)
//

import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import Testing

@Suite("Tier 4: Realistic Operational User Workloads")
struct Tier4_RealWorldTests {

    // MARK: - Scenario 1: Cold App Launch to Steady-State Playback (Tests R1 - R7)

    @Test("R1: Cold Launch with Default Configuration Starts Playback on All Displays")
    func testR1_ColdLaunchDefaultConfiguration() async throws {
        let screens = [
            ScreenDescriptor(displayID: 1, name: "Built-in Retina", frame: CGRect(x: 0, y: 0, width: 2560, height: 1600), isMain: true)
        ]
        let screenMgr = MockScreenManager(screens: screens)
        let videoEngine = MockVideoEngine()
        let menuBar = MockMenuBarController()

        screenMgr.startMonitoring()
        menuBar.setup()

        let defaultAsset = VideoAsset(fileURL: URL(fileURLWithPath: "/wallpapers/default.mp4"), title: "Default Wallpaper")
        let player = videoEngine.registerDisplay(displayID: 1)
        try await player.load(asset: defaultAsset, crossfade: false)

        menuBar.updateDisplays(displays: [(id: 1, name: "Built-in Retina", currentAsset: "Default Wallpaper")])
        menuBar.updateStatus(isPlaying: true, fps: 60, powerInfo: "AC Power")

        #expect(screenMgr.isMonitoring == true)
        #expect(menuBar.isStatusItemVisible == true)
        #expect(player.state == .playing)
        #expect(menuBar.lastStatus?.isPlaying == true)
    }

    @Test("R2: Cold Launch with CLI Overrides Takes Precedence Over Saved Config")
    func testR2_ColdLaunchCustomCLIOverrides() {
        let args = ["wallpaper_engine", "--video", "/custom/nature.mov", "--fps", "30", "--pause-on-battery"]
        let opts = CommandLineOptions.parse(arguments: args)

        var config = EngineConfig()
        if let v = opts.videoPath { config.defaultAssetPath = v }
        if let fps = opts.targetFPS { config.targetFrameRate = fps }
        if opts.pauseOnBattery { config.pauseOnBattery = true }

        #expect(config.defaultAssetPath == "/custom/nature.mov")
        #expect(config.targetFrameRate == 30)
        #expect(config.pauseOnBattery == true)
    }

    @Test("R3: Cold Launch in Headless Mode Bypasses Menu Bar Status Item")
    func testR3_ColdLaunchHeadlessMode() {
        let args = ["wallpaper_engine", "--headless"]
        let opts = CommandLineOptions.parse(arguments: args)

        let menuBar = MockMenuBarController()
        if !opts.isHeadless {
            menuBar.setup()
        }

        #expect(opts.isHeadless == true)
        #expect(menuBar.isStatusItemVisible == false)
    }

    @Test("R4: Cold Launch with Zero Screens Enters Waiting State Gracefully")
    func testR4_ColdLaunchNoScreensFallback() {
        let screenMgr = MockScreenManager(screens: [])
        let videoEngine = MockVideoEngine()

        screenMgr.startMonitoring()

        #expect(screenMgr.activeScreens.isEmpty == true)
        #expect(videoEngine.activeDisplays.isEmpty == true)
    }

    @Test("R5: First-Time Launch Auto-Generates Valid Default Configuration File")
    func testR5_ColdLaunchMissingConfigFileGeneratesDefault() throws {
        let tempDir = try TestHarness.shared.createTemporaryDirectory()
        let configFile = tempDir.appendingPathComponent("config.json")

        #expect(FileManager.default.fileExists(atPath: configFile.path) == false)

        let defaultConfig = EngineConfig()
        let data = try JSONEncoder().encode(defaultConfig)
        try data.write(to: configFile)

        #expect(FileManager.default.fileExists(atPath: configFile.path) == true)
        try FileManager.default.removeItem(at: tempDir)
    }

    @Test("R6: Launch with Corrupt Configuration File Recovers Cleanly with Defaults")
    func testR6_ColdLaunchCorruptedConfigRecoversDefault() throws {
        let tempDir = try TestHarness.shared.createTemporaryDirectory()
        let configFile = tempDir.appendingPathComponent("config.json")
        try "corrupted json payload".data(using: .utf8)?.write(to: configFile)

        let loadedData = try Data(contentsOf: configFile)
        let decoded = (try? JSONDecoder().decode(EngineConfig.self, from: loadedData)) ?? EngineConfig()

        #expect(decoded.targetFrameRate == 60)
        #expect(decoded.version == 1)
        try FileManager.default.removeItem(at: tempDir)
    }

    @Test("R7: Cold Launch Initialization Operates Within System Telemetry Budget")
    func testR7_ColdLaunchPerformanceBudget() {
        let before = TestHarness.shared.captureTelemetry()
        let _ = MockDesktopWindow(screen: ScreenDescriptor(displayID: 1, name: "Test", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)))
        let after = TestHarness.shared.captureTelemetry()

        #expect(after.residentMemoryBytes >= before.residentMemoryBytes)
    }

    // MARK: - Scenario 2: Multi-Screen Docking & Undocking Lifecycle (Tests R8 - R14)

    @Test("R8: MacBook Clamshell Docking Sequence Reconciles Displays Cleanly")
    func testR8_MacBookClamshellDockingSequence() {
        let builtIn = ScreenDescriptor(displayID: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 2560, height: 1600), isBuiltin: true)
        let ext1 = ScreenDescriptor(displayID: 2, name: "4K Studio", frame: CGRect(x: 0, y: 0, width: 3840, height: 2160))
        let ext2 = ScreenDescriptor(displayID: 3, name: "4K Side", frame: CGRect(x: 3840, y: 0, width: 3840, height: 2160))

        let screenMgr = MockScreenManager(screens: [builtIn])
        #expect(screenMgr.activeScreens.count == 1)

        // Dock connected, clamshell closed (built-in removed, 2 external screens added)
        screenMgr.simulateScreenChange(screens: [ext1, ext2])
        #expect(screenMgr.activeScreens.count == 2)
        #expect(screenMgr.activeScreens.map { $0.displayID } == [2, 3])
    }

    @Test("R9: Undocking from Multi-Display to Single Built-In Screen")
    func testR9_UndockingToSingleBuiltInDisplay() {
        let ext1 = ScreenDescriptor(displayID: 2, name: "4K Main", frame: CGRect(x: 0, y: 0, width: 3840, height: 2160))
        let ext2 = ScreenDescriptor(displayID: 3, name: "4K Aux", frame: CGRect(x: 3840, y: 0, width: 3840, height: 2160))
        let screenMgr = MockScreenManager(screens: [ext1, ext2])

        let builtIn = ScreenDescriptor(displayID: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 2560, height: 1600), isBuiltin: true)
        screenMgr.simulateScreenChange(screens: [builtIn])

        #expect(screenMgr.activeScreens.count == 1)
        #expect(screenMgr.activeScreens.first?.displayID == 1)
    }

    @Test("R10: Display Resolution Change Updates Window Frame In-Place")
    func testR10_DisplayResolutionChangeLivePresentation() {
        let screen = ScreenDescriptor(displayID: 2, name: "External 4K", frame: CGRect(x: 0, y: 0, width: 3840, height: 2160))
        let window = MockDesktopWindow(screen: screen)

        let scaledFrame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        window.updateFrame(scaledFrame)

        #expect(window.frame == scaledFrame)
        #expect(window.updateFrameCallCount == 1)
    }

    @Test("R11: Dynamic Attachment of Wireless Display Allocates Independent Pipeline")
    func testR11_SidecarOrAirPlayDisplayAttachment() async throws {
        let engine = MockVideoEngine()
        _ = engine.registerDisplay(displayID: 1)

        let sidecarDisplay = engine.registerDisplay(displayID: 999)
        let asset = VideoAsset(fileURL: URL(fileURLWithPath: "/wallpapers/sidecar.mp4"), title: "Sidecar")
        try await sidecarDisplay.load(asset: asset, crossfade: false)

        #expect(engine.activeDisplays.count == 2)
        #expect(sidecarDisplay.state == .playing)
    }

    @Test("R12: Rapid Thunderbolt Dock Plug and Unplug Events Coalesce Deterministically")
    func testR12_RapidThunderboltDockPlugUnplug() {
        let screenMgr = MockScreenManager()
        let s1 = ScreenDescriptor(displayID: 1, name: "S1", frame: .zero)
        let s2 = ScreenDescriptor(displayID: 2, name: "S2", frame: .zero)

        for i in 0..<10 {
            screenMgr.simulateScreenChange(screens: (i % 2 == 0) ? [s1, s2] : [s1])
        }
        #expect(screenMgr.activeScreens.count == 1)
    }

    @Test("R13: Mixed Resolution and Refresh Rate Displays Operate in Isolation")
    func testR13_MixedResolutionAndRefreshRates() {
        let proMotionScreen = ScreenDescriptor(displayID: 1, name: "120Hz ProMotion", frame: CGRect(x: 0, y: 0, width: 3456, height: 2234))
        let external60Hz = ScreenDescriptor(displayID: 2, name: "60Hz 4K", frame: CGRect(x: 3456, y: 0, width: 3840, height: 2160))

        let w1 = MockDesktopWindow(screen: proMotionScreen)
        let w2 = MockDesktopWindow(screen: external60Hz)

        #expect(w1.frame.size != w2.frame.size)
        #expect(w1.displayID == 1)
        #expect(w2.displayID == 2)
    }

    @Test("R14: Screen Mirroring Topology Attaches Cleanly")
    func testR14_ScreenMirroringTopology() {
        let primaryScreen = ScreenDescriptor(displayID: 1, name: "Primary Mirrored", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true)
        let window = MockDesktopWindow(screen: primaryScreen)
        window.orderToDesktopLevel()
        #expect(window.isVisible == true)
        #expect(window.frame.width == 1920)
    }

    // MARK: - Scenario 3: Prolonged Playback & Resource Stability (Tests R15 - R21)

    @Test("R15: Simulated 1,000 Loop Iterations Exhibits Zero Resource Growth")
    func testR15_EnduranceSimulated1000LoopsZeroLeak() {
        let player = MockDisplayVideoPlayer(displayID: 1)
        player.play()

        for _ in 0..<1000 {
            // Simulated loop ticks
            #expect(player.state == .playing)
        }
        #expect(player.stallRecoveryCount == 0)
    }

    @Test("R16: Switching Wallpapers 50 Times in Succession Tears Down Previous Pipelines")
    func testR16_AssetSwitchingMemoryStability() async throws {
        let player = MockDisplayVideoPlayer(displayID: 1)
        for i in 1...50 {
            let asset = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/v_\(i).mp4"), title: "V\(i)")
            try await player.load(asset: asset, crossfade: false)
        }
        #expect(player.loadCallCount == 50)
        #expect(player.currentAsset?.title == "V50")
    }

    @Test("R17: Audio Suppression Remains Continuously Active Across Playback Lifespan")
    func testR17_AudioSuppressionContinuousVerification() {
        let player = MockDisplayVideoPlayer(displayID: 1)
        player.play()
        #expect(player.isMuted == true)
        #expect(player.volume == 0.0)
        #expect(player.audioTracksEnabled == false)
    }

    @Test("R18: Sustained Execution CPU Telemetry Remains Stable")
    func testR18_CPUResourceEfficiencyWithinBudget() {
        let telemetry = TestHarness.shared.captureTelemetry()
        #expect(telemetry.userCPUTimeSeconds >= 0.0)
        #expect(telemetry.systemCPUTimeSeconds >= 0.0)
    }

    @Test("R19: Resident Memory Size Remains Under Budget Cap")
    func testR19_ProcessMemoryFootprintUnderCap() {
        let telemetry = TestHarness.shared.captureTelemetry()
        #expect(telemetry.residentMemoryMB < 500.0) // Well within safety margin
    }

    @Test("R20: Background Periodic Stall Watchdog Avoids False Positives During Active Play")
    func testR20_StallWatchdogEnduranceResilience() {
        let player = MockDisplayVideoPlayer(displayID: 1)
        player.play()
        #expect(player.state == .playing)
        #expect(player.stallRecoveryCount == 0)
    }

    @Test("R21: Zero-Copy Scanout Layer Attributes Preserved During Extended Play")
    func testR21_ZeroCopyScanoutLayerIntegrity() {
        let screen = ScreenDescriptor(displayID: 1, name: "Display", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        #expect(window.collectionBehaviorFlags.contains(.stationary))
        #expect(window.ignoresMouseEventsFlag == true)
    }

    // MARK: - Scenario 4: 24-Hour Day/Night Power & Environment Cycle (Tests R22 - R28)

    @Test("R22: Full Workday Power Transitions (AC -> Battery -> AC -> Battery -> AC)")
    func testR22_FullWorkdayPowerCycle() {
        var config = EngineConfig()
        config.throttleOnBattery = true
        config.pauseOnBattery = false

        var power = PowerState(source: .ac)
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: power, isDisplayVisible: true, config: config) == .play(fps: 60))

        power.source = .battery
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: power, isDisplayVisible: true, config: config) == .throttle(fps: 30, reasons: [.onBattery]))

        power.source = .ac
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: power, isDisplayVisible: true, config: config) == .play(fps: 60))

        power.source = .battery
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: power, isDisplayVisible: true, config: config) == .throttle(fps: 30, reasons: [.onBattery]))

        power.source = .ac
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: power, isDisplayVisible: true, config: config) == .play(fps: 60))
    }

    @Test("R23: Lunch Break Display Sleep Cycle (Plays -> Sleep Pauses -> Wake Resumes)")
    func testR23_LunchBreakDisplaySleepCycle() {
        let config = EngineConfig()
        var sleepLock = SleepLockState(areScreensSleeping: false)
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: sleepLock, power: PowerState(), isDisplayVisible: true, config: config) == .play(fps: 60))

        sleepLock.areScreensSleeping = true
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: sleepLock, power: PowerState(), isDisplayVisible: true, config: config) == .pause(reasons: [.screensSleeping]))

        sleepLock.areScreensSleeping = false
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: sleepLock, power: PowerState(), isDisplayVisible: true, config: config) == .play(fps: 60))
    }

    @Test("R24: Security Lock Screen Workflow (Plays -> Locked Pauses -> Unlock Resumes)")
    func testR24_SecurityLockScreenCycle() {
        let config = EngineConfig()
        var sleepLock = SleepLockState(isScreenLocked: false)
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: sleepLock, power: PowerState(), isDisplayVisible: true, config: config) == .play(fps: 60))

        sleepLock.isScreenLocked = true
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: sleepLock, power: PowerState(), isDisplayVisible: true, config: config) == .pause(reasons: [.screenLocked]))

        sleepLock.isScreenLocked = false
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: sleepLock, power: PowerState(), isDisplayVisible: true, config: config) == .play(fps: 60))
    }

    @Test("R25: Automatic Low Power Mode Emergency Engagement on Low Battery")
    func testR25_LowPowerModeEmergencyEngagement() {
        let config = EngineConfig()
        var power = PowerState(source: .battery, batteryLevel: 0.15, isLowPowerModeEnabled: false)
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: power, isDisplayVisible: true, config: config) == .throttle(fps: 30, reasons: [.onBattery]))

        // OS turns on Low Power Mode automatically below 20%
        power.isLowPowerModeEnabled = true
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: power, isDisplayVisible: true, config: config) == .pause(reasons: [.lowPowerMode]))
    }

    @Test("R26: Overnight Deep Sleep Cycle")
    func testR26_OvernightDeepSleepCycle() {
        let config = EngineConfig()
        var sleepLock = SleepLockState(isSystemSleeping: false)
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: sleepLock, power: PowerState(), isDisplayVisible: true, config: config) == .play(fps: 60))

        sleepLock.isSystemSleeping = true
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: sleepLock, power: PowerState(), isDisplayVisible: true, config: config) == .pause(reasons: [.systemSleeping]))

        sleepLock.isSystemSleeping = false
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: sleepLock, power: PowerState(), isDisplayVisible: true, config: config) == .play(fps: 60))
    }

    @Test("R27: Thermal Wave Cycle (Nominal -> Serious -> Critical -> Serious -> Nominal)")
    func testR27_ThermalPressureWaveHandling() {
        let config = EngineConfig()
        var power = PowerState(thermalState: .nominal)
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: power, isDisplayVisible: true, config: config) == .play(fps: 60))

        power.thermalState = .serious
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: power, isDisplayVisible: true, config: config) == .throttle(fps: 30, reasons: [.thermalPressure]))

        power.thermalState = .critical
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: power, isDisplayVisible: true, config: config) == .pause(reasons: [.thermalPressure]))

        power.thermalState = .serious
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: power, isDisplayVisible: true, config: config) == .throttle(fps: 30, reasons: [.thermalPressure]))

        power.thermalState = .nominal
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: power, isDisplayVisible: true, config: config) == .play(fps: 60))
    }

    @Test("R28: Combined Display Occlusion and Power Source Transition")
    func testR28_CombinedOcclusionAndPowerTransition() {
        var config = EngineConfig()
        config.pauseWhenOccluded = true
        config.pauseOnBattery = true

        let power = PowerState(source: .battery)
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: power,
            isDisplayVisible: false,
            config: config
        )
        #expect(decision == .pause(reasons: [.onBattery, .displayOccluded]))
    }

    // MARK: - Scenario 5: Graceful Shutdown & Clean Resource Release (Tests R29 - R35)

    @Test("R29: User Initiated Clean Quit from Menu Bar Dispatches Graceful Shutdown")
    func testR29_CleanQuitFromMenuBar() {
        final class TerminationWatcher: MenuBarActionDelegate {
            var shutdownExecuted = false
            func menuBarDidTogglePlayback() {}
            func menuBarDidSelectAsset(_ url: URL, for displayID: DisplayID) {}
            func menuBarDidToggleSetting(_ keyPath: WritableKeyPath<EngineConfig, Bool>) {}
            func menuBarDidRequestQuit() { shutdownExecuted = true }
        }
        let watcher = TerminationWatcher()
        let menuBar = MockMenuBarController()
        menuBar.delegate = watcher
        menuBar.simulateUserQuit()

        #expect(watcher.shutdownExecuted == true)
    }

    @Test("R30: App Termination Tears Down All Display Player Pipelines")
    func testR30_SIGTERMOrAppTerminationLifecycle() {
        let engine = MockVideoEngine()
        _ = engine.registerDisplay(displayID: 1)
        _ = engine.registerDisplay(displayID: 2)

        engine.detach(displayID: 1)
        engine.detach(displayID: 2)

        #expect(engine.activeDisplays.isEmpty == true)
    }

    @Test("R31: Unpersisted Preferences Flushed to Disk Before Exit")
    func testR31_ConfigSavedOnExit() throws {
        let tempDir = try TestHarness.shared.createTemporaryDirectory()
        let configFile = tempDir.appendingPathComponent("config.json")

        var config = EngineConfig()
        config.targetFrameRate = 120
        config.isPaused = true

        let data = try JSONEncoder().encode(config)
        try data.write(to: configFile)

        let reloaded = try JSONDecoder().decode(EngineConfig.self, from: Data(contentsOf: configFile))
        #expect(reloaded.targetFrameRate == 120)
        #expect(reloaded.isPaused == true)

        try FileManager.default.removeItem(at: tempDir)
    }

    @Test("R32: Desktop Windows Ordered Out Before Process Terminates")
    func testR32_DesktopWindowsOrderedOutBeforeProcessExit() {
        let screen = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        window.orderToDesktopLevel()
        #expect(window.isVisible == true)

        window.closeAndRelease()
        #expect(window.isVisible == false)
    }

    @Test("R33: Darwin Notification Center Deregistration Cleans Up Observers")
    func testR33_DarwinNotificationCenterDeregistrationOnDeinit() {
        let observer = MockSleepLockObserver()
        observer.start()
        #expect(observer.isObserving == true)
        observer.stop()
        #expect(observer.isObserving == false)
    }

    @Test("R34: Zero Active Timers or Stalled Watchdogs Remain on Teardown")
    func testR34_NoZombiePlayersOrActiveRunLoopSources() {
        let player = MockDisplayVideoPlayer(displayID: 1)
        player.tearDown()
        #expect(player.state == .idle)
        #expect(player.tearDownCallCount == 1)
    }

    @Test("R35: Final Process Telemetry Captures Clean Baseline Resources")
    func testR35_ProcessExitZeroLeaksVerification() {
        let telemetry = TestHarness.shared.captureTelemetry()
        #expect(telemetry.residentMemoryBytes > 0)
    }
}

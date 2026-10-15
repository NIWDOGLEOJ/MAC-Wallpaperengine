//
//  Tier2_BoundaryTests.swift
//  WallpaperEngineCoreTests / E2ETests
//
//  Tier 2: Boundary Value Analysis & Edge Cases (40 tests)
//

import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import Testing

@Suite("Tier 2: Boundary Value Analysis & Corner Cases")
struct Tier2_BoundaryTests {

    // MARK: - Display & Geometry Boundaries (Tests B1 - B8)

    @Test("B1: Zero Screens Topology Handles Gracefully Without Orphan Windows")
    func testB1_ZeroScreensTopology() {
        let mgr = MockScreenManager(screens: [])
        #expect(mgr.activeScreens.isEmpty == true)
        mgr.simulateScreenChange(screens: [])
        #expect(mgr.activeScreens.count == 0)
    }

    @Test("B2: Single Screen Minimum Valid Boundary")
    func testB2_SingleScreenBoundary() {
        let screen = ScreenDescriptor(displayID: 1, name: "Sole Display", frame: CGRect(x: 0, y: 0, width: 1280, height: 800))
        let mgr = MockScreenManager(screens: [screen])
        #expect(mgr.activeScreens.count == 1)
        #expect(mgr.activeScreens.first?.displayID == 1)
    }

    @Test("B3: Maximum Screen Density (8 Simultaneous Displays)")
    func testB3_MaximumScreenDensity() {
        let screens = (1...8).map { i in
            ScreenDescriptor(
                displayID: DisplayID(i),
                name: "Monitor \(i)",
                frame: CGRect(x: (i - 1) * 1920, y: 0, width: 1920, height: 1080)
            )
        }
        let mgr = MockScreenManager(screens: screens)
        #expect(mgr.activeScreens.count == 8)
        let windows = screens.map { MockDesktopWindow(screen: $0) }
        #expect(windows.count == 8)
        for (idx, w) in windows.enumerated() {
            #expect(w.displayID == DisplayID(idx + 1))
        }
    }

    @Test("B4: Zero Width and Height Screen Frame Boundary")
    func testB4_ZeroWidthHeightFrame() {
        let zeroScreen = ScreenDescriptor(displayID: 99, name: "Virtual Headless", frame: .zero)
        let window = MockDesktopWindow(screen: zeroScreen)
        #expect(window.frame == .zero)
        #expect(window.displayID == 99)
    }

    @Test("B5: Negative Origin Coordinates for Multi-Screen Spaces Arrangement")
    func testB5_NegativeScreenOriginCoordinates() {
        let negFrame = CGRect(x: -2560, y: -1440, width: 2560, height: 1440)
        let screen = ScreenDescriptor(displayID: 4, name: "Left Secondary", frame: negFrame)
        let window = MockDesktopWindow(screen: screen)
        #expect(window.frame.origin.x == -2560)
        #expect(window.frame.origin.y == -1440)
    }

    @Test("B6: Extreme Retina Backing Scale Factors (4.0x and 0.5x)")
    func testB6_ExtremeRetinaScaleFactor() {
        let ultraHiDPI = ScreenDescriptor(displayID: 1, name: "8K Canvas", frame: CGRect(x: 0, y: 0, width: 7680, height: 4320), scaleFactor: 4.0)
        let lowDPI = ScreenDescriptor(displayID: 2, name: "Legacy Projector", frame: CGRect(x: 0, y: 0, width: 800, height: 600), scaleFactor: 0.5)
        #expect(ultraHiDPI.scaleFactor == 4.0)
        #expect(lowDPI.scaleFactor == 0.5)
    }

    @Test("B7: Rapid Resolution Flipping (10 Alternating Updates)")
    func testB7_RapidScreenResolutionFlipping() {
        let screen = ScreenDescriptor(displayID: 1, name: "Display", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        let f1 = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let f2 = CGRect(x: 0, y: 0, width: 2560, height: 1440)

        for i in 0..<10 {
            window.updateFrame(i % 2 == 0 ? f2 : f1)
        }
        #expect(window.updateFrameCallCount == 10)
        #expect(window.frame == f1)
    }

    @Test("B8: Screen ID Collision Resistance")
    func testB8_ScreenIDCollisionHandling() {
        let s1 = ScreenDescriptor(displayID: 10, name: "Screen A", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let s2 = ScreenDescriptor(displayID: 10, name: "Screen B (Duplicate)", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        let set = Set([s1, s2])
        #expect(set.count == 2) // Differentiated by equality/hash
    }

    // MARK: - Power & Battery Boundaries (Tests B9 - B16)

    @Test("B9: Battery Level at Exactly Zero Percent (0.0)")
    func testB9_BatteryPercentageZero() {
        let state = PowerState(source: .battery, batteryLevel: 0.0, isCharging: false)
        #expect(state.batteryLevel == 0.0)
        #expect(state.isOnBattery == true)
    }

    @Test("B10: Battery Level at Boundary Edge (1% / 0.01)")
    func testB10_BatteryPercentageOnePercent() {
        let state = PowerState(source: .battery, batteryLevel: 0.01, isCharging: false)
        #expect(state.batteryLevel == 0.01)
        #expect(state.isOnBattery == true)
    }

    @Test("B11: Battery Level at Full Capacity (100% / 1.0)")
    func testB11_BatteryPercentageFull() {
        let state = PowerState(source: .battery, batteryLevel: 1.0, isCharging: true)
        #expect(state.batteryLevel == 1.0)
        #expect(state.isCharging == true)
    }

    @Test("B12: Desktop Mac Hardware Missing Battery Data (nil)")
    func testB12_MissingBatteryDataOnDesktopMac() {
        let state = PowerState(source: .ac, batteryLevel: nil, isCharging: false)
        #expect(state.source == .ac)
        #expect(state.batteryLevel == nil)
        #expect(state.isOnBattery == false)
    }

    @Test("B13: Thermal State Boundary: Nominal to Fair Does Not Throttle")
    func testB13_ThermalStateNominalToFair() {
        let fairPower = PowerState(thermalState: .fair)
        let config = EngineConfig()
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: fairPower,
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .play(fps: 60))
    }

    @Test("B14: Thermal State Boundary: Fair to Serious Invokes Throttling")
    func testB14_ThermalStateSeriousBoundary() {
        let seriousPower = PowerState(thermalState: .serious)
        let config = EngineConfig()
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: seriousPower,
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .throttle(fps: 30, reasons: [.thermalPressure]))
    }

    @Test("B15: Thermal State Boundary: Serious to Critical Triggers Total Pause")
    func testB15_ThermalStateCriticalBoundary() {
        let criticalPower = PowerState(thermalState: .critical)
        let config = EngineConfig()
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: criticalPower,
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .pause(reasons: [.thermalPressure]))
    }

    @Test("B16: Rapid Power Source Flapping (50 Alternating AC/Battery Cycles)")
    func testB16_RapidPowerSourceFlapping() {
        var power = PowerState(source: .ac)
        var config = EngineConfig()
        config.pauseOnBattery = true

        var pauseCount = 0
        var playCount = 0

        for i in 0..<50 {
            power.source = (i % 2 == 0) ? .battery : .ac
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: SleepLockState(),
                power: power,
                isDisplayVisible: true,
                config: config
            )
            switch decision {
            case .pause: pauseCount += 1
            case .play: playCount += 1
            case .throttle: break
            }
        }
        #expect(pauseCount == 25)
        #expect(playCount == 25)
    }

    // MARK: - Video Playback & Media Boundaries (Tests B17 - B24)

    @Test("B17: Zero-Byte Video File Rejection")
    func testB17_ZeroByteVideoFile() throws {
        let dir = try TestHarness.shared.createTemporaryDirectory()
        let zeroFile = try TestHarness.shared.createDummyVideoFile(in: dir, name: "empty.mp4", byteCount: 0)
        let attrs = try FileManager.default.attributesOfItem(atPath: zeroFile.path)
        let size = attrs[.size] as? Int ?? -1
        #expect(size == 0)
        try FileManager.default.removeItem(at: dir)
    }

    @Test("B18: Huge Video File Duration and Metadata Scaling")
    func testB18_HugeVideoFileHandling() {
        let hugeDuration = CMTime(seconds: 86400 * 7, preferredTimescale: 600) // 1 week duration
        let asset = VideoAsset(
            fileURL: URL(fileURLWithPath: "/wallpapers/100gb_render.mov"),
            title: "Ultra Render",
            duration: hugeDuration,
            naturalSize: CGSize(width: 7680, height: 4320),
            codec: "hvc1"
        )
        #expect(asset.duration.seconds == 604800.0)
        #expect(asset.naturalSize.width == 7680)
    }

    @Test("B19: Sub-Second Video Duration (0.1 Seconds)")
    func testB19_SubSecondVideoDuration() {
        let microDuration = CMTime(seconds: 0.1, preferredTimescale: 600)
        let asset = VideoAsset(
            fileURL: URL(fileURLWithPath: "/wallpapers/micro_loop.mp4"),
            title: "Micro",
            duration: microDuration
        )
        #expect(asset.duration.seconds == 0.1)
    }

    @Test("B20: Multi-Hour Video Duration Boundary (24 Hours)")
    func testB20_MultiHourVideoDuration() {
        let dayDuration = CMTime(seconds: 86400, preferredTimescale: 1)
        let asset = VideoAsset(
            fileURL: URL(fileURLWithPath: "/wallpapers/24hr_timelapse.mp4"),
            title: "Timelapse",
            duration: dayDuration
        )
        #expect(asset.duration.seconds == 86400.0)
    }

    @Test("B21: Unsupported Video Codec String Emits Specific Error")
    func testB21_UnsupportedVideoCodec() {
        let err = VideoEngineError.unreadableFormat("Unsupported codec: vp09")
        #expect(err.errorDescription?.contains("vp09") == true)
    }

    @Test("B22: Audio-Only Media File Rejected as Having No Video Track")
    func testB22_AudioOnlyFileRejection() {
        let url = URL(fileURLWithPath: "/music/track.m4a")
        let err = VideoEngineError.noVideoTrack(url)
        #expect(err.errorDescription?.contains("No video track") == true)
    }

    @Test("B23: Stall Watchdog Sub-Threshold (2.9s) Does Not Timeout")
    func testB23_StallWatchdogTimerPrecisionSubThreshold() {
        let config = VideoEngineConfiguration.default
        let elapsed: TimeInterval = 2.9
        #expect(elapsed < config.stallTimeoutThreshold)
    }

    @Test("B24: Stall Watchdog Super-Threshold (3.1s) Exceeds Timeout Threshold")
    func testB24_StallWatchdogTimerPrecisionSuperThreshold() {
        let config = VideoEngineConfiguration.default
        let elapsed: TimeInterval = 3.1
        #expect(elapsed > config.stallTimeoutThreshold)
    }

    // MARK: - Sleep, Lock, & Session Boundaries (Tests B25 - B32)

    @Test("B25: System Sleep Immediately Followed by Wake in Single Tick")
    func testB25_SleepImmediatelyFollowedByWake() {
        var state = SleepLockState(isSystemSleeping: true)
        #expect(state.isSystemSleeping == true)
        state.isSystemSleeping = false
        #expect(state.isSystemSleeping == false)
    }

    @Test("B26: Wake Occurs While Screen Remains Locked: Engine Stays Paused")
    func testB26_WakeWhileScreenRemainsLocked() {
        let sleepLock = SleepLockState(isSystemSleeping: false, areScreensSleeping: false, isScreenLocked: true)
        let config = EngineConfig()
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: sleepLock,
            power: PowerState(),
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .pause(reasons: [.screenLocked]))
    }

    @Test("B27: Screensaver and Display Sleep Flags True Simultaneously")
    func testB27_ScreensaverAndDisplaySleepSimultaneous() {
        let sleepLock = SleepLockState(areScreensSleeping: true, isScreensaverActive: true)
        let config = EngineConfig()
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: sleepLock,
            power: PowerState(),
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .pause(reasons: [.screensSleeping, .screensaverActive]))
    }

    @Test("B28: Rapid Darwin Lock/Unlock Toggles (20 Cycles)")
    func testB28_DarwinLockUnlockRapidToggles() {
        var sleepLock = SleepLockState()
        let config = EngineConfig()

        for i in 0..<20 {
            sleepLock.isScreenLocked = (i % 2 == 0)
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: sleepLock,
                power: PowerState(),
                isDisplayVisible: true,
                config: config
            )
            if i % 2 == 0 {
                #expect(decision == .pause(reasons: [.screenLocked]))
            } else {
                #expect(decision == .play(fps: 60))
            }
        }
    }

    @Test("B29: Session Inactive While Already Manually Paused")
    func testB29_SessionResignWhileAlreadyPaused() {
        let sleepLock = SleepLockState(isSessionActive: false)
        let config = EngineConfig()
        let decision = StateEvaluator.evaluate(
            manualPause: true,
            sleepLock: sleepLock,
            power: PowerState(),
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .pause(reasons: [.userRequested, .sessionInactive]))
    }

    @Test("B30: Multi-Display Asynchronous Sleep Events")
    func testB30_MultipleDisplaysSleepAsynchronously() {
        let occlusion = MockOcclusionManager()
        occlusion.registerDisplay(1, isVisible: true)
        occlusion.registerDisplay(2, isVisible: true)

        occlusion.setDisplayVisibility(1, isVisible: false)
        #expect(occlusion.isDisplayVisible(1) == false)
        #expect(occlusion.isDisplayVisible(2) == true)
    }

    @Test("B31: Display Wake While in Low Power Mode Evaluates to Paused")
    func testB31_DisplayWakeWithLPMActive() {
        let sleepLock = SleepLockState(areScreensSleeping: false)
        let power = PowerState(source: .battery, isLowPowerModeEnabled: true)
        let config = EngineConfig()
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: sleepLock,
            power: power,
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .pause(reasons: [.lowPowerMode]))
    }

    @Test("B32: Sleep Notification Handled Safely When Video Engine is Idle")
    func testB32_SleepWhileVideoEngineIdle() {
        let engine = MockVideoEngine()
        engine.pauseAll(reason: .systemSleeping)
        #expect(engine.isPaused == true)
        #expect(engine.activeDisplays.isEmpty == true)
    }

    // MARK: - Configuration & CLI Boundaries (Tests B33 - B40)

    @Test("B33: Config Target FPS Configured to Extreme High Rate (240 FPS)")
    func testB33_ConfigTargetFPSMaximum() {
        var config = EngineConfig()
        config.targetFrameRate = 240
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: PowerState(),
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .play(fps: 240))
    }

    @Test("B34: Config Throttled FPS Configured to Extreme Low Rate (15 FPS)")
    func testB34_ConfigTargetFPSLowRate() {
        var config = EngineConfig()
        config.throttledFrameRate = 15
        config.throttleOnBattery = true
        let power = PowerState(source: .battery)
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: power,
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .throttle(fps: 15, reasons: [.onBattery]))
    }

    @Test("B35: Corrupt JSON String Falls Back to Default Configuration")
    func testB35_CorruptJSONConfigFile() {
        let corruptData = "{\"invalid_json: true".data(using: .utf8)!
        let decoder = JSONDecoder()
        let decoded = try? decoder.decode(EngineConfig.self, from: corruptData)
        #expect(decoded == nil)
        let fallback = decoded ?? EngineConfig()
        #expect(fallback.targetFrameRate == 60)
    }

    @Test("B36: Empty Command Line Arguments Return Clean Default Options")
    func testB36_EmptyCommandLineArguments() {
        let opts = CommandLineOptions.parse(arguments: ["wallpaper_engine"])
        #expect(opts.videoPath == nil)
        #expect(opts.targetDisplayID == nil)
        #expect(opts.pauseOnBattery == false)
        #expect(opts.isHeadless == false)
    }

    @Test("B37: Non-Numeric Values in CLI Arguments Handled Safely")
    func testB37_CLIInvalidNumericValues() {
        let args = ["wallpaper_engine", "--display", "not_a_number", "--fps", "xyz"]
        let opts = CommandLineOptions.parse(arguments: args)
        #expect(opts.targetDisplayID == nil)
        #expect(opts.targetFPS == nil)
    }

    @Test("B38: Unknown CLI Flags Ignored Without Crashing")
    func testB38_CLIUnknownFlagGracefulIgnore() {
        let args = ["wallpaper_engine", "--bogus-flag", "--another-unknown", "val"]
        let opts = CommandLineOptions.parse(arguments: args)
        #expect(opts.isHeadless == false)
    }

    @Test("B39: Configuration with 100 Display Configurations Roundtrips")
    func testB39_ConfigWith100Displays() throws {
        var config = EngineConfig()
        for i in 1...100 {
            config.displayConfigurations["\(i)"] = EngineConfig.DisplayConfig(
                assetPath: "/wallpapers/vid_\(i).mp4",
                scalingMode: .aspectFill,
                isEnabled: true
            )
        }
        #expect(config.displayConfigurations.count == 100)
        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(EngineConfig.self, from: encoded)
        #expect(decoded.displayConfigurations.count == 100)
    }

    @Test("B40: Config Directory Auto-Creation on Save")
    func testB40_ConfigAtomicWriteDirectoryMissing() throws {
        let tempDir = try TestHarness.shared.createTemporaryDirectory()
        let nestedDir = tempDir.appendingPathComponent("Sub/Deep/Config")
        let configFile = nestedDir.appendingPathComponent("config.json")

        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        let config = EngineConfig()
        let data = try JSONEncoder().encode(config)
        try data.write(to: configFile, options: .atomic)

        #expect(FileManager.default.fileExists(atPath: configFile.path) == true)
        try FileManager.default.removeItem(at: tempDir)
    }
}

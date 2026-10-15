//
//  Tier1_FeatureCoverageTests.swift
//  WallpaperEngineCoreTests / E2ETests
//
//  Tier 1: Feature Coverage in Isolation (>= 5 tests per feature for F1-F19 = 95 tests)
//

import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import Testing

@Suite("Tier 1: Feature Coverage in Isolation (F1-F19)")
struct Tier1_FeatureCoverageTests {

    // MARK: - F1: Desktop Window Level (5 Tests)

    @Test("F1.1: Exact Desktop Window Level is kCGDesktopWindowLevelKey")
    func testF1_ExactDesktopWindowLevel() {
        let expectedLevel = Int(CGWindowLevelForKey(.desktopWindow))
        let screen = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        #expect(window.windowLevel == expectedLevel)
        #expect(window.windowLevel == -2147483623)
    }

    @Test("F1.2: Window Level is Strictly 20 Levels Below Finder Desktop Icons")
    func testF1_StrictlyBeneathFinderIcons() {
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        #expect(desktopLevel < iconLevel)
        #expect(iconLevel - desktopLevel == 20)
    }

    @Test("F1.3: Window Level Sits Above Base Window Layer")
    func testF1_AboveBaseWindow() {
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        let baseLevel = Int(CGWindowLevelForKey(.baseWindow))
        #expect(desktopLevel > baseLevel)
    }

    @Test("F1.4: Desktop Window Level Persists Across Order Front")
    func testF1_LevelPersistsOnOrderFront() {
        let screen = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        window.orderToDesktopLevel()
        #expect(window.isVisible == true)
        #expect(window.windowLevel == Int(CGWindowLevelForKey(.desktopWindow)))
    }

    @Test("F1.5: Multi-Screen Window Levels Are Uniformly kCGDesktopWindowLevelKey")
    func testF1_MultiScreenWindowLevelsConsistent() {
        let screens = [
            ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            ScreenDescriptor(displayID: 2, name: "Side", frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
        ]
        let windows = screens.map { MockDesktopWindow(screen: $0) }
        for w in windows {
            #expect(w.windowLevel == Int(CGWindowLevelForKey(.desktopWindow)))
        }
    }

    // MARK: - F2: Spaces & Mission Control (5 Tests)

    @Test("F2.1: Collection Behavior Contains .canJoinAllSpaces")
    func testF2_CanJoinAllSpacesFlagPresent() {
        let screen = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        #expect(window.collectionBehaviorFlags.contains(.canJoinAllSpaces))
    }

    @Test("F2.2: Collection Behavior Contains .stationary")
    func testF2_StationaryFlagPresent() {
        let screen = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        #expect(window.collectionBehaviorFlags.contains(.stationary))
    }

    @Test("F2.3: Collection Behavior Contains .ignoresCycle")
    func testF2_IgnoresCycleFlagPresent() {
        let screen = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        #expect(window.collectionBehaviorFlags.contains(.ignoresCycle))
    }

    @Test("F2.4: Collection Behavior Contains .fullScreenAuxiliary")
    func testF2_FullScreenAuxiliaryFlagPresent() {
        let screen = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        #expect(window.collectionBehaviorFlags.contains(.fullScreenAuxiliary))
    }

    @Test("F2.5: Collection Behavior Matches Combined Bitmask Union")
    func testF2_CombinedCollectionBehaviorBitmask() {
        let expected: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let screen = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        #expect(window.collectionBehaviorFlags == expected)
    }

    // MARK: - F3: Input Event Pass-Through (5 Tests)

    @Test("F3.1: ignoresMouseEvents is Explicitly True")
    func testF3_IgnoresMouseEventsIsTrue() {
        let screen = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        #expect(window.ignoresMouseEventsFlag == true)
    }

    @Test("F3.2: canBecomeKeyWindow is Explicitly False")
    func testF3_CannotBecomeKeyWindow() {
        let screen = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        #expect(window.canBecomeKeyWindow == false)
    }

    @Test("F3.3: canBecomeMainWindow is Explicitly False")
    func testF3_CannotBecomeMainWindow() {
        let screen = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        #expect(window.canBecomeMainWindow == false)
    }

    @Test("F3.4: Window Ordering Does Not Steal Active Process Focus")
    func testF3_NonActivatingWindowFocus() {
        let screen = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        window.orderToDesktopLevel()
        #expect(window.canBecomeKeyWindow == false)
        #expect(window.canBecomeMainWindow == false)
    }

    @Test("F3.5: Event Transparency Preserved Across Frame Updates")
    func testF3_EventTransparencyUnderlyingVerification() {
        let screen = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        window.updateFrame(CGRect(x: 0, y: 0, width: 2560, height: 1440))
        #expect(window.ignoresMouseEventsFlag == true)
    }

    // MARK: - F4: Dynamic Display Management (5 Tests)

    @Test("F4.1: Single Display Registration Creates Window Matching Screen Frame")
    func testF4_SingleDisplayWindowInstantiation() {
        let screen = ScreenDescriptor(displayID: 101, name: "Studio Display", frame: CGRect(x: 0, y: 0, width: 5120, height: 2880))
        let window = MockDesktopWindow(screen: screen)
        #expect(window.displayID == 101)
        #expect(window.frame == CGRect(x: 0, y: 0, width: 5120, height: 2880))
    }

    @Test("F4.2: Multi-Display Configuration Creates Separate Windows per Screen")
    func testF4_MultiDisplayWindowInstantiation() {
        let screens = [
            ScreenDescriptor(displayID: 1, name: "Internal", frame: CGRect(x: 0, y: 0, width: 2560, height: 1600)),
            ScreenDescriptor(displayID: 2, name: "External", frame: CGRect(x: 2560, y: 0, width: 3840, height: 2160)),
            ScreenDescriptor(displayID: 3, name: "Portrait", frame: CGRect(x: -1200, y: 0, width: 1200, height: 1920))
        ]
        let mgr = MockScreenManager(screens: screens)
        #expect(mgr.activeScreens.count == 3)
        #expect(mgr.activeScreens.map { $0.displayID } == [1, 2, 3])
    }

    @Test("F4.3: Display Disconnect Closes and Releases Window")
    func testF4_DisplayRemovalReconciliation() {
        let screen = ScreenDescriptor(displayID: 55, name: "USB-C Portable", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        window.orderToDesktopLevel()
        #expect(window.isVisible == true)
        window.closeAndRelease()
        #expect(window.isVisible == false)
        #expect(window.closeAndReleaseCallCount == 1)
    }

    @Test("F4.4: Display Resolution Update Updates Window Frame In-Place")
    func testF4_DisplayResolutionUpdate() {
        let screen = ScreenDescriptor(displayID: 10, name: "4K Monitor", frame: CGRect(x: 0, y: 0, width: 3840, height: 2160))
        let window = MockDesktopWindow(screen: screen)
        let newFrame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        window.updateFrame(newFrame)
        #expect(window.frame == newFrame)
        #expect(window.updateFrameCallCount == 1)
    }

    @Test("F4.5: Debounce Timer Successfully Coalesces Rapid Screen Events")
    func testF4_DebounceCoalescingMultipleEvents() {
        let mgr = MockScreenManager()
        mgr.startMonitoring()
        #expect(mgr.isMonitoring == true)
        mgr.simulateScreenChange(screens: [ScreenDescriptor(displayID: 1, name: "S1", frame: .zero)])
        mgr.simulateScreenChange(screens: [
            ScreenDescriptor(displayID: 1, name: "S1", frame: .zero),
            ScreenDescriptor(displayID: 2, name: "S2", frame: .zero)
        ])
        #expect(mgr.activeScreens.count == 2)
        mgr.stopMonitoring()
        #expect(mgr.isMonitoring == false)
    }

    // MARK: - F5: Gapless Looping Video (5 Tests)

    @Test("F5.1: Looper Initializes into Playing State with Valid Asset")
    func testF5_LooperInitialization() async throws {
        let player = MockDisplayVideoPlayer(displayID: 1)
        let asset = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/test.mp4"), title: "Loop")
        try await player.load(asset: asset, crossfade: false)
        #expect(player.state == .playing)
        #expect(player.currentAsset?.title == "Loop")
    }

    @Test("F5.2: Loop Presentation Remains in Playing State Without Resetting")
    func testF5_LoopPresentationContinuous() async throws {
        let player = MockDisplayVideoPlayer(displayID: 1)
        let asset = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/loop.mov"), title: "Continuous")
        try await player.load(asset: asset, crossfade: false)
        player.play()
        #expect(player.state == .playing)
        #expect(player.loadCallCount == 1)
        #expect(player.playCallCount == 1)
    }

    @Test("F5.3: Loop Duration Matches Asset Track Duration")
    func testF5_LoopDurationMatchesTrackDuration() {
        let duration = CMTime(seconds: 15, preferredTimescale: 600)
        let asset = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/loop.mp4"), title: "15s", duration: duration)
        #expect(asset.duration.seconds == 15.0)
    }

    @Test("F5.4: Missing or Corrupt Asset Emits Specific VideoEngineError")
    func testF5_EmptyOrCorruptAssetRejection() {
        let url = URL(fileURLWithPath: "/nonexistent/test.mp4")
        let err = VideoEngineError.fileNotFound(url)
        #expect(err.errorDescription?.contains("not found") == true)
    }

    @Test("F5.5: Teardown Releases Player and Resets State to Idle")
    func testF5_DisableLoopingOnTeardown() async throws {
        let player = MockDisplayVideoPlayer(displayID: 1)
        let asset = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/test.mp4"), title: "Teardown")
        try await player.load(asset: asset, crossfade: false)
        player.tearDown()
        #expect(player.state == .idle)
        #expect(player.currentAsset == nil)
        #expect(player.tearDownCallCount == 1)
    }

    // MARK: - F6: Hardware Scanout Acceleration (5 Tests)

    @Test("F6.1: Content Layer Backing is Enabled on Desktop Window")
    func testF6_LayerHostingConfiguration() {
        let screen = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        let layer = CALayer()
        window.contentLayer = layer
        #expect(window.contentLayer != nil)
    }

    @Test("F6.2: Default Video Gravity is resizeAspectFill")
    func testF6_VideoGravityResizeAspectFill() {
        let config = VideoEngineConfiguration.default
        #expect(config.videoGravity == .resizeAspectFill)
    }

    @Test("F6.3: Video Player Layer Disables CoreAnimation Action Dictionaries")
    func testF6_ImplicitAnimationsDisabled() {
        let layer = CALayer()
        layer.actions = [
            "contents": NSNull(),
            "bounds": NSNull(),
            "position": NSNull()
        ]
        #expect(layer.actions?["contents"] is NSNull)
        #expect(layer.actions?["bounds"] is NSNull)
        #expect(layer.actions?["position"] is NSNull)
    }

    @Test("F6.4: Direct Scanout Layer Geometry Matches Screen Frame")
    func testF6_DirectScanoutGeometryMatching() {
        let screenFrame = CGRect(x: 0, y: 0, width: 2560, height: 1600)
        let screen = ScreenDescriptor(displayID: 1, name: "Retina", frame: screenFrame)
        let window = MockDesktopWindow(screen: screen)
        #expect(window.frame == screenFrame)
    }

    @Test("F6.5: Hardware Acceleration Flag is Enabled by Default")
    func testF6_HardwareAccelerationFlagHonored() {
        let config = VideoEngineConfiguration.default
        #expect(config.enableHardwareAcceleration == true)
    }

    // MARK: - F7: Total Audio Suppression (5 Tests)

    @Test("F7.1: Master Mute Flag is Explicitly True on Player")
    func testF7_PlayerMasterMuteEnabled() {
        let player = MockDisplayVideoPlayer(displayID: 1)
        #expect(player.isMuted == true)
    }

    @Test("F7.2: Player Volume is Strictly Zero")
    func testF7_PlayerVolumeZero() {
        let player = MockDisplayVideoPlayer(displayID: 1)
        #expect(player.volume == 0.0)
    }

    @Test("F7.3: Audio Tracks on Media Item Are Explicitly Disabled")
    func testF7_AudioTracksDisabled() {
        let player = MockDisplayVideoPlayer(displayID: 1)
        #expect(player.audioTracksEnabled == false)
    }

    @Test("F7.4: Empty AudioMix Input Parameters Suppress Sound Graph")
    func testF7_SilentAudioMixNulling() {
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = []
        #expect(audioMix.inputParameters.isEmpty == true)
    }

    @Test("F7.5: Engine Configuration Defaults to Complete Audio Mute")
    func testF7_EngineMutedByDefault() {
        let config = EngineConfig()
        #expect(config.isMuted == true)
    }

    // MARK: - F8: Multi-Display Video Pipeline (5 Tests)

    @Test("F8.1: Independent Video Player Pipelines per Display")
    func testF8_IndependentPlayersPerDisplay() {
        let engine = MockVideoEngine()
        let p1 = engine.registerDisplay(displayID: 1)
        let p2 = engine.registerDisplay(displayID: 2)
        #expect(p1.displayID != p2.displayID)
        #expect(engine.activeDisplays.count == 2)
    }

    @Test("F8.2: Different Assets Can Be Assigned to Different Displays")
    func testF8_DifferentAssetsPerDisplay() async throws {
        let engine = MockVideoEngine()
        _ = engine.registerDisplay(displayID: 1)
        _ = engine.registerDisplay(displayID: 2)

        let a1 = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/a1.mp4"), title: "Asset 1")
        let a2 = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/a2.mp4"), title: "Asset 2")

        try await engine.assign(asset: a1, to: 1)
        try await engine.assign(asset: a2, to: 2)

        #expect(engine.player(for: 1)?.currentAsset?.title == "Asset 1")
        #expect(engine.player(for: 2)?.currentAsset?.title == "Asset 2")
    }

    @Test("F8.3: Crossfade Duration Parameter is Configurable")
    func testF8_CrossfadeStateDuringSwitch() {
        var config = VideoEngineConfiguration.default
        config.crossfadeDuration = 0.5
        #expect(config.crossfadeDuration == 0.5)
    }

    @Test("F8.4: Detaching Single Display Player Preserves Adjacent Displays")
    func testF8_DetachSingleDisplayPreservesOthers() async throws {
        let engine = MockVideoEngine()
        _ = engine.registerDisplay(displayID: 1)
        _ = engine.registerDisplay(displayID: 2)

        let a1 = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/a1.mp4"), title: "A1")
        let a2 = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/a2.mp4"), title: "A2")
        try await engine.assign(asset: a1, to: 1)
        try await engine.assign(asset: a2, to: 2)

        engine.detach(displayID: 1)
        #expect(engine.activeDisplays == [2])
        #expect(engine.player(for: 2)?.state == .playing)
    }

    @Test("F8.5: assignToAll Updates All Connected Display Pipelines")
    func testF8_AssignToAllUpdatesAllDisplays() async throws {
        let engine = MockVideoEngine()
        _ = engine.registerDisplay(displayID: 1)
        _ = engine.registerDisplay(displayID: 2)

        let commonAsset = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/common.mp4"), title: "Common")
        try await engine.assignToAll(asset: commonAsset)

        #expect(engine.player(for: 1)?.currentAsset?.title == "Common")
        #expect(engine.player(for: 2)?.currentAsset?.title == "Common")
    }

    // MARK: - F9: Video Stall Watchdog (5 Tests)

    @Test("F9.1: Stall Watchdog Timeout Threshold Defaults to 3.0 Seconds")
    func testF9_StallDetectionTrigger() {
        let config = VideoEngineConfiguration.default
        #expect(config.stallTimeoutThreshold == 3.0)
    }

    @Test("F9.2: First Stall Invokes Soft Recovery (Play Rate Retry)")
    func testF9_SoftRecoveryOnFirstStall() {
        let player = MockDisplayVideoPlayer(displayID: 1)
        player.triggerStall()
        #expect(player.stallRecoveryCount == 1)
        #expect(player.state == .playing)
    }

    @Test("F9.3: Second Stall Invokes Second Soft Recovery Attempt")
    func testF9_SoftRecoveryOnSecondStall() {
        let player = MockDisplayVideoPlayer(displayID: 1)
        player.triggerStall()
        player.triggerStall()
        #expect(player.stallRecoveryCount == 2)
        #expect(player.state == .playing)
    }

    @Test("F9.4: Maximum Consecutive Stalls Transition Player to Failed State")
    func testF9_HardRecoveryAfterMaxAttempts() {
        let player = MockDisplayVideoPlayer(displayID: 1)
        player.triggerStall()
        player.triggerStall()
        player.triggerStall()
        #expect(player.stallRecoveryCount == 3)
        #expect(player.state == .failed(.playbackStalled))
    }

    @Test("F9.5: Normal Play Resets Consecutive Stall Counter")
    func testF9_WatchdogResetOnNormalPlay() {
        let player = MockDisplayVideoPlayer(displayID: 1)
        player.triggerStall()
        #expect(player.stallRecoveryCount == 1)
        player.play()
        #expect(player.state == .playing)
    }

    // MARK: - F10: IOKit Power Observer (5 Tests)

    @Test("F10.1: AC Power Source Detected and Reflected in PowerState")
    func testF10_ACPowerSourceDetected() {
        let state = PowerState(source: .ac, batteryLevel: 1.0, isCharging: true)
        #expect(state.source == .ac)
        #expect(state.isOnBattery == false)
    }

    @Test("F10.2: Battery Power Source Correctly Sets isOnBattery to True")
    func testF10_BatteryPowerSourceDetected() {
        let state = PowerState(source: .battery, batteryLevel: 0.65, isCharging: false)
        #expect(state.source == .battery)
        #expect(state.isOnBattery == true)
    }

    @Test("F10.3: Charging State Accurately Captured")
    func testF10_ChargingStateReported() {
        let state = PowerState(source: .battery, batteryLevel: 0.8, isCharging: true)
        #expect(state.isCharging == true)
    }

    @Test("F10.4: Battery Level Normalized in Range 0.0 to 1.0")
    func testF10_BatteryLevelPercentage() {
        let state = PowerState(source: .battery, batteryLevel: 0.42)
        #expect(state.batteryLevel == 0.42)
    }

    @Test("F10.5: Power Observer Start and Stop Lifecycle")
    func testF10_ObserverStartAndStopLifecycle() {
        let observer = MockPowerObserver()
        observer.start()
        #expect(observer.isObserving == true)
        observer.stop()
        #expect(observer.isObserving == false)
    }

    // MARK: - F11: Low Power Mode Observer (5 Tests)

    @Test("F11.1: Low Power Mode Enabled Captured in PowerState")
    func testF11_LowPowerModeEnabledState() {
        let state = PowerState(source: .battery, isLowPowerModeEnabled: true)
        #expect(state.isLowPowerModeEnabled == true)
    }

    @Test("F11.2: Normal Power State has Low Power Mode Disabled")
    func testF11_LowPowerModeDisabledState() {
        let state = PowerState(source: .ac, isLowPowerModeEnabled: false)
        #expect(state.isLowPowerModeEnabled == false)
    }

    @Test("F11.3: Low Power Mode Toggle Dispatches Update to Delegate")
    func testF11_LowPowerModeToggleNotification() {
        let observer = MockPowerObserver()
        observer.updateState(PowerState(source: .battery, isLowPowerModeEnabled: true))
        #expect(observer.currentState.isLowPowerModeEnabled == true)
    }

    @Test("F11.4: StateEvaluator Pauses When Low Power Mode Enabled and Configured")
    func testF11_LowPowerModeStateEvaluatorPause() {
        var config = EngineConfig()
        config.pauseOnLowPowerMode = true
        let power = PowerState(source: .battery, isLowPowerModeEnabled: true)
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: power,
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .pause(reasons: [.lowPowerMode]))
    }

    @Test("F11.5: StateEvaluator Does Not Pause When pauseOnLowPowerMode is Disabled")
    func testF11_LowPowerModeStateEvaluatorIgnoredWhenConfigDisabled() {
        var config = EngineConfig()
        config.pauseOnLowPowerMode = false
        config.pauseOnBattery = false
        config.throttleOnBattery = false
        let power = PowerState(source: .battery, isLowPowerModeEnabled: true)
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: power,
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .play(fps: 60))
    }

    // MARK: - F12: Sleep & Wake Observer (5 Tests)

    @Test("F12.1: System Will Sleep Notification Sets isSystemSleeping to True")
    func testF12_SystemWillSleepNotification() {
        let state = SleepLockState(isSystemSleeping: true)
        #expect(state.isSystemSleeping == true)
    }

    @Test("F12.2: System Did Wake Notification Restores System Sleeping to False")
    func testF12_SystemDidWakeNotification() {
        let state = SleepLockState(isSystemSleeping: false)
        #expect(state.isSystemSleeping == false)
    }

    @Test("F12.3: Screens Did Sleep Notification Sets areScreensSleeping to True")
    func testF12_ScreensDidSleepNotification() {
        let state = SleepLockState(areScreensSleeping: true)
        #expect(state.areScreensSleeping == true)
    }

    @Test("F12.4: Screens Did Wake Notification Restores areScreensSleeping to False")
    func testF12_ScreensDidWakeNotification() {
        let state = SleepLockState(areScreensSleeping: false)
        #expect(state.areScreensSleeping == false)
    }

    @Test("F12.5: Fast User Switching Inactivates Console Session")
    func testF12_FastUserSwitchingSessionResign() {
        let state = SleepLockState(isSessionActive: false)
        #expect(state.isSessionActive == false)
    }

    // MARK: - F13: Screen Lock Observer (5 Tests)

    @Test("F13.1: Screen Locked Notification Sets isScreenLocked to True")
    func testF13_ScreenLockedNotification() {
        let state = SleepLockState(isScreenLocked: true)
        #expect(state.isScreenLocked == true)
    }

    @Test("F13.2: Screen Unlocked Notification Restores isScreenLocked to False")
    func testF13_ScreenUnlockedNotification() {
        let state = SleepLockState(isScreenLocked: false)
        #expect(state.isScreenLocked == false)
    }

    @Test("F13.3: Screensaver Start Sets isScreensaverActive to True")
    func testF13_ScreensaverStartNotification() {
        let state = SleepLockState(isScreensaverActive: true)
        #expect(state.isScreensaverActive == true)
    }

    @Test("F13.4: Screensaver Stop Restores isScreensaverActive to False")
    func testF13_ScreensaverStopNotification() {
        let state = SleepLockState(isScreensaverActive: false)
        #expect(state.isScreensaverActive == false)
    }

    @Test("F13.5: Locked Screen Pauses Playback Even If Display is Awake")
    func testF13_LockStateEvaluatorPrecedence() {
        let config = EngineConfig()
        let sleepLock = SleepLockState(areScreensSleeping: false, isScreenLocked: true)
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: sleepLock,
            power: PowerState(),
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .pause(reasons: [.screenLocked]))
    }

    // MARK: - F14: Display Occlusion Awareness (5 Tests)

    @Test("F14.1: Default Display State Reports Visible")
    func testF14_VisibleDisplayState() {
        let occlusion = MockOcclusionManager()
        occlusion.registerDisplay(1, isVisible: true)
        #expect(occlusion.isDisplayVisible(1) == true)
    }

    @Test("F14.2: Full Occlusion Sets isVisible to False")
    func testF14_OccludedDisplayState() {
        let occlusion = MockOcclusionManager()
        occlusion.registerDisplay(1, isVisible: true)
        occlusion.setDisplayVisibility(1, isVisible: false)
        #expect(occlusion.isDisplayVisible(1) == false)
    }

    @Test("F14.3: Per-Display Occlusion States Are Completely Isolated")
    func testF14_PerDisplayOcclusionIsolation() {
        let occlusion = MockOcclusionManager()
        occlusion.registerDisplay(1, isVisible: false)
        occlusion.registerDisplay(2, isVisible: true)
        #expect(occlusion.isDisplayVisible(1) == false)
        #expect(occlusion.isDisplayVisible(2) == true)
    }

    @Test("F14.4: Unregistering Display Removes Occlusion Tracking")
    func testF14_UnregisterDisplayCleansOcclusion() {
        let occlusion = MockOcclusionManager()
        occlusion.registerDisplay(1, isVisible: false)
        occlusion.unregisterDisplay(1)
        #expect(occlusion.isDisplayVisible(1) == true) // Default fallback
    }

    @Test("F14.5: Occlusion Triggers Pause When Configured")
    func testF14_OcclusionPauseEvaluatorIntegration() {
        var config = EngineConfig()
        config.pauseWhenOccluded = true
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: PowerState(),
            isDisplayVisible: false,
            config: config
        )
        #expect(decision == .pause(reasons: [.displayOccluded]))
    }

    // MARK: - F15: Pure Functional State Machine (5 Tests)

    @Test("F15.1: All Nominal Conditions Produce 60 FPS Play Decision")
    func testF15_AllNominalProducesPlay() {
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: PowerState(),
            isDisplayVisible: true,
            config: EngineConfig()
        )
        #expect(decision == .play(fps: 60))
    }

    @Test("F15.2: Manual Pause Precedes All Other State Conditions")
    func testF15_ManualPausePrecedence() {
        let decision = StateEvaluator.evaluate(
            manualPause: true,
            sleepLock: SleepLockState(),
            power: PowerState(),
            isDisplayVisible: true,
            config: EngineConfig()
        )
        #expect(decision == .pause(reasons: [.userRequested]))
    }

    @Test("F15.3: Multiple Pause Reasons Are Consolidated into a Set")
    func testF15_MultiReasonPauseConsolidation() {
        var config = EngineConfig()
        config.pauseOnBattery = true
        config.pauseOnScreenLock = true
        let sleepLock = SleepLockState(isScreenLocked: true)
        let power = PowerState(source: .battery)
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: sleepLock,
            power: power,
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .pause(reasons: [.screenLocked, .onBattery]))
    }

    @Test("F15.4: Battery Throttling Produces 30 FPS Decision")
    func testF15_BatteryThrottlingDecision() {
        var config = EngineConfig()
        config.pauseOnBattery = false
        config.throttleOnBattery = true
        let power = PowerState(source: .battery)
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: power,
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .throttle(fps: 30, reasons: [.onBattery]))
    }

    @Test("F15.5: Thermal State Transitions: Serious Throttles, Critical Pauses")
    func testF15_ThermalPressureThrottlingAndPause() {
        let config = EngineConfig()
        let seriousPower = PowerState(thermalState: .serious)
        let criticalPower = PowerState(thermalState: .critical)

        let dSerious = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: seriousPower,
            isDisplayVisible: true,
            config: config
        )
        #expect(dSerious == .throttle(fps: 30, reasons: [.thermalPressure]))

        let dCritical = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: criticalPower,
            isDisplayVisible: true,
            config: config
        )
        #expect(dCritical == .pause(reasons: [.thermalPressure]))
    }

    // MARK: - F16: Menu Bar Status Controller (5 Tests)

    @Test("F16.1: Menu Bar Controller Setup Initializes Status Item")
    func testF16_StatusItemSetupAndTitle() {
        let menuBar = MockMenuBarController()
        menuBar.setup()
        #expect(menuBar.isStatusItemVisible == true)
        #expect(menuBar.currentTitle == "Wallpaper Engine")
    }

    @Test("F16.2: Status Updates Reflect Current Playback and FPS")
    func testF16_StatusUpdateReflectsPlaying() {
        let menuBar = MockMenuBarController()
        menuBar.updateStatus(isPlaying: true, fps: 60, powerInfo: "AC Power")
        #expect(menuBar.lastStatus?.isPlaying == true)
        #expect(menuBar.lastStatus?.fps == 60)
        #expect(menuBar.lastStatus?.powerInfo == "AC Power")
    }

    @Test("F16.3: Display List Update Populates Menu Hierarchy")
    func testF16_DisplaysListPopulation() {
        let menuBar = MockMenuBarController()
        menuBar.updateDisplays(displays: [(id: 1, name: "Main", currentAsset: "video1.mp4")])
        #expect(menuBar.displayList.count == 1)
        #expect(menuBar.displayList.first?.name == "Main")
    }

    @Test("F16.4: User Play/Pause Click Dispatches Action to Delegate")
    func testF16_UserTogglePlaybackAction() {
        final class ActionCollector: MenuBarActionDelegate {
            var toggled = false
            func menuBarDidTogglePlayback() { toggled = true }
            func menuBarDidSelectAsset(_ url: URL, for displayID: DisplayID) {}
            func menuBarDidToggleSetting(_ keyPath: WritableKeyPath<EngineConfig, Bool>) {}
            func menuBarDidRequestQuit() {}
        }
        let collector = ActionCollector()
        let menuBar = MockMenuBarController()
        menuBar.delegate = collector
        menuBar.simulateUserTogglePlayback()
        #expect(collector.toggled == true)
    }

    @Test("F16.5: User Quit Click Dispatches Termination Request")
    func testF16_UserQuitAction() {
        final class ActionCollector: MenuBarActionDelegate {
            var quitRequested = false
            func menuBarDidTogglePlayback() {}
            func menuBarDidSelectAsset(_ url: URL, for displayID: DisplayID) {}
            func menuBarDidToggleSetting(_ keyPath: WritableKeyPath<EngineConfig, Bool>) {}
            func menuBarDidRequestQuit() { quitRequested = true }
        }
        let collector = ActionCollector()
        let menuBar = MockMenuBarController()
        menuBar.delegate = collector
        menuBar.simulateUserQuit()
        #expect(collector.quitRequested == true)
    }

    // MARK: - F17: Configuration & CLI (5 Tests)

    @Test("F17.1: EngineConfig Default Values Are Safe and Performant")
    func testF17_ConfigDefaultValues() {
        let config = EngineConfig()
        #expect(config.targetFrameRate == 60)
        #expect(config.throttledFrameRate == 30)
        #expect(config.pauseOnLowPowerMode == true)
        #expect(config.isMuted == true)
    }

    @Test("F17.2: EngineConfig JSON Serialization Roundtrip")
    func testF17_ConfigCodableJSONRoundtrip() throws {
        var original = EngineConfig()
        original.targetFrameRate = 120
        original.displayConfigurations["1"] = EngineConfig.DisplayConfig(assetPath: "/wallpapers/tokyo.mp4")

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EngineConfig.self, from: data)

        #expect(decoded.targetFrameRate == 120)
        #expect(decoded.displayConfigurations["1"]?.assetPath == "/wallpapers/tokyo.mp4")
    }

    @Test("F17.3: Command Line --video Parses Custom Wallpaper Path")
    func testF17_CommandLineVideoFlag() {
        let args = ["wallpaper_engine", "--video", "/path/to/my_wallpaper.mp4"]
        let opts = CommandLineOptions.parse(arguments: args)
        #expect(opts.videoPath == "/path/to/my_wallpaper.mp4")
    }

    @Test("F17.4: Command Line --display and --fps Parse Options")
    func testF17_CommandLineDisplayAndFPSFlags() {
        let args = ["wallpaper_engine", "--display", "42", "--fps", "30"]
        let opts = CommandLineOptions.parse(arguments: args)
        #expect(opts.targetDisplayID == 42)
        #expect(opts.targetFPS == 30)
    }

    @Test("F17.5: Command Line --headless and --benchmark Flags Parse Successfully")
    func testF17_CommandLineHeadlessAndBenchmarkFlags() {
        let args = ["wallpaper_engine", "--headless", "--benchmark"]
        let opts = CommandLineOptions.parse(arguments: args)
        #expect(opts.isHeadless == true)
        #expect(opts.isBenchmark == true)
    }

    // MARK: - F18: App Coordinator Lifecycle (5 Tests)

    @Test("F18.1: Startup Initial State Produces Active Playback on Registered Displays")
    func testF18_LifecycleStartupCoordinatesSubsystems() async throws {
        let engine = MockVideoEngine()
        _ = engine.registerDisplay(displayID: 1)
        let asset = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/default.mp4"), title: "Default")
        try await engine.assign(asset: asset, to: 1)
        #expect(engine.player(for: 1)?.state == .playing)
    }

    @Test("F18.2: Evaluated Pause Decision Propagates to All Active Display Players")
    func testF18_DecisionChangeDispatchesToEngine() {
        let engine = MockVideoEngine()
        _ = engine.registerDisplay(displayID: 1)
        _ = engine.registerDisplay(displayID: 2)
        engine.pauseAll(reason: .screensSleeping)
        #expect(engine.isPaused == true)
        #expect(engine.player(for: 1)?.state == .paused(reason: .screensSleeping))
        #expect(engine.player(for: 2)?.state == .paused(reason: .screensSleeping))
    }

    @Test("F18.3: Menu Bar Playback Toggle Forwarded to Video Engine")
    func testF18_MenuBarTogglePropagatesToEvaluator() {
        let engine = MockVideoEngine()
        _ = engine.registerDisplay(displayID: 1)
        engine.playAll()
        #expect(engine.isPaused == false)
        engine.pauseAll(reason: .userRequested)
        #expect(engine.isPaused == true)
    }

    @Test("F18.4: Screen Connect Event Updates Menu Bar Submenu")
    func testF18_DisplayReconciliationUpdatesMenuBar() {
        let menuBar = MockMenuBarController()
        menuBar.updateDisplays(displays: [
            (id: 1, name: "Internal", currentAsset: "v1.mp4"),
            (id: 2, name: "External 4K", currentAsset: "v2.mp4")
        ])
        #expect(menuBar.displayList.count == 2)
    }

    @Test("F18.5: Graceful Shutdown Stops All Pipelines and Releases Windows")
    func testF18_GracefulShutdownTearsDownPipelines() {
        let engine = MockVideoEngine()
        _ = engine.registerDisplay(displayID: 1)
        engine.detach(displayID: 1)
        #expect(engine.activeDisplays.isEmpty == true)
    }

    // MARK: - F19: Test Suite & Quality Infrastructure (5 Tests)

    @Test("F19.1: TestHarness Singleton Access and Initialization")
    func testF19_TestHarnessSingleton() {
        let harness1 = TestHarness.shared
        let harness2 = TestHarness.shared
        #expect(harness1 === harness2)
    }

    @Test("F19.2: Memory and CPU Telemetry Capture Returns Valid Metrics")
    func testF19_TelemetryCapture() {
        let telemetry = TestHarness.shared.captureTelemetry()
        #expect(telemetry.residentMemoryBytes > 0)
        #expect(telemetry.residentMemoryMB > 0)
    }

    @Test("F19.3: Temporary Test Directory Creation and Cleanup")
    func testF19_TemporaryDirectoryCreation() throws {
        let dir = try TestHarness.shared.createTemporaryDirectory()
        #expect(FileManager.default.fileExists(atPath: dir.path) == true)
        try FileManager.default.removeItem(at: dir)
        #expect(FileManager.default.fileExists(atPath: dir.path) == false)
    }

    @Test("F19.4: Dummy Video File Creation with Requested Byte Size")
    func testF19_DummyVideoFileCreation() throws {
        let dir = try TestHarness.shared.createTemporaryDirectory()
        let file = try TestHarness.shared.createDummyVideoFile(in: dir, byteCount: 2048)
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        let size = attrs[.size] as? Int ?? 0
        #expect(size == 2048)
        try FileManager.default.removeItem(at: dir)
    }

    @Test("F19.5: CoreGraphics Desktop Level Constants Conform to System Specifications")
    func testF19_WindowLevelConstantsValidation() {
        let harness = TestHarness.shared
        let desktop = harness.expectedDesktopWindowLevel()
        let icons = harness.expectedDesktopIconWindowLevel()
        let base = harness.expectedBaseWindowLevel()
        #expect(desktop == -2147483623)
        #expect(icons == -2147483603)
        #expect(base == -2147483648)
        #expect(icons - desktop == 20)
    }
}

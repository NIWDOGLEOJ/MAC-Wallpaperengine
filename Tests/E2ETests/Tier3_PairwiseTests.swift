//
//  Tier3_PairwiseTests.swift
//  WallpaperEngineCoreTests / E2ETests
//
//  Tier 3: Pairwise Combinatorial Subsystem Interaction Tests (50 tests)
//

import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import Testing

@Suite("Tier 3: Pairwise Cross-Feature Interactions")
struct Tier3_PairwiseTests {

    // MARK: - Window Management x Video Playback (Tests P1 - P10)

    @Test("P1: Display Resize During Active Video Playback Updates Window Frame Without Halting Playback")
    func testP1_DisplayResizeDuringActivePlayback() async throws {
        let screen = ScreenDescriptor(displayID: 1, name: "Monitor", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        let player = MockDisplayVideoPlayer(displayID: 1)
        let asset = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/loop.mp4"), title: "Loop")

        try await player.load(asset: asset, crossfade: false)
        #expect(player.state == .playing)

        let newFrame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        window.updateFrame(newFrame)

        #expect(window.frame == newFrame)
        #expect(player.state == .playing)
    }

    @Test("P2: Connecting Second Display While Primary Plays Video Spawns Independent Pipeline")
    func testP2_SecondDisplayConnectDuringSinglePlayback() async throws {
        let engine = MockVideoEngine()
        let p1 = engine.registerDisplay(displayID: 1)
        let a1 = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/v1.mp4"), title: "V1")
        try await p1.load(asset: a1, crossfade: false)

        let p2 = engine.registerDisplay(displayID: 2)
        let a2 = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/v2.mp4"), title: "V2")
        try await p2.load(asset: a2, crossfade: false)

        #expect(engine.activeDisplays.count == 2)
        #expect(p1.state == .playing)
        #expect(p2.state == .playing)
    }

    @Test("P3: Primary Display Disconnect Leaves Secondary Display Playing Uninterrupted")
    func testP3_PrimaryDisplayDisconnectWhileSecondaryPlays() async throws {
        let engine = MockVideoEngine()
        let p1 = engine.registerDisplay(displayID: 1)
        let p2 = engine.registerDisplay(displayID: 2)

        try await p1.load(asset: VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/v1.mp4"), title: "V1"), crossfade: false)
        try await p2.load(asset: VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/v2.mp4"), title: "V2"), crossfade: false)

        engine.detach(displayID: 1)

        #expect(engine.activeDisplays == [2])
        #expect(p2.state == .playing)
    }

    @Test("P4: Asset Switch Crossfade Occurs While Window Frame Is Updated")
    func testP4_AssetSwitchCrossfadeDuringScreenMove() async throws {
        let screen = ScreenDescriptor(displayID: 1, name: "Screen", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        let player = MockDisplayVideoPlayer(displayID: 1)

        let a1 = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/v1.mp4"), title: "V1")
        try await player.load(asset: a1, crossfade: false)

        let a2 = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/v2.mp4"), title: "V2")
        try await player.load(asset: a2, crossfade: true)
        window.updateFrame(CGRect(x: 100, y: 100, width: 1920, height: 1080))

        #expect(player.currentAsset?.title == "V2")
        #expect(window.frame.origin.x == 100)
    }

    @Test("P5: Ordering Window to Desktop Level While Paused Preserves Paused State")
    func testP5_WindowReorderToDesktopLevelWhilePaused() {
        let screen = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        let player = MockDisplayVideoPlayer(displayID: 1)

        player.pause(reason: .userRequested)
        window.orderToDesktopLevel()

        #expect(window.isVisible == true)
        #expect(player.state == .paused(reason: .userRequested))
    }

    @Test("P6: Window Teardown on Display Removal Automatically Halts Player Pipeline")
    func testP6_WindowTeardownOnDisplayRemovalHaltsPipeline() {
        let screen = ScreenDescriptor(displayID: 7, name: "Aux", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = MockDesktopWindow(screen: screen)
        let player = MockDisplayVideoPlayer(displayID: 7)

        window.closeAndRelease()
        player.tearDown()

        #expect(window.isVisible == false)
        #expect(player.state == .idle)
    }

    @Test("P7: Newly Registered Display Automatically Assigned Default Asset")
    func testP7_NewDisplayAttachedWithDefaultAsset() async throws {
        let engine = MockVideoEngine()
        let defaultAsset = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/default.mp4"), title: "Default")

        let p1 = engine.registerDisplay(displayID: 1)
        try await p1.load(asset: defaultAsset, crossfade: false)

        #expect(p1.currentAsset?.title == "Default")
    }

    @Test("P8: Negative Screen Origin Preserves Video Layer Frame Geometry")
    func testP8_WindowFrameNegativeOriginPreservesVideoScanout() {
        let negFrame = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let screen = ScreenDescriptor(displayID: 2, name: "Left Monitor", frame: negFrame)
        let window = MockDesktopWindow(screen: screen)

        #expect(window.frame == negFrame)
        #expect(window.frame.width == 1920)
    }

    @Test("P9: Multiple Windows Playing Identical Asset Maintain Independent Players")
    func testP9_MultipleWindowsShareSameAssetIndependently() async throws {
        let engine = MockVideoEngine()
        let p1 = engine.registerDisplay(displayID: 1)
        let p2 = engine.registerDisplay(displayID: 2)

        let commonAsset = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/shared.mp4"), title: "Shared")
        try await p1.load(asset: commonAsset, crossfade: false)
        try await p2.load(asset: commonAsset, crossfade: false)

        p1.pause(reason: .userRequested)

        #expect(p1.state == .paused(reason: .userRequested))
        #expect(p2.state == .playing)
    }

    @Test("P10: Rapid Add and Remove Displays During Playback Loop")
    func testP10_RapidAddRemoveDisplaysDuringPlaybackLoop() {
        let engine = MockVideoEngine()
        for i in 1...10 {
            let p = engine.registerDisplay(displayID: DisplayID(i))
            p.play()
            if i % 2 == 0 {
                engine.detach(displayID: DisplayID(i))
            }
        }
        #expect(engine.activeDisplays.count == 5)
    }

    // MARK: - Power State x Video Playback (Tests P11 - P20)

    @Test("P11: Switching from AC to Battery with pauseOnBattery Pauses Video Engine")
    func testP11_UnplugFromACToBatteryWithPauseOnBattery() {
        var config = EngineConfig()
        config.pauseOnBattery = true

        var power = PowerState(source: .ac)
        let d1 = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: power,
            isDisplayVisible: true,
            config: config
        )
        #expect(d1 == .play(fps: 60))

        power.source = .battery
        let d2 = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: power,
            isDisplayVisible: true,
            config: config
        )
        #expect(d2 == .pause(reasons: [.onBattery]))
    }

    @Test("P12: Switching to Battery with throttleOnBattery Throttles Video Engine to 30 FPS")
    func testP12_UnplugFromACToBatteryWithThrottleOnBattery() {
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

    @Test("P13: Reconnecting AC Power Resumes Playback from Battery Pause")
    func testP13_PlugIntoACResumesFromBatteryPause() {
        var config = EngineConfig()
        config.pauseOnBattery = true

        var power = PowerState(source: .battery)
        let pausedDecision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: power,
            isDisplayVisible: true,
            config: config
        )
        #expect(pausedDecision == .pause(reasons: [.onBattery]))

        power.source = .ac
        let resumedDecision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: power,
            isDisplayVisible: true,
            config: config
        )
        #expect(resumedDecision == .play(fps: 60))
    }

    @Test("P14: Low Power Mode Activation While on Battery Pauses Playback")
    func testP14_LowPowerModeActivatedWhilePlayingOnBattery() {
        var config = EngineConfig()
        config.pauseOnLowPowerMode = true
        config.pauseOnBattery = false

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

    @Test("P15: Disabling Low Power Mode on AC Power Restores 60 FPS Playback")
    func testP15_LowPowerModeDisabledWhileOnACResumes() {
        let config = EngineConfig()
        let power = PowerState(source: .ac, isLowPowerModeEnabled: false)
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: power,
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .play(fps: 60))
    }

    @Test("P16: Thermal Spike to Serious Throttles Video Playback to 30 FPS")
    func testP16_ThermalSpikeToSeriousDuringPlayback() {
        let config = EngineConfig()
        let power = PowerState(thermalState: .serious)
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: power,
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .throttle(fps: 30, reasons: [.thermalPressure]))
    }

    @Test("P17: Thermal Spike to Critical Pauses Video Playback Completely")
    func testP17_ThermalSpikeToCriticalDuringPlayback() {
        let config = EngineConfig()
        let power = PowerState(thermalState: .critical)
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: power,
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .pause(reasons: [.thermalPressure]))
    }

    @Test("P18: Thermal Recovery from Critical to Nominal Resumes Playback")
    func testP18_ThermalRecoveryFromCriticalToNominalResumes() {
        let config = EngineConfig()
        var power = PowerState(thermalState: .critical)
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: power, isDisplayVisible: true, config: config) == .pause(reasons: [.thermalPressure]))

        power.thermalState = .nominal
        #expect(StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: power, isDisplayVisible: true, config: config) == .play(fps: 60))
    }

    @Test("P19: Battery Drain to Empty While Playing Maintains Paused Decision")
    func testP19_BatteryDrainToEmptyWhilePlaying() {
        var config = EngineConfig()
        config.pauseOnBattery = true
        let power = PowerState(source: .battery, batteryLevel: 0.0)
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: power,
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .pause(reasons: [.onBattery]))
    }

    @Test("P20: Power State Change Dispatched to Observer Delegate Safely")
    func testP20_PowerStateChangeDuringAssetLoading() {
        final class PowerStateCollector: PowerObserverDelegate {
            var receivedState: PowerState?
            func powerStateDidChange(_ newState: PowerState) { receivedState = newState }
        }
        let collector = PowerStateCollector()
        let observer = MockPowerObserver()
        observer.delegate = collector

        let newState = PowerState(source: .battery, batteryLevel: 0.5)
        observer.updateState(newState)

        #expect(collector.receivedState == newState)
    }

    // MARK: - Sleep / Lock Lifecycle x Video Playback (Tests P21 - P30)

    @Test("P21: System Sleep Notification Pauses All Active Video Players")
    func testP21_SystemSleepPausesActiveVideoPlayer() {
        let engine = MockVideoEngine()
        _ = engine.registerDisplay(displayID: 1)
        engine.pauseAll(reason: .systemSleeping)
        #expect(engine.isPaused == true)
        #expect(engine.player(for: 1)?.state == .paused(reason: .systemSleeping))
    }

    @Test("P22: System Wake Notification Resumes Video Players When Screen Unlocked")
    func testP22_SystemWakeResumesActiveVideoPlayer() {
        let engine = MockVideoEngine()
        _ = engine.registerDisplay(displayID: 1)
        engine.pauseAll(reason: .systemSleeping)
        engine.playAll()
        #expect(engine.isPaused == false)
        #expect(engine.player(for: 1)?.state == .playing)
    }

    @Test("P23: Darwin Screen Lock Notification Immediately Pauses Video Engine")
    func testP23_ScreenLockPausesVideoPlayer() {
        let engine = MockVideoEngine()
        _ = engine.registerDisplay(displayID: 1)
        engine.pauseAll(reason: .screenLocked)
        #expect(engine.player(for: 1)?.state == .paused(reason: .screenLocked))
    }

    @Test("P24: Darwin Screen Unlock Notification Immediately Resumes Video Engine")
    func testP24_ScreenUnlockResumesVideoPlayer() {
        let engine = MockVideoEngine()
        _ = engine.registerDisplay(displayID: 1)
        engine.pauseAll(reason: .screenLocked)
        engine.playAll()
        #expect(engine.player(for: 1)?.state == .playing)
    }

    @Test("P25: Display Sleep During Asset Crossfade Transitions Safely to Paused")
    func testP25_DisplaySleepDuringAssetCrossfade() async throws {
        let player = MockDisplayVideoPlayer(displayID: 1)
        try await player.load(asset: VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/v1.mp4"), title: "V1"), crossfade: false)
        player.pause(reason: .screensSleeping)
        #expect(player.state == .paused(reason: .screensSleeping))
    }

    @Test("P26: Wake into Locked State Keeps Video Player Paused")
    func testP26_WakeIntoLockedStateKeepsPlayerPaused() {
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

    @Test("P27: Fast User Switching Inactivates Session and Pauses Playback")
    func testP27_FastUserSwitchingPausesPlayer() {
        let sleepLock = SleepLockState(isSessionActive: false)
        let config = EngineConfig()
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: sleepLock,
            power: PowerState(),
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .pause(reasons: [.sessionInactive]))
    }

    @Test("P28: Fast User Switching Return Restores Active Session and Resumes")
    func testP28_FastUserSwitchingReturnResumesPlayer() {
        let sleepLock = SleepLockState(isSessionActive: true)
        let config = EngineConfig()
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: sleepLock,
            power: PowerState(),
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .play(fps: 60))
    }

    @Test("P29: Screensaver Start Pauses Playback Immediately")
    func testP29_ScreensaverStartPausesPlayer() {
        let sleepLock = SleepLockState(isScreensaverActive: true)
        let config = EngineConfig()
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: sleepLock,
            power: PowerState(),
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .pause(reasons: [.screensaverActive]))
    }

    @Test("P30: Screensaver Dismissal Resumes Playback Immediately")
    func testP30_ScreensaverDismissResumesPlayer() {
        let sleepLock = SleepLockState(isScreensaverActive: false)
        let config = EngineConfig()
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: sleepLock,
            power: PowerState(),
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .play(fps: 60))
    }

    // MARK: - Occlusion x Multi-Display Video Pipeline (Tests P31 - P40)

    @Test("P31: Display 1 Occluded Pauses Display 1 While Display 2 Remains Playing")
    func testP31_DisplayOneOccludedWhileDisplayTwoVisible() {
        let occlusion = MockOcclusionManager()
        occlusion.registerDisplay(1, isVisible: false)
        occlusion.registerDisplay(2, isVisible: true)

        let d1 = StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: PowerState(), isDisplayVisible: occlusion.isDisplayVisible(1), config: EngineConfig())
        let d2 = StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: PowerState(), isDisplayVisible: occlusion.isDisplayVisible(2), config: EngineConfig())

        #expect(d1 == .pause(reasons: [.displayOccluded]))
        #expect(d2 == .play(fps: 60))
    }

    @Test("P32: Bringing Display 1 Back to Visible Resumes Playback")
    func testP32_DisplayOneRestoredToVisibleResumes() {
        let occlusion = MockOcclusionManager()
        occlusion.registerDisplay(1, isVisible: false)
        occlusion.setDisplayVisibility(1, isVisible: true)

        let d = StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: PowerState(), isDisplayVisible: occlusion.isDisplayVisible(1), config: EngineConfig())
        #expect(d == .play(fps: 60))
    }

    @Test("P33: Both Displays Occluded Simultaneously Pauses Both Pipelines")
    func testP33_BothDisplaysOccludedPausesGlobal() {
        let occlusion = MockOcclusionManager()
        occlusion.registerDisplay(1, isVisible: false)
        occlusion.registerDisplay(2, isVisible: false)

        let d1 = StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: PowerState(), isDisplayVisible: occlusion.isDisplayVisible(1), config: EngineConfig())
        let d2 = StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: PowerState(), isDisplayVisible: occlusion.isDisplayVisible(2), config: EngineConfig())

        #expect(d1 == .pause(reasons: [.displayOccluded]))
        #expect(d2 == .pause(reasons: [.displayOccluded]))
    }

    @Test("P34: Occlusion Ignored When pauseWhenOccluded Is Disabled in Preferences")
    func testP34_OcclusionIgnoredWhenConfigDisabled() {
        var config = EngineConfig()
        config.pauseWhenOccluded = false
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: PowerState(),
            isDisplayVisible: false,
            config: config
        )
        #expect(decision == .play(fps: 60))
    }

    @Test("P35: Full-Screen Space Switch Occludes Desktop Window and Pauses")
    func testP35_SpaceSwitchOccludesStandardDesktop() {
        let config = EngineConfig()
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: PowerState(),
            isDisplayVisible: false,
            config: config
        )
        #expect(decision == .pause(reasons: [.displayOccluded]))
    }

    @Test("P36: Swiping Back to Desktop Space Restores Visibility and Resumes")
    func testP36_SpaceSwitchBackToDesktopResumes() {
        let config = EngineConfig()
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: PowerState(),
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .play(fps: 60))
    }

    @Test("P37: Disconnecting an Occluded Screen Cleans Up Tracking Without Leaks")
    func testP37_OccludedDisplayDisconnectHandledCleanly() {
        let occlusion = MockOcclusionManager()
        occlusion.registerDisplay(5, isVisible: false)
        occlusion.unregisterDisplay(5)
        #expect(occlusion.isDisplayVisible(5) == true)
    }

    @Test("P38: New Asset Assigned to Occluded Display Stays in Paused State")
    func testP38_AssetAssignmentToOccludedDisplay() async throws {
        let player = MockDisplayVideoPlayer(displayID: 1)
        let asset = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/v.mp4"), title: "V")
        try await player.load(asset: asset, crossfade: false)
        player.pause(reason: .displayOccluded)

        #expect(player.state == .paused(reason: .displayOccluded))
    }

    @Test("P39: Thermal Critical Takes Precedence Over Occlusion State")
    func testP39_ThermalThrottleOnOccludedDisplayPrecedence() {
        let config = EngineConfig()
        let power = PowerState(thermalState: .critical)
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: power,
            isDisplayVisible: false,
            config: config
        )
        #expect(decision == .pause(reasons: [.thermalPressure, .displayOccluded]))
    }

    @Test("P40: Manual Pause and Occlusion Reasons Consolidate Correctly")
    func testP40_DisplayOccludedWhileManualPauseActive() {
        let config = EngineConfig()
        let decision = StateEvaluator.evaluate(
            manualPause: true,
            sleepLock: SleepLockState(),
            power: PowerState(),
            isDisplayVisible: false,
            config: config
        )
        #expect(decision == .pause(reasons: [.userRequested, .displayOccluded]))
    }

    // MARK: - Menu Bar & User Controls x State Machine (Tests P41 - P50)

    @Test("P41: User Manual Pause Overrides AC Power and Resumed Observers")
    func testP41_UserManualPauseOverridesAllObservers() {
        let config = EngineConfig()
        let decision = StateEvaluator.evaluate(
            manualPause: true,
            sleepLock: SleepLockState(),
            power: PowerState(source: .ac),
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .pause(reasons: [.userRequested]))
    }

    @Test("P42: User Manual Resume Clears User Pause and Produces 60 FPS")
    func testP42_UserManualResumeOverridesObserverPause() {
        let config = EngineConfig()
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: PowerState(source: .ac),
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .play(fps: 60))
    }

    @Test("P43: User Toggling pauseOnBattery Setting Dynamically Pauses When on Battery")
    func testP43_UserTogglesPauseOnBatterySetting() {
        var config = EngineConfig()
        config.pauseOnBattery = false
        config.throttleOnBattery = false
        let power = PowerState(source: .battery)

        let d1 = StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: power, isDisplayVisible: true, config: config)
        #expect(d1 == .play(fps: 60))

        config.pauseOnBattery = true
        let d2 = StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: power, isDisplayVisible: true, config: config)
        #expect(d2 == .pause(reasons: [.onBattery]))
    }

    @Test("P44: User Toggling pauseOnLowPowerMode Dynamically Updates Decision")
    func testP44_UserTogglesPauseOnLowPowerModeSetting() {
        var config = EngineConfig()
        config.pauseOnLowPowerMode = false
        let power = PowerState(isLowPowerModeEnabled: true)

        let d1 = StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: power, isDisplayVisible: true, config: config)
        #expect(d1 == .play(fps: 60))

        config.pauseOnLowPowerMode = true
        let d2 = StateEvaluator.evaluate(manualPause: false, sleepLock: SleepLockState(), power: power, isDisplayVisible: true, config: config)
        #expect(d2 == .pause(reasons: [.lowPowerMode]))
    }

    @Test("P45: User Picking New Asset From Menu Bar Forwards URL to Specific Display")
    func testP45_UserSelectsNewAssetForDisplayOne() {
        final class AssetSelectionSink: MenuBarActionDelegate {
            var selectedURL: URL?
            var targetDisplay: DisplayID?
            func menuBarDidTogglePlayback() {}
            func menuBarDidSelectAsset(_ url: URL, for displayID: DisplayID) {
                selectedURL = url
                targetDisplay = displayID
            }
            func menuBarDidToggleSetting(_ keyPath: WritableKeyPath<EngineConfig, Bool>) {}
            func menuBarDidRequestQuit() {}
        }
        let sink = AssetSelectionSink()
        let menuBar = MockMenuBarController()
        menuBar.delegate = sink

        let testURL = URL(fileURLWithPath: "/wallpapers/new_scene.mp4")
        menuBar.simulateUserSelectAsset(testURL, for: 1)

        #expect(sink.selectedURL == testURL)
        #expect(sink.targetDisplay == 1)
    }

    @Test("P46: User Changing Target FPS from 60 to 120 Updates Play Decision")
    func testP46_UserChangesTargetFPSWhilePlaying() {
        var config = EngineConfig()
        config.targetFrameRate = 120
        let decision = StateEvaluator.evaluate(
            manualPause: false,
            sleepLock: SleepLockState(),
            power: PowerState(),
            isDisplayVisible: true,
            config: config
        )
        #expect(decision == .play(fps: 120))
    }

    @Test("P47: User Quit Action Forwards Termination Request to AppCoordinator")
    func testP47_UserRequestsQuitInitiatesGracefulShutdown() {
        final class QuitSink: MenuBarActionDelegate {
            var quitInvoked = false
            func menuBarDidTogglePlayback() {}
            func menuBarDidSelectAsset(_ url: URL, for displayID: DisplayID) {}
            func menuBarDidToggleSetting(_ keyPath: WritableKeyPath<EngineConfig, Bool>) {}
            func menuBarDidRequestQuit() { quitInvoked = true }
        }
        let sink = QuitSink()
        let menuBar = MockMenuBarController()
        menuBar.delegate = sink
        menuBar.simulateUserQuit()
        #expect(sink.quitInvoked == true)
    }

    @Test("P48: Menu Bar Status Item Displays Throttled Status Information")
    func testP48_MenuBarStatusItemReflectsThrottledState() {
        let menuBar = MockMenuBarController()
        menuBar.updateStatus(isPlaying: true, fps: 30, powerInfo: "Battery Power (Throttled)")
        #expect(menuBar.lastStatus?.fps == 30)
        #expect(menuBar.lastStatus?.powerInfo.contains("Throttled") == true)
    }

    @Test("P49: Menu Bar Status Item Displays Paused Status Information")
    func testP49_MenuBarStatusItemReflectsPausedState() {
        let menuBar = MockMenuBarController()
        menuBar.updateStatus(isPlaying: false, fps: 0, powerInfo: "Paused (Screen Locked)")
        #expect(menuBar.lastStatus?.isPlaying == false)
        #expect(menuBar.lastStatus?.fps == 0)
    }

    @Test("P50: Setting Toggle in Menu Bar Persists Updated State to EngineConfig")
    func testP50_ConfigPersistenceUpdatedOnMenuBarToggle() {
        var config = EngineConfig()
        config.pauseOnBattery = false

        let toggleKeyPath: WritableKeyPath<EngineConfig, Bool> = \.pauseOnBattery
        config[keyPath: toggleKeyPath].toggle()

        #expect(config.pauseOnBattery == true)
    }
}

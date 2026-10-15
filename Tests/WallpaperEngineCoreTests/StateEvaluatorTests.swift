//
//  StateEvaluatorTests.swift
//  WallpaperEngineCoreTests
//
//  Unit and combinatorial integration test suite for StateEvaluator pure functional engine.
//

import AppKit
import CoreGraphics
import Foundation
@testable import WallpaperEngineCore

@MainActor
public struct StateEvaluatorTests {

    public static func runAllTests() async {
        let runner = TestRunner.shared
        await runner.runSuite("StateEvaluator Pure Functional Decision Matrix") {
            testNominalPlaybackAndTargetFPS()
            testManualPauseOverrides()
            testSleepAndLockPermutations()
            testPowerAndLowPowerModePermutations()
            testThermalPressureLifecycle()
            testDisplayOcclusionAndMultiScreen()
            testExhaustiveReasonSetAccumulationAndUnwinding()
            testFrameRateThrottlingPropagation()
            testDesktopMacInvariance()
            testPureFunctionDeterminismAndZeroMutation()
        }
    }

    // MARK: - Test Suites

    static func testNominalPlaybackAndTargetFPS() {
        TestRunner.shared.test("Nominal: AC power, active session, unoccluded -> .play(60)") {
            let config = EngineConfig(targetFrameRate: 60)
            let sleepLock = MockSleepLockEventGenerator.normalActive()
            let power = MockPowerEventGenerator.ac()

            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: sleepLock,
                power: power,
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(decision, .play(fps: 60))
        }

        TestRunner.shared.test("Nominal: Custom 120 FPS target on ProMotion display") {
            let config = EngineConfig(targetFrameRate: 120)
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: MockPowerEventGenerator.ac(),
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(decision, .play(fps: 120))
        }

        TestRunner.shared.test("Nominal: Thermal state .fair does not throttle") {
            let config = EngineConfig(targetFrameRate: 60)
            let power = MockPowerEventGenerator.ac(thermalState: .fair)
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: power,
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(decision, .play(fps: 60))
        }
    }

    static func testManualPauseOverrides() {
        TestRunner.shared.test("Manual: manualPause == true produces .userRequested") {
            let decision = StateEvaluator.evaluate(
                manualPause: true,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: MockPowerEventGenerator.ac(),
                isDisplayVisible: true,
                config: EngineConfig()
            )
            try assertEqual(decision, .pause(reasons: [.userRequested]))
        }

        TestRunner.shared.test("Manual: config.isPaused == true produces .userRequested") {
            let config = EngineConfig(isPaused: true)
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: MockPowerEventGenerator.ac(),
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(decision, .pause(reasons: [.userRequested]))
        }

        TestRunner.shared.test("Manual: manualPause overrides all auto-pause toggles disabled") {
            let config = EngineConfig(
                pauseOnBattery: false,
                throttleOnBattery: false,
                pauseOnLowPowerMode: false,
                pauseOnScreenLock: false,
                pauseOnDisplaySleep: false,
                pauseWhenOccluded: false
            )
            let decision = StateEvaluator.evaluate(
                manualPause: true,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: MockPowerEventGenerator.battery(),
                isDisplayVisible: false,
                config: config
            )
            try assertEqual(decision, .pause(reasons: [.userRequested]))
        }
    }

    static func testSleepAndLockPermutations() {
        TestRunner.shared.test("Sleep/Lock: Screen locked with pauseOnScreenLock = true") {
            let config = EngineConfig(pauseOnScreenLock: true)
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.locked(),
                power: MockPowerEventGenerator.ac(),
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(decision, .pause(reasons: [.screenLocked]))
        }

        TestRunner.shared.test("Sleep/Lock: Screen locked with pauseOnScreenLock = false ignores lock") {
            let config = EngineConfig(pauseOnScreenLock: false)
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.locked(),
                power: MockPowerEventGenerator.ac(),
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(decision, .play(fps: 60))
        }

        TestRunner.shared.test("Sleep/Lock: Displays sleeping produces .screensSleeping") {
            let config = EngineConfig(pauseOnDisplaySleep: true)
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.screensSleeping(),
                power: MockPowerEventGenerator.ac(),
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(decision, .pause(reasons: [.screensSleeping]))
        }

        TestRunner.shared.test("Sleep/Lock: Screensaver active pauses unconditionally") {
            let config = EngineConfig()
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.screensaver(),
                power: MockPowerEventGenerator.ac(),
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(decision, .pause(reasons: [.screensaverActive]))
        }

        TestRunner.shared.test("Sleep/Lock: Fast User Switching sessionInactive pauses unconditionally") {
            let config = EngineConfig()
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.sessionInactive(),
                power: MockPowerEventGenerator.ac(),
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(decision, .pause(reasons: [.sessionInactive]))
        }
    }

    static func testPowerAndLowPowerModePermutations() {
        TestRunner.shared.test("Power: Battery with pauseOnBattery = true") {
            let config = EngineConfig(pauseOnBattery: true, throttleOnBattery: true)
            let power = MockPowerEventGenerator.battery()
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: power,
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(decision, .pause(reasons: [.onBattery]))
        }

        TestRunner.shared.test("Power: Battery with throttleOnBattery = true and pauseOnBattery = false") {
            let config = EngineConfig(throttledFrameRate: 30, pauseOnBattery: false, throttleOnBattery: true)
            let power = MockPowerEventGenerator.battery()
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: power,
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(decision, .throttle(fps: 30, reasons: [.onBattery]))
        }

        TestRunner.shared.test("Power: Battery with both battery pause and throttle disabled -> .play(60)") {
            let config = EngineConfig(pauseOnBattery: false, throttleOnBattery: false)
            let power = MockPowerEventGenerator.battery()
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: power,
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(decision, .play(fps: 60))
        }

        TestRunner.shared.test("Power: Low Power Mode on AC power produces .lowPowerMode") {
            let config = EngineConfig(pauseOnLowPowerMode: true)
            let power = MockPowerEventGenerator.ac(isLowPowerMode: true)
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: power,
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(decision, .pause(reasons: [.lowPowerMode]))
        }
    }

    static func testThermalPressureLifecycle() {
        TestRunner.shared.test("Thermal: .serious triggers throttling") {
            let config = EngineConfig(throttledFrameRate: 30)
            let power = MockPowerEventGenerator.thermalSerious()
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: power,
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(decision, .throttle(fps: 30, reasons: [.thermalPressure]))
        }

        TestRunner.shared.test("Thermal: .critical triggers pause") {
            let config = EngineConfig()
            let power = MockPowerEventGenerator.thermalCritical()
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: power,
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(decision, .pause(reasons: [.thermalPressure]))
        }

        TestRunner.shared.test("Thermal: .serious + Battery Throttle combines throttle reasons") {
            let config = EngineConfig(throttledFrameRate: 30, pauseOnBattery: false, throttleOnBattery: true)
            let power = MockPowerEventGenerator.thermalSerious(onBattery: true)
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: power,
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(decision, .throttle(fps: 30, reasons: [.onBattery, .thermalPressure]))
        }
    }

    static func testDisplayOcclusionAndMultiScreen() {
        TestRunner.shared.test("Occlusion: isDisplayVisible = false produces .displayOccluded") {
            let config = EngineConfig(pauseWhenOccluded: true)
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: MockPowerEventGenerator.ac(),
                isDisplayVisible: false,
                config: config
            )
            try assertEqual(decision, .pause(reasons: [.displayOccluded]))
        }

        TestRunner.shared.test("Occlusion: pauseWhenOccluded = false plays even when occluded") {
            let config = EngineConfig(pauseWhenOccluded: false)
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: MockPowerEventGenerator.ac(),
                isDisplayVisible: false,
                config: config
            )
            try assertEqual(decision, .play(fps: 60))
        }

        TestRunner.shared.test("Multi-Display: Display 1 visible, Display 2 occluded") {
            let config = EngineConfig(pauseWhenOccluded: true)
            let displays: [CGDirectDisplayID: Bool] = [
                1: true,
                2: false
            ]
            let decisions = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: MockPowerEventGenerator.ac(),
                displays: displays,
                config: config
            )
            try assertEqual(decisions[1], .play(fps: 60))
            try assertEqual(decisions[2], .pause(reasons: [.displayOccluded]))
        }
    }

    static func testExhaustiveReasonSetAccumulationAndUnwinding() {
        TestRunner.shared.test("Exhaustive: All 10 pause conditions present simultaneously") {
            let config = EngineConfig(
                pauseOnBattery: true,
                pauseOnLowPowerMode: true,
                pauseOnScreenLock: true,
                pauseOnDisplaySleep: true,
                pauseWhenOccluded: true
            )
            let sleepLock = SleepLockState(
                isSystemSleeping: true,
                areScreensSleeping: true,
                isScreenLocked: true,
                isScreensaverActive: true,
                isSessionActive: false
            )
            let power = PowerState(
                source: .battery,
                batteryLevel: 0.1,
                isCharging: false,
                isLowPowerModeEnabled: true,
                thermalState: .critical
            )

            let decision = StateEvaluator.evaluate(
                manualPause: true,
                sleepLock: sleepLock,
                power: power,
                isDisplayVisible: false,
                config: config
            )

            let expectedReasons: Set<PauseReason> = [
                .userRequested,
                .systemSleeping,
                .screensSleeping,
                .screenLocked,
                .screensaverActive,
                .sessionInactive,
                .lowPowerMode,
                .onBattery,
                .displayOccluded,
                .thermalPressure
            ]
            try assertEqual(decision, .pause(reasons: expectedReasons))
            guard case .pause(let reasons) = decision else {
                throw TestFailure("Expected .pause")
            }
            try assertEqual(reasons.count, 10)
        }

        TestRunner.shared.test("Unwinding: Clearing 10 reasons sequentially to throttled then play") {
            var manual = true
            var sysSleep = true
            var screensSleep = true
            var locked = true
            var saver = true
            var session = false
            var lpm = true
            var src = PowerSource.battery
            var visible = false
            var therm = ProcessInfo.ThermalState.critical

            let config = EngineConfig(
                pauseOnBattery: true,
                throttleOnBattery: true,
                pauseOnLowPowerMode: true,
                pauseOnScreenLock: true,
                pauseOnDisplaySleep: true,
                pauseWhenOccluded: true
            )

            // Step 1: clear manual pause
            manual = false
            var d = StateEvaluator.evaluate(
                manualPause: manual,
                sleepLock: SleepLockState(isSystemSleeping: sysSleep, areScreensSleeping: screensSleep, isScreenLocked: locked, isScreensaverActive: saver, isSessionActive: session),
                power: PowerState(source: src, batteryLevel: 0.5, isCharging: false, isLowPowerModeEnabled: lpm, thermalState: therm),
                isDisplayVisible: visible,
                config: config
            )
            guard case .pause(let r1) = d else { throw TestFailure("Step 1 failed") }
            try assertEqual(r1.count, 9)

            // Step 2-9: clear sleep, lock, screensaver, session, lpm, battery, occlusion
            sysSleep = false
            screensSleep = false
            locked = false
            saver = false
            session = true
            lpm = false
            src = .ac
            visible = true

            // Only thermal critical remains
            d = StateEvaluator.evaluate(
                manualPause: manual,
                sleepLock: SleepLockState(isSystemSleeping: sysSleep, areScreensSleeping: screensSleep, isScreenLocked: locked, isScreensaverActive: saver, isSessionActive: session),
                power: PowerState(source: src, batteryLevel: nil, isCharging: false, isLowPowerModeEnabled: lpm, thermalState: therm),
                isDisplayVisible: visible,
                config: config
            )
            try assertEqual(d, .pause(reasons: [.thermalPressure]))

            // Thermal drops to .serious -> Transitions to throttle!
            therm = .serious
            d = StateEvaluator.evaluate(
                manualPause: manual,
                sleepLock: SleepLockState(isSystemSleeping: sysSleep, areScreensSleeping: screensSleep, isScreenLocked: locked, isScreensaverActive: saver, isSessionActive: session),
                power: PowerState(source: src, batteryLevel: nil, isCharging: false, isLowPowerModeEnabled: lpm, thermalState: therm),
                isDisplayVisible: visible,
                config: config
            )
            try assertEqual(d, .throttle(fps: 30, reasons: [.thermalPressure]))

            // Thermal drops to .nominal -> Transitions to play!
            therm = .nominal
            d = StateEvaluator.evaluate(
                manualPause: manual,
                sleepLock: SleepLockState(isSystemSleeping: sysSleep, areScreensSleeping: screensSleep, isScreenLocked: locked, isScreensaverActive: saver, isSessionActive: session),
                power: PowerState(source: src, batteryLevel: nil, isCharging: false, isLowPowerModeEnabled: lpm, thermalState: therm),
                isDisplayVisible: visible,
                config: config
            )
            try assertEqual(d, .play(fps: 60))
        }
    }

    static func testFrameRateThrottlingPropagation() {
        TestRunner.shared.test("FrameRate: Custom throttledFrameRate 15 propagated on battery") {
            let config = EngineConfig(
                targetFrameRate: 60,
                throttledFrameRate: 15,
                pauseOnBattery: false,
                throttleOnBattery: true
            )
            let power = MockPowerEventGenerator.battery()
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: power,
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(decision, .throttle(fps: 15, reasons: [.onBattery]))
        }
    }

    static func testDesktopMacInvariance() {
        TestRunner.shared.test("Desktop: Mac Studio (AC only, nil battery) never throttles on battery") {
            let config = EngineConfig(pauseOnBattery: true, throttleOnBattery: true)
            let power = PowerState(
                source: .ac,
                batteryLevel: nil,
                isCharging: false,
                isLowPowerModeEnabled: false,
                thermalState: .nominal
            )
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: power,
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(decision, .play(fps: 60))
        }
    }

    static func testPureFunctionDeterminismAndZeroMutation() {
        TestRunner.shared.test("Purity: 1,000 deterministic iterations produce identical outputs") {
            let config = EngineConfig(targetFrameRate: 60, throttledFrameRate: 30)
            let power = MockPowerEventGenerator.thermalSerious(onBattery: true)
            let sleepLock = MockSleepLockEventGenerator.normalActive()

            let baseline = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: sleepLock,
                power: power,
                isDisplayVisible: true,
                config: config
            )

            for _ in 1...1000 {
                let current = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: sleepLock,
                    power: power,
                    isDisplayVisible: true,
                    config: config
                )
                try assertEqual(current, baseline)
            }
        }
    }
}

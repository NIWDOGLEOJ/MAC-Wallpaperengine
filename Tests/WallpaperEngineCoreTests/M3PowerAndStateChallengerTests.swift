//
//  M3PowerAndStateChallengerTests.swift
//  WallpaperEngineCoreTests
//
//  Milestone 3 Adversarial Empirical Challenger Probes:
//  - Probe 1: 10-Condition Pause Accumulation & Strict Unwinding Invariance
//  - Probe 2: Desktop Mac Hardware State Invariance (Zero False Battery Throttling)
//  - Probe 3: Thermal Escalation Ladder & Hysteresis Recovery
//  - Probe 4: Adversarial Edge Cases & Priority Matrix Preemption
//  - Probe 5: PowerObserver Deduplication & High-Frequency State Flapping
//

import AppKit
import CoreGraphics
import Foundation
@testable import WallpaperEngineCore

@MainActor
public struct M3PowerAndStateChallengerTests {

    public static func runAllTests() async {
        let runner = TestRunner.shared
        await runner.runSuite("M3 Adversarial Challenger: 10-Condition Accumulation & Unwinding") {
            testProbe1_1_AllTenConditionsSimultaneouslyActive()
            testProbe1_2_StrictSequentialUnwindingCanonical()
            testProbe1_3_StrictSequentialUnwindingReverse()
            testProbe1_4_AllTenConditionsIsolatedSingleReason()
            testProbe1_5_RandomizedPermutationUnwinding()
        }

        await runner.runSuite("M3 Adversarial Challenger: Desktop Mac Hardware Invariance") {
            testProbe2_1_DesktopMacBaselineInvariance()
            testProbe2_2_DesktopMacThermalInvariance()
            testProbe2_3_DesktopMacMultiRefreshRates()
            testProbe2_4_DesktopMac10kEvaluationFlurry()
            testProbe2_5_DesktopMacWithUPSPower()
        }

        await runner.runSuite("M3 Adversarial Challenger: Thermal Escalation Ladder & Hysteresis") {
            testProbe3_1_FullThermalEscalationLadderAndRecovery()
            testProbe3_2_ConcurrentThermalAndBatteryThrottling()
            testProbe3_3_RapidThermalFlapping1000Cycles()
        }

        await runner.runSuite("M3 Adversarial Challenger: Priority Matrix & Boundary Preemption") {
            testProbe4_1_FrameRateSanitizationClamp()
            testProbe4_2_UnconditionalOverridesUnderAllFlagsDisabled()
            testProbe4_3_MultiDisplayOcclusionIndependenceAndGlobalLock()
        }

        await runner.runSuite("M3 Adversarial Challenger: PowerObserver Stream & Lifecycle Probes") {
            testProbe5_1_PowerObserver10kDeduplication()
            testProbe5_2_PowerObserverRapidLifecycleFlurry()
            testProbe5_3_PowerObserverRapidStateFlapping()
        }
    }

    // MARK: - Probe 1: 10-Condition Pause Accumulation & Unwinding

    static func testProbe1_1_AllTenConditionsSimultaneouslyActive() {
        TestRunner.shared.test("CHALLENGE 1.1: Complete 10-Condition Simultaneous Accumulation") {
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
                batteryLevel: 0.15,
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
                .thermalPressure,
                .displayOccluded
            ]

            guard case .pause(let reasons) = decision else {
                throw TestFailure("Decision must be .pause when all 10 conditions are active, got: \(decision)")
            }

            try assertEqual(reasons, expectedReasons, "All 10 pause reasons must be captured in the Set")
            try assertEqual(reasons.count, 10, "Reason count must be exactly 10")
        }
    }

    static func testProbe1_2_StrictSequentialUnwindingCanonical() {
        TestRunner.shared.test("CHALLENGE 1.2: Canonical Unwinding: 10 -> 9 -> ... -> 1 -> Throttle -> Play") {
            var manual = true
            var sysSleep = true
            var screensSleep = true
            var locked = true
            var saver = true
            var sessionActive = false
            var lpm = true
            var onBattery = true
            var visible = false
            var thermal = ProcessInfo.ThermalState.critical

            let config = EngineConfig(
                targetFrameRate: 60,
                throttledFrameRate: 30,
                pauseOnBattery: true,
                throttleOnBattery: true,
                pauseOnLowPowerMode: true,
                pauseOnScreenLock: true,
                pauseOnDisplaySleep: true,
                pauseWhenOccluded: true
            )

            func currentDecision() -> PlaybackDecision {
                StateEvaluator.evaluate(
                    manualPause: manual,
                    sleepLock: SleepLockState(
                        isSystemSleeping: sysSleep,
                        areScreensSleeping: screensSleep,
                        isScreenLocked: locked,
                        isScreensaverActive: saver,
                        isSessionActive: sessionActive
                    ),
                    power: PowerState(
                        source: onBattery ? .battery : .ac,
                        batteryLevel: onBattery ? 0.2 : 1.0,
                        isCharging: !onBattery,
                        isLowPowerModeEnabled: lpm,
                        thermalState: thermal
                    ),
                    isDisplayVisible: visible,
                    config: config
                )
            }

            // Step 0: 10 active
            guard case .pause(let r10) = currentDecision() else { throw TestFailure("Step 0 failed") }
            try assertEqual(r10.count, 10)

            // Step 1: clear manual -> 9 active
            manual = false
            guard case .pause(let r9) = currentDecision() else { throw TestFailure("Step 1 failed") }
            try assertEqual(r9.count, 9)
            try assertFalse(r9.contains(.userRequested))

            // Step 2: clear sysSleep -> 8 active
            sysSleep = false
            guard case .pause(let r8) = currentDecision() else { throw TestFailure("Step 2 failed") }
            try assertEqual(r8.count, 8)
            try assertFalse(r8.contains(.systemSleeping))

            // Step 3: clear screensSleep -> 7 active
            screensSleep = false
            guard case .pause(let r7) = currentDecision() else { throw TestFailure("Step 3 failed") }
            try assertEqual(r7.count, 7)
            try assertFalse(r7.contains(.screensSleeping))

            // Step 4: clear locked -> 6 active
            locked = false
            guard case .pause(let r6) = currentDecision() else { throw TestFailure("Step 4 failed") }
            try assertEqual(r6.count, 6)
            try assertFalse(r6.contains(.screenLocked))

            // Step 5: clear screensaver -> 5 active
            saver = false
            guard case .pause(let r5) = currentDecision() else { throw TestFailure("Step 5 failed") }
            try assertEqual(r5.count, 5)
            try assertFalse(r5.contains(.screensaverActive))

            // Step 6: clear session -> 4 active
            sessionActive = true
            guard case .pause(let r4) = currentDecision() else { throw TestFailure("Step 6 failed") }
            try assertEqual(r4.count, 4)
            try assertFalse(r4.contains(.sessionInactive))

            // Step 7: clear lpm -> 3 active
            lpm = false
            guard case .pause(let r3) = currentDecision() else { throw TestFailure("Step 7 failed") }
            try assertEqual(r3.count, 3)
            try assertFalse(r3.contains(.lowPowerMode))

            // Step 8: clear onBattery (plug into AC) -> 2 active
            onBattery = false
            guard case .pause(let r2) = currentDecision() else { throw TestFailure("Step 8 failed") }
            try assertEqual(r2.count, 2)
            try assertFalse(r2.contains(.onBattery))

            // Step 9: clear occlusion (display becomes visible) -> 1 active (.thermalPressure)
            visible = true
            guard case .pause(let r1) = currentDecision() else { throw TestFailure("Step 9 failed") }
            try assertEqual(r1.count, 1)
            try assertEqual(r1, [.thermalPressure])

            // Transition from Pause to Throttle: Drop thermal from .critical to .serious
            thermal = .serious
            let throttleDecision = currentDecision()
            try assertEqual(throttleDecision, .throttle(fps: 30, reasons: [.thermalPressure]), "Must transition to .throttle at .serious")

            // Transition from Throttle to Play: Drop thermal from .serious to .nominal
            thermal = .nominal
            let playDecision = currentDecision()
            try assertEqual(playDecision, .play(fps: 60), "Must transition to .play(60) at .nominal")
        }
    }

    static func testProbe1_3_StrictSequentialUnwindingReverse() {
        TestRunner.shared.test("CHALLENGE 1.3: Reverse Unwinding: Thermal & Occlusion first down to Manual Pause") {
            var manual = true
            var sysSleep = true
            var screensSleep = true
            var locked = true
            var saver = true
            var sessionActive = false
            var lpm = true
            var onBattery = true
            var visible = false
            var thermal = ProcessInfo.ThermalState.critical

            let config = EngineConfig(
                targetFrameRate: 60,
                throttledFrameRate: 30,
                pauseOnBattery: true,
                pauseOnLowPowerMode: true,
                pauseOnScreenLock: true,
                pauseOnDisplaySleep: true,
                pauseWhenOccluded: true
            )

            func currentDecision() -> PlaybackDecision {
                StateEvaluator.evaluate(
                    manualPause: manual,
                    sleepLock: SleepLockState(
                        isSystemSleeping: sysSleep,
                        areScreensSleeping: screensSleep,
                        isScreenLocked: locked,
                        isScreensaverActive: saver,
                        isSessionActive: sessionActive
                    ),
                    power: PowerState(
                        source: onBattery ? .battery : .ac,
                        batteryLevel: onBattery ? 0.5 : 1.0,
                        isCharging: !onBattery,
                        isLowPowerModeEnabled: lpm,
                        thermalState: thermal
                    ),
                    isDisplayVisible: visible,
                    config: config
                )
            }

            // 10 -> 9: Clear thermal to nominal
            thermal = .nominal
            guard case .pause(let r9) = currentDecision() else { throw TestFailure("Reverse step 1 failed") }
            try assertEqual(r9.count, 9)
            try assertFalse(r9.contains(.thermalPressure))

            // 9 -> 8: Clear occlusion
            visible = true
            guard case .pause(let r8) = currentDecision() else { throw TestFailure("Reverse step 2 failed") }
            try assertEqual(r8.count, 8)
            try assertFalse(r8.contains(.displayOccluded))

            // 8 -> 7: Clear battery
            onBattery = false
            guard case .pause(let r7) = currentDecision() else { throw TestFailure("Reverse step 3 failed") }
            try assertEqual(r7.count, 7)
            try assertFalse(r7.contains(.onBattery))

            // 7 -> 6: Clear Low Power Mode
            lpm = false
            guard case .pause(let r6) = currentDecision() else { throw TestFailure("Reverse step 4 failed") }
            try assertEqual(r6.count, 6)
            try assertFalse(r6.contains(.lowPowerMode))

            // 6 -> 5: Clear session inactive
            sessionActive = true
            guard case .pause(let r5) = currentDecision() else { throw TestFailure("Reverse step 5 failed") }
            try assertEqual(r5.count, 5)
            try assertFalse(r5.contains(.sessionInactive))

            // 5 -> 4: Clear screensaver
            saver = false
            guard case .pause(let r4) = currentDecision() else { throw TestFailure("Reverse step 6 failed") }
            try assertEqual(r4.count, 4)
            try assertFalse(r4.contains(.screensaverActive))

            // 4 -> 3: Clear screen lock
            locked = false
            guard case .pause(let r3) = currentDecision() else { throw TestFailure("Reverse step 7 failed") }
            try assertEqual(r3.count, 3)
            try assertFalse(r3.contains(.screenLocked))

            // 3 -> 2: Clear screens sleeping
            screensSleep = false
            guard case .pause(let r2) = currentDecision() else { throw TestFailure("Reverse step 8 failed") }
            try assertEqual(r2.count, 2)
            try assertFalse(r2.contains(.screensSleeping))

            // 2 -> 1: Clear system sleeping (only manual pause left)
            sysSleep = false
            guard case .pause(let r1) = currentDecision() else { throw TestFailure("Reverse step 9 failed") }
            try assertEqual(r1.count, 1)
            try assertEqual(r1, [.userRequested])

            // 1 -> 0: Clear manual pause -> .play(60)
            manual = false
            try assertEqual(currentDecision(), .play(fps: 60))
        }
    }

    static func testProbe1_4_AllTenConditionsIsolatedSingleReason() {
        TestRunner.shared.test("CHALLENGE 1.4: Exhaustive Single-Reason Isolation (All 10 Isolated)") {
            let config = EngineConfig(
                pauseOnBattery: true,
                pauseOnLowPowerMode: true,
                pauseOnScreenLock: true,
                pauseOnDisplaySleep: true,
                pauseWhenOccluded: true
            )

            let nominalSleepLock = MockSleepLockEventGenerator.normalActive()
            let nominalPower = MockPowerEventGenerator.ac()

            // 1. Manual Pause alone
            let d1 = StateEvaluator.evaluate(
                manualPause: true,
                sleepLock: nominalSleepLock,
                power: nominalPower,
                isDisplayVisible: true,
                config: config
            )
            try assertEqual(d1, .pause(reasons: [.userRequested]))

            // 2. System Sleep alone
            var sl2 = nominalSleepLock; sl2.isSystemSleeping = true
            let d2 = StateEvaluator.evaluate(manualPause: false, sleepLock: sl2, power: nominalPower, isDisplayVisible: true, config: config)
            try assertEqual(d2, .pause(reasons: [.systemSleeping]))

            // 3. Screens Sleep alone
            var sl3 = nominalSleepLock; sl3.areScreensSleeping = true
            let d3 = StateEvaluator.evaluate(manualPause: false, sleepLock: sl3, power: nominalPower, isDisplayVisible: true, config: config)
            try assertEqual(d3, .pause(reasons: [.screensSleeping]))

            // 4. Screen Lock alone
            var sl4 = nominalSleepLock; sl4.isScreenLocked = true
            let d4 = StateEvaluator.evaluate(manualPause: false, sleepLock: sl4, power: nominalPower, isDisplayVisible: true, config: config)
            try assertEqual(d4, .pause(reasons: [.screenLocked]))

            // 5. Screensaver alone
            var sl5 = nominalSleepLock; sl5.isScreensaverActive = true
            let d5 = StateEvaluator.evaluate(manualPause: false, sleepLock: sl5, power: nominalPower, isDisplayVisible: true, config: config)
            try assertEqual(d5, .pause(reasons: [.screensaverActive]))

            // 6. Session Inactive alone
            var sl6 = nominalSleepLock; sl6.isSessionActive = false
            let d6 = StateEvaluator.evaluate(manualPause: false, sleepLock: sl6, power: nominalPower, isDisplayVisible: true, config: config)
            try assertEqual(d6, .pause(reasons: [.sessionInactive]))

            // 7. Low Power Mode alone
            var p7 = nominalPower; p7.isLowPowerModeEnabled = true
            let d7 = StateEvaluator.evaluate(manualPause: false, sleepLock: nominalSleepLock, power: p7, isDisplayVisible: true, config: config)
            try assertEqual(d7, .pause(reasons: [.lowPowerMode]))

            // 8. On Battery alone
            var p8 = nominalPower; p8.source = .battery
            let d8 = StateEvaluator.evaluate(manualPause: false, sleepLock: nominalSleepLock, power: p8, isDisplayVisible: true, config: config)
            try assertEqual(d8, .pause(reasons: [.onBattery]))

            // 9. Critical Thermal alone
            var p9 = nominalPower; p9.thermalState = .critical
            let d9 = StateEvaluator.evaluate(manualPause: false, sleepLock: nominalSleepLock, power: p9, isDisplayVisible: true, config: config)
            try assertEqual(d9, .pause(reasons: [.thermalPressure]))

            // 10. Occluded alone
            let d10 = StateEvaluator.evaluate(manualPause: false, sleepLock: nominalSleepLock, power: nominalPower, isDisplayVisible: false, config: config)
            try assertEqual(d10, .pause(reasons: [.displayOccluded]))
        }
    }

    static func testProbe1_5_RandomizedPermutationUnwinding() {
        TestRunner.shared.test("CHALLENGE 1.5: 50 Randomized Permutation Unwindings from 10 to 0") {
            let config = EngineConfig(
                targetFrameRate: 60,
                throttledFrameRate: 30,
                pauseOnBattery: true,
                pauseOnLowPowerMode: true,
                pauseOnScreenLock: true,
                pauseOnDisplaySleep: true,
                pauseWhenOccluded: true
            )

            enum ConditionKind: Int, CaseIterable {
                case manual, sysSleep, screensSleep, locked, saver, session, lpm, battery, thermal, occluded
            }

            for seed in 1...50 {
                var activeConditions = Set(ConditionKind.allCases)
                let shuffledOrder = ConditionKind.allCases.shuffled()

                for (clearedCount, conditionToClear) in shuffledOrder.enumerated() {
                    // Evaluate with currently active conditions
                    let isManual = activeConditions.contains(.manual)
                    let sleepLock = SleepLockState(
                        isSystemSleeping: activeConditions.contains(.sysSleep),
                        areScreensSleeping: activeConditions.contains(.screensSleep),
                        isScreenLocked: activeConditions.contains(.locked),
                        isScreensaverActive: activeConditions.contains(.saver),
                        isSessionActive: !activeConditions.contains(.session)
                    )
                    let power = PowerState(
                        source: activeConditions.contains(.battery) ? .battery : .ac,
                        batteryLevel: activeConditions.contains(.battery) ? 0.3 : 1.0,
                        isCharging: !activeConditions.contains(.battery),
                        isLowPowerModeEnabled: activeConditions.contains(.lpm),
                        thermalState: activeConditions.contains(.thermal) ? .critical : .nominal
                    )
                    let isVisible = !activeConditions.contains(.occluded)

                    let decision = StateEvaluator.evaluate(
                        manualPause: isManual,
                        sleepLock: sleepLock,
                        power: power,
                        isDisplayVisible: isVisible,
                        config: config
                    )

                    let remainingCount = 10 - clearedCount
                    guard case .pause(let reasons) = decision else {
                        throw TestFailure("Seed \(seed): step \(clearedCount) with \(remainingCount) active reasons must be .pause, got: \(decision)")
                    }
                    try assertEqual(reasons.count, remainingCount, "Seed \(seed): reason count must match remaining active count")

                    // Clear condition
                    activeConditions.remove(conditionToClear)
                }

                // When all 10 are cleared, it must transition to .play
                let finalDecision = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: MockSleepLockEventGenerator.normalActive(),
                    power: MockPowerEventGenerator.ac(),
                    isDisplayVisible: true,
                    config: config
                )
                try assertEqual(finalDecision, .play(fps: 60), "Seed \(seed): Final state must be .play(60)")
            }
        }
    }

    // MARK: - Probe 2: Desktop Mac Hardware Invariance

    static func testProbe2_1_DesktopMacBaselineInvariance() {
        TestRunner.shared.test("CHALLENGE 2.1: Canonical Desktop Mac Baseline Invariance") {
            let config = EngineConfig(
                targetFrameRate: 60,
                throttledFrameRate: 30,
                pauseOnBattery: true,
                throttleOnBattery: true
            )
            // Desktop Mac: source = .ac, batteryLevel = nil, isCharging = false
            let desktopPower = PowerState(
                source: .ac,
                batteryLevel: nil,
                isCharging: false,
                isLowPowerModeEnabled: false,
                thermalState: .nominal
            )

            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: desktopPower,
                isDisplayVisible: true,
                config: config
            )

            try assertEqual(decision, .play(fps: 60), "Desktop Mac must never pause or throttle on battery policies")
        }
    }

    static func testProbe2_2_DesktopMacThermalInvariance() {
        TestRunner.shared.test("CHALLENGE 2.2: Desktop Mac Thermal Invariance (.nominal vs .fair)") {
            let config = EngineConfig(pauseOnBattery: true, throttleOnBattery: true)

            // 1. Desktop Mac at .nominal
            let powerNominal = PowerState(source: .ac, batteryLevel: nil, isCharging: false, thermalState: .nominal)
            let d1 = StateEvaluator.evaluate(manualPause: false, sleepLock: MockSleepLockEventGenerator.normalActive(), power: powerNominal, isDisplayVisible: true, config: config)
            try assertEqual(d1, .play(fps: 60))

            // 2. Desktop Mac at .fair (fair does not throttle)
            let powerFair = PowerState(source: .ac, batteryLevel: nil, isCharging: false, thermalState: .fair)
            let d2 = StateEvaluator.evaluate(manualPause: false, sleepLock: MockSleepLockEventGenerator.normalActive(), power: powerFair, isDisplayVisible: true, config: config)
            try assertEqual(d2, .play(fps: 60))
        }
    }

    static func testProbe2_3_DesktopMacMultiRefreshRates() {
        TestRunner.shared.test("CHALLENGE 2.3: Desktop Mac Multi-Refresh Rates (30, 60, 120, 144, 240)") {
            let targetFPSList = [30, 60, 120, 144, 240]
            let desktopPower = PowerState(source: .ac, batteryLevel: nil, isCharging: false, thermalState: .nominal)

            for fps in targetFPSList {
                let config = EngineConfig(
                    targetFrameRate: fps,
                    throttledFrameRate: 15,
                    pauseOnBattery: true,
                    throttleOnBattery: true
                )

                let decision = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: MockSleepLockEventGenerator.normalActive(),
                    power: desktopPower,
                    isDisplayVisible: true,
                    config: config
                )

                try assertEqual(decision, .play(fps: fps), "Desktop Mac must play at requested \(fps) FPS")
            }
        }
    }

    static func testProbe2_4_DesktopMac10kEvaluationFlurry() {
        TestRunner.shared.test("CHALLENGE 2.4: Desktop Mac 10,000 Evaluation Flurry (Determinism & Zero Mutation)") {
            let config = EngineConfig(targetFrameRate: 60, pauseOnBattery: true, throttleOnBattery: true)
            let desktopPower = PowerState(source: .ac, batteryLevel: nil, isCharging: false, thermalState: .nominal)
            let sleepLock = MockSleepLockEventGenerator.normalActive()

            let baseline = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: sleepLock,
                power: desktopPower,
                isDisplayVisible: true,
                config: config
            )

            for _ in 1...10_000 {
                let current = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: sleepLock,
                    power: desktopPower,
                    isDisplayVisible: true,
                    config: config
                )
                try assertEqual(current, baseline)
            }
        }
    }

    static func testProbe2_5_DesktopMacWithUPSPower() {
        TestRunner.shared.test("CHALLENGE 2.5: Desktop Mac Connected to UPS Power (.ups)") {
            let config = EngineConfig(
                pauseOnBattery: true,
                throttleOnBattery: true
            )
            let upsPower = PowerState(
                source: .ups,
                batteryLevel: nil,
                isCharging: false,
                thermalState: .nominal
            )

            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: upsPower,
                isDisplayVisible: true,
                config: config
            )

            // UPS is not laptop internal battery: isOnBattery is false
            try assertEqual(decision, .play(fps: 60), "UPS power source must not trigger battery throttling")
        }
    }

    // MARK: - Probe 3: Thermal Escalation Ladder & Hysteresis

    static func testProbe3_1_FullThermalEscalationLadderAndRecovery() {
        TestRunner.shared.test("CHALLENGE 3.1: Full Thermal Escalation Ladder & Recovery (AC Power)") {
            let config = EngineConfig(targetFrameRate: 60, throttledFrameRate: 30)
            let sleepLock = MockSleepLockEventGenerator.normalActive()

            func evaluateThermal(_ thermal: ProcessInfo.ThermalState) -> PlaybackDecision {
                StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: sleepLock,
                    power: PowerState(source: .ac, batteryLevel: 1.0, isCharging: true, thermalState: thermal),
                    isDisplayVisible: true,
                    config: config
                )
            }

            // 1. .nominal -> Play 60
            try assertEqual(evaluateThermal(.nominal), .play(fps: 60))

            // 2. Heat up to .fair -> Play 60 (no throttle)
            try assertEqual(evaluateThermal(.fair), .play(fps: 60))

            // 3. Heat up to .serious -> Throttle 30 (.thermalPressure)
            try assertEqual(evaluateThermal(.serious), .throttle(fps: 30, reasons: [.thermalPressure]))

            // 4. Heat up to .critical -> Pause (.thermalPressure)
            try assertEqual(evaluateThermal(.critical), .pause(reasons: [.thermalPressure]))

            // 5. Cool down to .serious -> Throttle 30 (.thermalPressure)
            try assertEqual(evaluateThermal(.serious), .throttle(fps: 30, reasons: [.thermalPressure]))

            // 6. Cool down to .fair -> Play 60
            try assertEqual(evaluateThermal(.fair), .play(fps: 60))

            // 7. Cool down to .nominal -> Play 60
            try assertEqual(evaluateThermal(.nominal), .play(fps: 60))
        }
    }

    static func testProbe3_2_ConcurrentThermalAndBatteryThrottling() {
        TestRunner.shared.test("CHALLENGE 3.2: Concurrent Thermal & Battery Throttling Interaction") {
            let config = EngineConfig(
                targetFrameRate: 60,
                throttledFrameRate: 24,
                pauseOnBattery: false,
                throttleOnBattery: true
            )
            let sleepLock = MockSleepLockEventGenerator.normalActive()

            func evaluate(thermal: ProcessInfo.ThermalState) -> PlaybackDecision {
                StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: sleepLock,
                    power: PowerState(source: .battery, batteryLevel: 0.5, isCharging: false, thermalState: thermal),
                    isDisplayVisible: true,
                    config: config
                )
            }

            // 1. On Battery at .nominal -> Throttled on battery alone
            try assertEqual(evaluate(thermal: .nominal), .throttle(fps: 24, reasons: [.onBattery]))

            // 2. On Battery at .fair -> Throttled on battery alone
            try assertEqual(evaluate(thermal: .fair), .throttle(fps: 24, reasons: [.onBattery]))

            // 3. On Battery at .serious -> Throttled on BOTH battery and thermal!
            try assertEqual(evaluate(thermal: .serious), .throttle(fps: 24, reasons: [.onBattery, .thermalPressure]))

            // 4. On Battery at .critical -> PAUSED for thermal pressure (Pause preempts throttle!)
            try assertEqual(evaluate(thermal: .critical), .pause(reasons: [.thermalPressure]))

            // 5. Recovery to .serious -> Throttled on BOTH again
            try assertEqual(evaluate(thermal: .serious), .throttle(fps: 24, reasons: [.onBattery, .thermalPressure]))

            // 6. Recovery to .nominal -> Throttled on battery alone
            try assertEqual(evaluate(thermal: .nominal), .throttle(fps: 24, reasons: [.onBattery]))
        }
    }

    static func testProbe3_3_RapidThermalFlapping1000Cycles() {
        TestRunner.shared.test("CHALLENGE 3.3: Rapid Thermal Flapping (1,000 Alternating Serious <-> Critical Cycles)") {
            let config = EngineConfig(targetFrameRate: 60, throttledFrameRate: 30)
            let sleepLock = MockSleepLockEventGenerator.normalActive()

            for i in 1...1000 {
                let state: ProcessInfo.ThermalState = (i % 2 == 1) ? .serious : .critical
                let decision = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: sleepLock,
                    power: PowerState(source: .ac, thermalState: state),
                    isDisplayVisible: true,
                    config: config
                )

                if state == .serious {
                    try assertEqual(decision, .throttle(fps: 30, reasons: [.thermalPressure]))
                } else {
                    try assertEqual(decision, .pause(reasons: [.thermalPressure]))
                }
            }
        }
    }

    // MARK: - Probe 4: Priority Matrix & Boundary Preemption

    static func testProbe4_1_FrameRateSanitizationClamp() {
        TestRunner.shared.test("CHALLENGE 4.1: Frame Rate Sanitization Boundaries & Safety Clamp") {
            // Negative and zero frame rates should clamp to >= 1
            let c1 = EngineConfig(targetFrameRate: 0, throttledFrameRate: -10)
            try assertEqual(c1.targetFrameRate, 1)
            try assertEqual(c1.throttledFrameRate, 1)

            // Throttled frame rate exceeding target frame rate should clamp to targetFrameRate
            let c2 = EngineConfig(targetFrameRate: 30, throttledFrameRate: 120)
            try assertEqual(c2.targetFrameRate, 30)
            try assertEqual(c2.throttledFrameRate, 30)

            let pSerious = MockPowerEventGenerator.thermalSerious()
            let decision = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: pSerious,
                isDisplayVisible: true,
                config: c2
            )
            try assertEqual(decision, .throttle(fps: 30, reasons: [.thermalPressure]))
        }
    }

    static func testProbe4_2_UnconditionalOverridesUnderAllFlagsDisabled() {
        TestRunner.shared.test("CHALLENGE 4.2: Unconditional Overrides Under All Optional Flags Disabled") {
            let disabledConfig = EngineConfig(
                pauseOnBattery: false,
                throttleOnBattery: false,
                pauseOnLowPowerMode: false,
                pauseOnScreenLock: false,
                pauseOnDisplaySleep: false,
                pauseWhenOccluded: false
            )

            // 1. Manual Pause is unconditional
            let d1 = StateEvaluator.evaluate(
                manualPause: true,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: MockPowerEventGenerator.ac(),
                isDisplayVisible: true,
                config: disabledConfig
            )
            try assertEqual(d1, .pause(reasons: [.userRequested]))

            // 2. Screensaver is unconditional
            let d2 = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.screensaver(),
                power: MockPowerEventGenerator.ac(),
                isDisplayVisible: true,
                config: disabledConfig
            )
            try assertEqual(d2, .pause(reasons: [.screensaverActive]))

            // 3. Session Inactive (Fast User Switching) is unconditional
            let d3 = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.sessionInactive(),
                power: MockPowerEventGenerator.ac(),
                isDisplayVisible: true,
                config: disabledConfig
            )
            try assertEqual(d3, .pause(reasons: [.sessionInactive]))

            // 4. Critical Thermal Pressure is unconditional
            let d4 = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: MockPowerEventGenerator.thermalCritical(),
                isDisplayVisible: true,
                config: disabledConfig
            )
            try assertEqual(d4, .pause(reasons: [.thermalPressure]))

            // 5. Serious Thermal Pressure is unconditional throttling
            let d5 = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: MockPowerEventGenerator.thermalSerious(),
                isDisplayVisible: true,
                config: disabledConfig
            )
            try assertEqual(d5, .throttle(fps: 30, reasons: [.thermalPressure]))
        }
    }

    static func testProbe4_3_MultiDisplayOcclusionIndependenceAndGlobalLock() {
        TestRunner.shared.test("CHALLENGE 4.3: 4-Display Occlusion Independence & Global Screen Lock Interleaving") {
            let config = EngineConfig(pauseOnScreenLock: true, pauseWhenOccluded: true)
            let displays: [CGDirectDisplayID: Bool] = [
                1: true,
                2: false,
                3: true,
                4: false
            ]

            // 1. Nominal state: Displays 1 & 3 play, Displays 2 & 4 pause
            let dNominal = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: MockPowerEventGenerator.ac(),
                displays: displays,
                config: config
            )
            try assertEqual(dNominal[1], .play(fps: 60))
            try assertEqual(dNominal[2], .pause(reasons: [.displayOccluded]))
            try assertEqual(dNominal[3], .play(fps: 60))
            try assertEqual(dNominal[4], .pause(reasons: [.displayOccluded]))

            // 2. Global Screen Lock arrives: All displays pause, but 2 & 4 have 2 reasons
            let dLocked = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.locked(),
                power: MockPowerEventGenerator.ac(),
                displays: displays,
                config: config
            )
            try assertEqual(dLocked[1], .pause(reasons: [.screenLocked]))
            try assertEqual(dLocked[2], .pause(reasons: [.screenLocked, .displayOccluded]))
            try assertEqual(dLocked[3], .pause(reasons: [.screenLocked]))
            try assertEqual(dLocked[4], .pause(reasons: [.screenLocked, .displayOccluded]))

            // 3. Screen Unlock: Displays 1 & 3 resume play, Displays 2 & 4 remain paused
            let dUnlocked = StateEvaluator.evaluate(
                manualPause: false,
                sleepLock: MockSleepLockEventGenerator.normalActive(),
                power: MockPowerEventGenerator.ac(),
                displays: displays,
                config: config
            )
            try assertEqual(dUnlocked[1], .play(fps: 60))
            try assertEqual(dUnlocked[2], .pause(reasons: [.displayOccluded]))
            try assertEqual(dUnlocked[3], .play(fps: 60))
            try assertEqual(dUnlocked[4], .pause(reasons: [.displayOccluded]))
        }
    }

    // MARK: - Probe 5: PowerObserver Stream & Lifecycle Probes

    static func testProbe5_1_PowerObserver10kDeduplication() {
        TestRunner.shared.test("CHALLENGE 5.1: PowerObserver 10,000 Redundant Notifications are Deduplicated") {
            let mockProvider = MockPowerSourceProvider()
            let observer = PowerObserver(provider: mockProvider)
            let delegate = MockPowerObserverDelegate()
            observer.delegate = delegate
            observer.start()

            // Fire 10,000 change notifications where the state has NOT changed
            for _ in 1...10_000 {
                mockProvider.delegate?.powerSourceProviderDidDetectChange(mockProvider)
            }

            try assertEqual(delegate.states.count, 0, "No duplicate callbacks must be emitted when state is unchanged")
            observer.stop()
        }
    }

    static func testProbe5_2_PowerObserverRapidLifecycleFlurry() {
        TestRunner.shared.test("CHALLENGE 5.2: PowerObserver 100 Rapid Start/Stop Lifecycle Cycles") {
            let mockProvider = MockPowerSourceProvider()
            let observer = PowerObserver(provider: mockProvider)

            for _ in 1...100 {
                observer.start()
                try assertTrue(observer.isObserving)
                try assertTrue(mockProvider.isMonitoring)

                observer.stop()
                try assertFalse(observer.isObserving)
                try assertFalse(mockProvider.isMonitoring)
            }
        }
    }

    static func testProbe5_3_PowerObserverRapidStateFlapping() {
        TestRunner.shared.test("CHALLENGE 5.3: PowerObserver 50 State Transitions with Battery Drain Simulation") {
            let mockProvider = MockPowerSourceProvider()
            let observer = PowerObserver(provider: mockProvider)
            let delegate = MockPowerObserverDelegate()
            observer.delegate = delegate
            observer.start()

            for step in 1...50 {
                let isOnBattery = (step % 2 == 1)
                let batteryLevel = max(0.01, 1.0 - (Double(step) * 0.018))
                let newState = PowerState(
                    source: isOnBattery ? .battery : .ac,
                    batteryLevel: isOnBattery ? batteryLevel : 1.0,
                    isCharging: !isOnBattery,
                    isLowPowerModeEnabled: isOnBattery && (batteryLevel < 0.2),
                    thermalState: .nominal
                )
                mockProvider.simulateChange(to: newState)
            }

            try assertEqual(delegate.states.count, 50, "Every unique state transition must be faithfully delivered")
            try assertEqual(observer.currentState, delegate.states.last)
            observer.stop()
        }
    }
}

// MARK: - Test Delegate for PowerObserver

@MainActor
public final class MockPowerObserverDelegate: PowerObserverDelegate {
    public var states: [PowerState] = []
    public var lastState: PowerState? { states.last }

    public init() {}

    public func powerStateDidChange(_ newState: PowerState) {
        states.append(newState)
    }

    public func reset() {
        states.removeAll()
    }
}

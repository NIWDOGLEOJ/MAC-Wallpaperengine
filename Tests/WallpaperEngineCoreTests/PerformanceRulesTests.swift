//
//  PerformanceRulesTests.swift
//  WallpaperEngineCoreTests
//
//  Unit tests for MemoryPressureMonitor, PerformanceRulesManager, and
//  StateEvaluator multi-condition decision matrix (fullscreen, games, idle, memory pressure).
//

import AppKit
import CoreGraphics
import Foundation
@testable import WallpaperEngineCore

@MainActor
public struct PerformanceRulesTests {
    public static func runAllTests() async {
        let runner = TestRunner.shared

        await runner.runSuite("Suite: Performance Rules & Advanced State Evaluator") {

            // Test 1: MemoryPressureMonitor Initialization
            runner.test("MemoryPressureMonitor initializes with normal level") {
                let monitor = MemoryPressureMonitor()
                try assertEqual(monitor.currentLevel, .normal, "Initial memory pressure is normal")
            }

            // Test 2: StateEvaluator Fullscreen App Per-Display Pausing
            runner.test("StateEvaluator pauses only displays with active fullscreen apps") {
                let display1: CGDirectDisplayID = 101
                let display2: CGDirectDisplayID = 102
                let displays: [CGDirectDisplayID: Bool] = [display1: true, display2: true]
                let config = EngineConfig()

                // Display 1 is covered by fullscreen app, Display 2 is not
                let fullscreen: Set<CGDirectDisplayID> = [display1]

                let decisions = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: SleepLockState(),
                    power: PowerState(),
                    displays: displays,
                    config: config,
                    fullscreenDisplays: fullscreen,
                    isGameActive: false,
                    isIdle: false,
                    memoryPressure: .normal
                )

                // display1 should be paused due to fullscreenApp
                if case .pause(let reasons) = decisions[display1] {
                    try assertTrue(reasons.contains(.fullscreenApp), "display1 paused due to fullscreenApp")
                } else {
                    try assertTrue(false, "display1 expected to be paused")
                }

                // display2 should remain playing
                if case .play(let fps) = decisions[display2] {
                    try assertEqual(fps, config.targetFrameRate, "display2 plays at targetFrameRate")
                } else {
                    try assertTrue(false, "display2 expected to be playing")
                }
            }

            // Test 3: StateEvaluator Game Detection Pausing
            runner.test("StateEvaluator pauses all displays when a game title is active") {
                let display1: CGDirectDisplayID = 201
                let display2: CGDirectDisplayID = 202
                let displays: [CGDirectDisplayID: Bool] = [display1: true, display2: true]
                let config = EngineConfig()

                let decisions = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: SleepLockState(),
                    power: PowerState(),
                    displays: displays,
                    config: config,
                    fullscreenDisplays: [],
                    isGameActive: true,
                    isIdle: false,
                    memoryPressure: .normal
                )

                for (id, decision) in decisions {
                    if case .pause(let reasons) = decision {
                        try assertTrue(reasons.contains(.gameActive), "Display \(id) paused with gameActive reason")
                    } else {
                        try assertTrue(false, "Display \(id) expected to be paused when game is active")
                    }
                }
            }

            // Test 4: StateEvaluator Desktop Idle Handling
            runner.test("StateEvaluator handles desktop idle state according to configuration") {
                let display: CGDirectDisplayID = 301
                let displays: [CGDirectDisplayID: Bool] = [display: true]
                let config = EngineConfig()

                // When not idle, normal playback
                let activeDecisions = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: SleepLockState(),
                    power: PowerState(),
                    displays: displays,
                    config: config,
                    fullscreenDisplays: [],
                    isGameActive: false,
                    isIdle: false,
                    memoryPressure: .normal
                )
                if case .play(let fps) = activeDecisions[display] {
                    try assertEqual(fps, config.targetFrameRate, "Continues normal playback when idle is false")
                } else {
                    try assertTrue(false, "Expected play when idle is false")
                }

                // When idle is true, throttles frame rate
                let idleDecisions = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: SleepLockState(),
                    power: PowerState(),
                    displays: displays,
                    config: config,
                    fullscreenDisplays: [],
                    isGameActive: false,
                    isIdle: true,
                    memoryPressure: .normal
                )
                if case .throttle(let fps, let reasons) = idleDecisions[display] {
                    try assertEqual(fps, config.throttledFrameRate, "Throttles to throttledFrameRate when idle")
                    try assertTrue(reasons.contains(.desktopIdle), "Throttled due to desktopIdle")
                } else {
                    try assertTrue(false, "Expected throttle when idle is true")
                }
            }

            // Test 5: StateEvaluator Critical Memory Pressure Pause
            runner.test("StateEvaluator pauses rendering under critical memory pressure") {
                let display: CGDirectDisplayID = 401
                let displays: [CGDirectDisplayID: Bool] = [display: true]
                let config = EngineConfig()

                let decisions = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: SleepLockState(),
                    power: PowerState(),
                    displays: displays,
                    config: config,
                    fullscreenDisplays: [],
                    isGameActive: false,
                    isIdle: false,
                    memoryPressure: .critical
                )

                if case .pause(let reasons) = decisions[display] {
                    try assertTrue(reasons.contains(.memoryPressure), "Pause reason is memoryPressure")
                } else {
                    try assertTrue(false, "Expected pause decision under critical memory pressure")
                }
            }

            // Test 6: PerformanceRulesManager Defaults & Delegates
            runner.test("PerformanceRulesManager exposes configurable thresholds and default states") {
                let rules = PerformanceRulesManager()
                try assertTrue(rules.pauseOnFullscreen, "Default pause on fullscreen is true")
                try assertTrue(rules.pauseOnGame, "Default pause on game is true")
                try assertFalse(rules.pauseOnIdle, "Default pause on idle is false")
                try assertEqual(rules.idleThresholdSeconds, 600, "Default idle threshold is 600s")
                try assertFalse(rules.isGameActive, "Initially not game active")
                try assertFalse(rules.isDesktopIdle, "Initially not desktop idle")
                try assertTrue(rules.fullscreenDisplays.isEmpty, "Initially no fullscreen displays")
            }

            // Test 7: Backwards-compatible 5-argument StateEvaluator invocation
            runner.test("StateEvaluator 5-argument evaluate maintains seamless backward compatibility") {
                let display: CGDirectDisplayID = 501
                let displays: [CGDirectDisplayID: Bool] = [display: true]
                let config = EngineConfig()

                let decisions = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: SleepLockState(),
                    power: PowerState(),
                    displays: displays,
                    config: config
                )

                if case .play(let fps) = decisions[display] {
                    try assertEqual(fps, config.targetFrameRate, "Plays at target frame rate")
                } else {
                    try assertTrue(false, "Expected play decision")
                }
            }

            // Test 8: Multi-Display Fullscreen Spatial Isolation (Zero Cross-Display False Positives)
            runner.test("PerformanceRulesManager evaluateFullscreenDisplays isolates fullscreen to matching display") {
                let rules = PerformanceRulesManager()
                let display1: CGDirectDisplayID = 1001
                let display2: CGDirectDisplayID = 1002

                let displayBoundsMap: [CGDirectDisplayID: CGRect] = [
                    display1: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                    display2: CGRect(x: 1920, y: 0, width: 1920, height: 1080)
                ]

                // Scenario A: Fullscreen window strictly on Display 1
                let windowOnDisplay1 = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
                let resultA = rules.evaluateFullscreenDisplays(windowRects: windowOnDisplay1, displayBoundsMap: displayBoundsMap)
                try assertTrue(resultA.contains(display1), "Display 1 detected as fullscreen")
                try assertFalse(resultA.contains(display2), "Display 2 is NOT marked as fullscreen when window is on Display 1")

                // Scenario B: Fullscreen window strictly on Display 2
                let windowOnDisplay2 = [CGRect(x: 1920, y: 0, width: 1920, height: 1080)]
                let resultB = rules.evaluateFullscreenDisplays(windowRects: windowOnDisplay2, displayBoundsMap: displayBoundsMap)
                try assertFalse(resultB.contains(display1), "Display 1 is NOT marked as fullscreen when window is on Display 2")
                try assertTrue(resultB.contains(display2), "Display 2 detected as fullscreen")

                // Scenario C: Non-fullscreen regular window (e.g. 1000x800)
                let regularWindow = [CGRect(x: 100, y: 100, width: 1000, height: 800)]
                let resultC = rules.evaluateFullscreenDisplays(windowRects: regularWindow, displayBoundsMap: displayBoundsMap)
                try assertTrue(resultC.isEmpty, "Neither display marked as fullscreen for regular window")
            }
        }
    }
}

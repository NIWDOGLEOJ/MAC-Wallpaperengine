//
//  M3SleepLockAndOcclusionChallengerTests.swift
//  WallpaperEngineCoreTests
//
//  Milestone 3 Adversarial Empirical Challenger Probes:
//  - Probe 1: Wake-into-lock edge cases (display wake vs active lock verification)
//  - Probe 2: Fast User Switching (session resignation, reactivation, console switching)
//  - Probe 3: Multi-display mixed occlusion (3 displays: D1 visible, D2 occluded, D3 visible)
//  - Probe 4: OcclusionManager registration & rapid space switching stress (50 transitions, ARC leak audit)
//

import AppKit
import CoreGraphics
import Foundation
@testable import WallpaperEngineCore

// MARK: - Weak Reference Tracking Helpers for Leak Probes

@MainActor
public final class WeakWindowBox {
    public weak var window: NSWindow?
    public init(_ window: NSWindow) {
        self.window = window
    }
}

@MainActor
public final class WeakOcclusionManagerBox {
    public weak var manager: OcclusionManager?
    public init(_ manager: OcclusionManager) {
        self.manager = manager
    }
}

// MARK: - Empirical Challenger Test Suite

@MainActor
public struct M3SleepLockAndOcclusionChallengerTests {

    public static func runAllTests() async {
        let runner = TestRunner.shared
        await runner.runSuite("Milestone 3 Challenger Suite: SleepLock & Occlusion Empirical Probes") {

            // =================================================================
            // PROBE 1: Wake-into-Lock Edge Case
            // =================================================================

            runner.test("CHALLENGE 1.1: Display Wake Notification While Session Locked Maintains isScreenLocked and Decision .pause([.screenLocked])") {
                let wsCenter = NotificationCenter()
                let session = MockSessionStateProvider(locked: true, onConsole: true)
                let initial = SleepLockState(areScreensSleeping: true, isScreenLocked: true)
                let observer = SleepLockObserver(
                    initialState: initial,
                    workspaceNotificationCenter: wsCenter,
                    sessionProvider: session
                )
                let delegate = MockSleepLockObserverDelegate()
                observer.delegate = delegate
                observer.start()

                try assertTrue(observer.currentState.areScreensSleeping, "Screens should initially be sleeping")
                try assertTrue(observer.currentState.isScreenLocked, "Screen should initially be locked")

                // Fire screensDidWakeNotification
                wsCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)

                try assertFalse(observer.currentState.areScreensSleeping, "Screens sleeping flag must be cleared on display wake")
                try assertTrue(observer.currentState.isScreenLocked, "Screen lock MUST remain true on display wake when session is locked")

                // Evaluate consolidated decision with StateEvaluator
                let config = EngineConfig()
                let power = MockPowerEventGenerator.ac()
                let decision = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: observer.currentState,
                    power: power,
                    isDisplayVisible: true,
                    config: config
                )

                try assertEqual(decision, .pause(reasons: [.screenLocked]), "Playback must remain strictly paused with reason .screenLocked")
            }

            runner.test("CHALLENGE 1.2: System Wake (didWakeNotification) While Session Locked Synchronously Verifies Lock State") {
                let wsCenter = NotificationCenter()
                let session = MockSessionStateProvider(locked: true, onConsole: true)
                let initial = SleepLockState(isSystemSleeping: true, isScreenLocked: false) // lock state initially out-of-date
                let observer = SleepLockObserver(
                    initialState: initial,
                    workspaceNotificationCenter: wsCenter,
                    sessionProvider: session
                )
                observer.start()

                // Trigger didWakeNotification: implementation must query sessionProvider synchronously
                wsCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

                try assertFalse(observer.currentState.isSystemSleeping, "isSystemSleeping must be false after didWakeNotification")
                try assertTrue(observer.currentState.isScreenLocked, "Observer must synchronously probe sessionProvider and set isScreenLocked = true")

                let decision = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: observer.currentState,
                    power: MockPowerEventGenerator.ac(),
                    isDisplayVisible: true,
                    config: EngineConfig()
                )
                try assertEqual(decision, .pause(reasons: [.screenLocked]))
            }

            runner.test("CHALLENGE 1.3: Rapid Interleaved Wake Sequence (Screens Wake + System Wake) Under Active Lock") {
                let wsCenter = NotificationCenter()
                let session = MockSessionStateProvider(locked: true, onConsole: true)
                let initial = SleepLockState(isSystemSleeping: true, areScreensSleeping: true, isScreenLocked: true)
                let observer = SleepLockObserver(
                    initialState: initial,
                    workspaceNotificationCenter: wsCenter,
                    sessionProvider: session
                )
                let delegate = MockSleepLockObserverDelegate()
                observer.delegate = delegate
                observer.start()

                // Burst of wake notifications in rapid sequence
                for _ in 0..<10 {
                    wsCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
                    wsCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
                }

                try assertFalse(observer.currentState.isSystemSleeping, "isSystemSleeping must be false")
                try assertFalse(observer.currentState.areScreensSleeping, "areScreensSleeping must be false")
                try assertTrue(observer.currentState.isScreenLocked, "isScreenLocked must remain true across entire burst")

                let decision = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: observer.currentState,
                    power: MockPowerEventGenerator.ac(),
                    isDisplayVisible: true,
                    config: EngineConfig()
                )
                try assertEqual(decision, .pause(reasons: [.screenLocked]))
            }

            runner.test("CHALLENGE 1.4: Darwin Screen Unlock Following Wake-Into-Lock Seamlessly Unwinds to .play(60)") {
                let wsCenter = NotificationCenter()
                let darwin = MockDarwinNotificationProvider()
                let session = MockSessionStateProvider(locked: true, onConsole: true)
                let initial = SleepLockState(areScreensSleeping: true, isScreenLocked: true)
                let observer = SleepLockObserver(
                    initialState: initial,
                    workspaceNotificationCenter: wsCenter,
                    darwinProvider: darwin,
                    sessionProvider: session
                )
                observer.start()

                // 1. Wake displays
                wsCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
                try assertTrue(observer.currentState.isScreenLocked)
                var decision = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: observer.currentState,
                    power: MockPowerEventGenerator.ac(),
                    isDisplayVisible: true,
                    config: EngineConfig()
                )
                try assertEqual(decision, .pause(reasons: [.screenLocked]))

                // 2. User successfully authenticates -> Darwin unlock notification arrives
                session.locked = false
                darwin.simulateNotification("com.apple.screenIsUnlocked")

                try assertFalse(observer.currentState.isScreenLocked, "Screen lock flag must clear on unlock notification")

                decision = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: observer.currentState,
                    power: MockPowerEventGenerator.ac(),
                    isDisplayVisible: true,
                    config: EngineConfig()
                )
                try assertEqual(decision, .play(fps: 60), "Decision must immediately transition to .play(60)")
            }

            runner.test("CHALLENGE 1.5: Wake-Into-Lock with pauseOnScreenLock Disabled Strictly Respects User Preference") {
                let wsCenter = NotificationCenter()
                let session = MockSessionStateProvider(locked: true, onConsole: true)
                let initial = SleepLockState(areScreensSleeping: true, isScreenLocked: true)
                let observer = SleepLockObserver(
                    initialState: initial,
                    workspaceNotificationCenter: wsCenter,
                    sessionProvider: session
                )
                observer.start()

                wsCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
                try assertTrue(observer.currentState.isScreenLocked)

                // User preference explicitly disables pausing on screen lock
                let customConfig = EngineConfig(pauseOnScreenLock: false)
                let decision = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: observer.currentState,
                    power: MockPowerEventGenerator.ac(),
                    isDisplayVisible: true,
                    config: customConfig
                )
                try assertEqual(decision, .play(fps: 60), "When pauseOnScreenLock is disabled, engine must play even if locked")
            }

            // =================================================================
            // PROBE 2: Fast User Switching
            // =================================================================

            runner.test("CHALLENGE 2.1: Session Resignation Immediately Emits .sessionInactive and Halts Playback") {
                let wsCenter = NotificationCenter()
                let observer = SleepLockObserver(workspaceNotificationCenter: wsCenter)
                let delegate = MockSleepLockObserverDelegate()
                observer.delegate = delegate
                observer.start()

                try assertTrue(observer.currentState.isSessionActive, "Session should be active by default")

                // User initiates Fast User Switch out
                wsCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)

                try assertFalse(observer.currentState.isSessionActive, "isSessionActive must transition to false")
                try assertEqual(delegate.states.count, 1, "Delegate must be called on resignation")
                try assertFalse(delegate.lastState!.isSessionActive, "Delegate state must reflect inactive session")

                let decision = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: observer.currentState,
                    power: MockPowerEventGenerator.ac(),
                    isDisplayVisible: true,
                    config: EngineConfig()
                )
                try assertEqual(decision, .pause(reasons: [.sessionInactive]), "Decision must strictly be .sessionInactive")
            }

            runner.test("CHALLENGE 2.2: Session Reactivation with Unlocked Console Session Resumes Active Playback (.play)") {
                let wsCenter = NotificationCenter()
                let session = MockSessionStateProvider(locked: false, onConsole: true)
                let initial = SleepLockState(isScreenLocked: false, isSessionActive: false)
                let observer = SleepLockObserver(
                    initialState: initial,
                    workspaceNotificationCenter: wsCenter,
                    sessionProvider: session
                )
                let delegate = MockSleepLockObserverDelegate()
                observer.delegate = delegate
                observer.start()

                // User returns to session
                wsCenter.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

                try assertTrue(observer.currentState.isSessionActive, "isSessionActive must transition to true")
                try assertFalse(observer.currentState.isScreenLocked, "isScreenLocked must be false")

                let decision = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: observer.currentState,
                    power: MockPowerEventGenerator.ac(),
                    isDisplayVisible: true,
                    config: EngineConfig()
                )
                try assertEqual(decision, .play(fps: 60), "Engine must resume normal playback at 60 FPS")
            }

            runner.test("CHALLENGE 2.3: Session Reactivation with Screen Locked Transitions Reason to .screenLocked") {
                let wsCenter = NotificationCenter()
                let session = MockSessionStateProvider(locked: true, onConsole: true) // screen is locked on return
                let initial = SleepLockState(isScreenLocked: false, isSessionActive: false)
                let observer = SleepLockObserver(
                    initialState: initial,
                    workspaceNotificationCenter: wsCenter,
                    sessionProvider: session
                )
                observer.start()

                // User switches back, but is on the lock/password screen
                wsCenter.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

                try assertTrue(observer.currentState.isSessionActive, "Session is now on-console")
                try assertTrue(observer.currentState.isScreenLocked, "Session lock must be synchronously detected")

                let decision = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: observer.currentState,
                    power: MockPowerEventGenerator.ac(),
                    isDisplayVisible: true,
                    config: EngineConfig()
                )
                try assertEqual(decision, .pause(reasons: [.screenLocked]), "Decision must transition from .sessionInactive to .screenLocked")
            }

            runner.test("CHALLENGE 2.4: Fast User Switching Flapping Stress (50 Iterations) Maintains Concurrency & State Integrity") {
                let wsCenter = NotificationCenter()
                let session = MockSessionStateProvider(locked: false, onConsole: true)
                let observer = SleepLockObserver(
                    workspaceNotificationCenter: wsCenter,
                    sessionProvider: session
                )
                let delegate = MockSleepLockObserverDelegate()
                observer.delegate = delegate
                observer.start()

                let iterations = 25
                for _ in 0..<iterations {
                    wsCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
                    wsCenter.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
                }

                try assertEqual(delegate.states.count, iterations * 2, "Delegate must receive exactly 50 state changes")
                try assertTrue(observer.currentState.isSessionActive, "Final state must be active")

                let decision = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: observer.currentState,
                    power: MockPowerEventGenerator.ac(),
                    isDisplayVisible: true,
                    config: EngineConfig()
                )
                try assertEqual(decision, .play(fps: 60))
            }

            runner.test("CHALLENGE 2.5: Session Resignation During Battery Throttling Transitions from .throttle to .pause") {
                let wsCenter = NotificationCenter()
                let observer = SleepLockObserver(workspaceNotificationCenter: wsCenter)
                observer.start()

                let batteryPower = MockPowerEventGenerator.battery(isCharging: false)
                let throttleConfig = EngineConfig(pauseOnBattery: false, throttleOnBattery: true)

                // Before resignation: should be throttled to 30 FPS on battery
                var decision = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: observer.currentState,
                    power: batteryPower,
                    isDisplayVisible: true,
                    config: throttleConfig
                )
                try assertEqual(decision, .throttle(fps: 30, reasons: [.onBattery]))

                // User switches away
                wsCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)

                // Now must pause unconditionally with .sessionInactive (Tier 1 pause overrides Tier 2 throttle)
                decision = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: observer.currentState,
                    power: batteryPower,
                    isDisplayVisible: true,
                    config: throttleConfig
                )
                try assertEqual(decision, .pause(reasons: [.sessionInactive]))
            }

            // =================================================================
            // PROBE 3: Multi-Display Mixed Occlusion
            // =================================================================

            runner.test("CHALLENGE 3.1: 3-Display Mixed Occlusion: D1 & D3 Play While D2 is Paused for .displayOccluded") {
                let manager = OcclusionManager()
                manager.registerDisplay(1, isVisible: true)
                manager.registerDisplay(2, isVisible: false)
                manager.registerDisplay(3, isVisible: true)

                try assertTrue(manager.isDisplayVisible(1))
                try assertFalse(manager.isDisplayVisible(2))
                try assertTrue(manager.isDisplayVisible(3))

                let config = EngineConfig(pauseWhenOccluded: true)
                let sleepLock = MockSleepLockEventGenerator.normalActive()
                let power = MockPowerEventGenerator.ac()

                // Batch evaluation
                let decisions = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: sleepLock,
                    power: power,
                    displays: manager.displayVisibility,
                    config: config
                )

                try assertEqual(decisions[1], .play(fps: 60), "Display 1 must play at 60 FPS")
                try assertEqual(decisions[2], .pause(reasons: [.displayOccluded]), "Display 2 must be paused with .displayOccluded")
                try assertEqual(decisions[3], .play(fps: 60), "Display 3 must play at 60 FPS")
            }

            runner.test("CHALLENGE 3.2: Dynamic Occlusion State Migration Across 3 Displays") {
                let manager = OcclusionManager()
                let delegate = MockOcclusionManagerDelegate()
                manager.delegate = delegate

                manager.registerDisplay(1, isVisible: true)
                manager.registerDisplay(2, isVisible: false)
                manager.registerDisplay(3, isVisible: true)

                let config = EngineConfig()
                let sleepLock = MockSleepLockEventGenerator.normalActive()
                let power = MockPowerEventGenerator.ac()

                // Move occluded window from Display 2 to Display 1
                manager.setDisplayVisibility(2, isVisible: true)
                manager.setDisplayVisibility(1, isVisible: false)

                try assertEqual(delegate.events.count, 2, "Delegate must capture 2 occlusion transitions")

                let decisions = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: sleepLock,
                    power: power,
                    displays: manager.displayVisibility,
                    config: config
                )

                try assertEqual(decisions[1], .pause(reasons: [.displayOccluded]), "Display 1 now paused")
                try assertEqual(decisions[2], .play(fps: 60), "Display 2 now playing")
                try assertEqual(decisions[3], .play(fps: 60), "Display 3 continues playing")
            }

            runner.test("CHALLENGE 3.3: Global Battery Pause Overlaid on Occluded Display 2 and Resumption Isolation") {
                let manager = OcclusionManager()
                manager.registerDisplay(1, isVisible: true)
                manager.registerDisplay(2, isVisible: false)
                manager.registerDisplay(3, isVisible: true)

                let config = EngineConfig(pauseOnBattery: true, pauseWhenOccluded: true)
                let sleepLock = MockSleepLockEventGenerator.normalActive()
                let batteryPower = MockPowerEventGenerator.battery()

                // While D2 is occluded, battery unplug occurs
                let decisionsOnBattery = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: sleepLock,
                    power: batteryPower,
                    displays: manager.displayVisibility,
                    config: config
                )

                try assertEqual(decisionsOnBattery[1], .pause(reasons: [.onBattery]))
                try assertEqual(decisionsOnBattery[2], .pause(reasons: [.onBattery, .displayOccluded]), "Display 2 accumulates both reasons")
                try assertEqual(decisionsOnBattery[3], .pause(reasons: [.onBattery]))

                // AC power restored
                let decisionsOnAC = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: sleepLock,
                    power: MockPowerEventGenerator.ac(),
                    displays: manager.displayVisibility,
                    config: config
                )

                try assertEqual(decisionsOnAC[1], .play(fps: 60), "Display 1 immediately resumes on AC")
                try assertEqual(decisionsOnAC[2], .pause(reasons: [.displayOccluded]), "Display 2 safely remains paused for occlusion only")
                try assertEqual(decisionsOnAC[3], .play(fps: 60), "Display 3 immediately resumes on AC")
            }

            runner.test("CHALLENGE 3.4: EngineConfig pauseWhenOccluded = false Allows Occluded Display to Play at 60 FPS") {
                let manager = OcclusionManager()
                manager.registerDisplay(1, isVisible: true)
                manager.registerDisplay(2, isVisible: false)
                manager.registerDisplay(3, isVisible: true)

                let config = EngineConfig(pauseWhenOccluded: false)
                let decisions = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: MockSleepLockEventGenerator.normalActive(),
                    power: MockPowerEventGenerator.ac(),
                    displays: manager.displayVisibility,
                    config: config
                )

                try assertEqual(decisions[1], .play(fps: 60))
                try assertEqual(decisions[2], .play(fps: 60), "When pauseWhenOccluded is false, Display 2 must play despite occlusion")
                try assertEqual(decisions[3], .play(fps: 60))
            }

            runner.test("CHALLENGE 3.5: Unregistering Occluded Display Restores Unregistered Visible Fallback") {
                let manager = OcclusionManager()
                manager.registerDisplay(2, isVisible: false)
                try assertFalse(manager.isDisplayVisible(2))

                manager.unregisterDisplay(2)
                try assertTrue(manager.isDisplayVisible(2), "Unregistered display must return default fallback true")

                let decision = StateEvaluator.evaluate(
                    manualPause: false,
                    sleepLock: MockSleepLockEventGenerator.normalActive(),
                    power: MockPowerEventGenerator.ac(),
                    isDisplayVisible: manager.isDisplayVisible(2),
                    config: EngineConfig()
                )
                try assertEqual(decision, .play(fps: 60))
            }

            // =================================================================
            // PROBE 4: OcclusionManager Registration & Rapid Space Switching Stress
            // =================================================================

            runner.test("CHALLENGE 4.1: 50 Rapid Space Transition Sweeps Under Multi-Display Load Without State Desync") {
                let wsCenter = NotificationCenter()
                let manager = OcclusionManager(workspaceNotificationCenter: wsCenter)

                // Register 4 mock desktop windows across displays
                let d1 = MockDesktopWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 101)
                let d2 = MockDesktopWindow(frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440), displayID: 102)
                let d3 = MockDesktopWindow(frame: CGRect(x: 4480, y: 0, width: 1920, height: 1080), displayID: 103)
                let d4 = MockDesktopWindow(frame: CGRect(x: 6400, y: 0, width: 3840, height: 2160), displayID: 104)

                manager.registerWindow(d1)
                manager.registerWindow(d2)
                manager.registerWindow(d3)
                manager.registerWindow(d4)

                try assertEqual(manager.displayVisibility.count, 4)

                // Fire 50 space transition notifications in rapid succession
                for _ in 0..<50 {
                    wsCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
                }

                // Verify all 4 displays continue to be correctly tracked
                try assertTrue(manager.isDisplayVisible(101))
                try assertTrue(manager.isDisplayVisible(102))
                try assertTrue(manager.isDisplayVisible(103))
                try assertTrue(manager.isDisplayVisible(104))
                try assertEqual(manager.displayVisibility.count, 4)
            }

            runner.test("CHALLENGE 4.2: Interleaved Display Registration and Space Switching Without Collision") {
                let wsCenter = NotificationCenter()
                let manager = OcclusionManager(workspaceNotificationCenter: wsCenter)

                for i: CGDirectDisplayID in 1...20 {
                    let win = MockDesktopWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600), displayID: i)
                    manager.registerWindow(win)
                    wsCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
                }

                try assertEqual(manager.displayVisibility.count, 20, "All 20 displays must be tracked concurrently")

                // Unregister 10 displays
                for i: CGDirectDisplayID in 1...10 {
                    manager.unregisterDisplay(i)
                }

                try assertEqual(manager.displayVisibility.count, 10, "10 displays must remain after unregistration")
                wsCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
                try assertEqual(manager.displayVisibility.count, 10, "Sweep must not resurrect unregistered displays")
            }

            runner.test("CHALLENGE 4.3: Unregistering Display Removes Notification Observer and Leaves 0 ARC Leaks") {
                let notificationCenter = NotificationCenter()
                let wsCenter = NotificationCenter()
                let manager = OcclusionManager(
                    notificationCenter: notificationCenter,
                    workspaceNotificationCenter: wsCenter
                )

                var weakBox: WeakWindowBox?

                autoreleasepool {
                    let window = NSWindow(
                        contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                        styleMask: [.borderless],
                        backing: .buffered,
                        defer: false
                    )
                    weakBox = WeakWindowBox(window)

                    manager.registerWindow(window, for: 55)
                    try? assertTrue(weakBox?.window != nil, "Window must be retained while registered")

                    // Unregister display
                    manager.unregisterDisplay(55)
                }

                // Window is released by manager and local scope
                try assertNil(weakBox?.window, "NSWindow must be fully deallocated with zero memory leaks after unregisterDisplay")
            }

            runner.test("CHALLENGE 4.4: OcclusionManager Teardown Deregisters Workspace Space Observer Without Leaks") {
                let wsCenter = NotificationCenter()
                var weakManagerBox: WeakOcclusionManagerBox?

                autoreleasepool {
                    let manager = OcclusionManager(workspaceNotificationCenter: wsCenter)
                    weakManagerBox = WeakOcclusionManagerBox(manager)

                    manager.registerDisplay(10, isVisible: true)
                    wsCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
                    try? assertTrue(weakManagerBox?.manager != nil, "Manager must exist in scope")
                }

                // Verify deallocation
                try assertNil(weakManagerBox?.manager, "OcclusionManager must deallocate cleanly with 0 leaks")

                // Post space change after deallocation: should not crash or trigger dead callbacks
                wsCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            }

            runner.test("CHALLENGE 4.5: Orphan Notification Immunity: Post-Unregistration Events Do Not Fire Delegate") {
                let notificationCenter = NotificationCenter()
                let manager = OcclusionManager(notificationCenter: notificationCenter)
                let delegate = MockOcclusionManagerDelegate()
                manager.delegate = delegate

                let window = NSWindow(
                    contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )

                manager.registerWindow(window, for: 99)
                manager.unregisterDisplay(99)

                // Post window occlusion notification after display has been unregistered
                notificationCenter.post(
                    name: NSWindow.didChangeOcclusionStateNotification,
                    object: window
                )

                try assertEqual(delegate.events.count, 0, "No delegate callbacks should be delivered for unregistered displays")
            }
        }
    }
}

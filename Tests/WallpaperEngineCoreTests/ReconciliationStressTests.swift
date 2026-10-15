//
//  ReconciliationStressTests.swift
//  WallpaperEngineCoreTests
//
//  Milestone 1 Empirical Challenge & Stress Probes:
//  - High-frequency screen parameter notification spam (debouncing & task lifecycle)
//  - Rapid simulated monitor connect/disconnect cycles (zero orphans & memory leak verification)
//  - Simulated display resolution change (pointer identity preservation & zero flicker)
//

import AppKit
import CoreGraphics
import Foundation
import QuartzCore
@testable import WallpaperEngineCore

@MainActor
public struct ReconciliationStressTests {

    public static func runAllTests() async {
        let runner = TestRunner.shared

        await runner.runSuite("Suite 8: Empirical Stress Probes & Adversarial Challenge") {

            // =================================================================
            // PROBE 1: High-Frequency Notification Spam & Debounce Verification
            // =================================================================

            await runner.testAsync("PROBE 1.1: 50 Burst Notifications in 10ms Coalesce Deterministically") {
                final class SpamTracker: ScreenManagerDelegate {
                    var callCount = 0
                    var detectedScreens: [ScreenDescriptor] = []

                    func screenManager(_ manager: ScreenManagerProtocol, didDetectScreenChanges screens: [ScreenDescriptor]) {
                        callCount += 1
                        detectedScreens = screens
                    }
                }

                let tracker = SpamTracker()
                let manager = ScreenManager(debounceDuration: 0.1) // 100ms debouncing
                manager.delegate = tracker
                manager.startMonitoring()

                // Fire 50 notifications within ~10ms (one every 0.2ms)
                for _ in 0..<50 {
                    NotificationCenter.default.post(
                        name: NSApplication.didChangeScreenParametersNotification,
                        object: nil
                    )
                    try await Task.sleep(nanoseconds: 200_000) // 0.2ms
                }

                // Verify that while still within the 100ms debounce window, 0 callbacks have fired
                try assertEqual(tracker.callCount, 0, "No delegate callback should fire before the 100ms debounce window expires")

                // Wait 160ms for debounce timer to expire
                try await Task.sleep(nanoseconds: 160_000_000)

                // Must coalesce into exactly 1 invocation
                try assertEqual(tracker.callCount, 1, "50 burst notifications must coalesce into exactly 1 delegate invocation")

                manager.stopMonitoring()
            }

            await runner.testAsync("PROBE 1.2: Multi-Threaded Concurrent Notification Spam (100 Events Across 4 Tasks)") {
                final class MultiThreadTracker: ScreenManagerDelegate {
                    var callCount = 0

                    func screenManager(_ manager: ScreenManagerProtocol, didDetectScreenChanges screens: [ScreenDescriptor]) {
                        callCount += 1
                    }
                }

                let tracker = MultiThreadTracker()
                let manager = ScreenManager(debounceDuration: 0.08) // 80ms debounce
                manager.delegate = tracker
                manager.startMonitoring()

                // Launch 4 concurrent tasks posting 25 notifications each
                await withTaskGroup(of: Void.self) { group in
                    for _ in 0..<4 {
                        group.addTask {
                            for _ in 0..<25 {
                                NotificationCenter.default.post(
                                    name: NSApplication.didChangeScreenParametersNotification,
                                    object: nil
                                )
                                try? await Task.sleep(nanoseconds: 300_000)
                            }
                        }
                    }
                }

                // Allow debounce timer to settle
                try await Task.sleep(nanoseconds: 150_000_000)

                try assertEqual(tracker.callCount, 1, "Concurrent multi-threaded notification storm must coalesce into 1 invocation")

                manager.stopMonitoring()
            }

            await runner.testAsync("PROBE 1.3: Continuous Notification Flood Resets Debounce Window") {
                final class FloodTracker: ScreenManagerDelegate {
                    var callCount = 0

                    func screenManager(_ manager: ScreenManagerProtocol, didDetectScreenChanges screens: [ScreenDescriptor]) {
                        callCount += 1
                    }
                }

                let tracker = FloodTracker()
                let manager = ScreenManager(debounceDuration: 0.15) // 150ms debounce
                manager.delegate = tracker
                manager.startMonitoring()

                // Send 1 notification every 10ms for 100ms (10 notifications total)
                // Since 10ms << 150ms debounce duration, the timer should repeatedly reset
                for _ in 0..<10 {
                    NotificationCenter.default.post(
                        name: NSApplication.didChangeScreenParametersNotification,
                        object: nil
                    )
                    try await Task.sleep(nanoseconds: 10_000_000)
                    try assertEqual(tracker.callCount, 0, "Timer must reset on each incoming notification during flood")
                }

                // Now stop posting and wait for the trailing edge to settle (150ms + 70ms)
                try await Task.sleep(nanoseconds: 220_000_000)

                try assertEqual(tracker.callCount, 1, "Exactly 1 trailing edge callback must fire after flood subsides")

                manager.stopMonitoring()
            }

            await runner.testAsync("PROBE 1.4: In-Flight Debounce Task Cancelled Promptly on StopMonitoring") {
                final class CancelTracker: ScreenManagerDelegate {
                    var callCount = 0

                    func screenManager(_ manager: ScreenManagerProtocol, didDetectScreenChanges screens: [ScreenDescriptor]) {
                        callCount += 1
                    }
                }

                let tracker = CancelTracker()
                let manager = ScreenManager(debounceDuration: 0.1) // 100ms debounce
                manager.delegate = tracker
                manager.startMonitoring()

                // Trigger debounce
                NotificationCenter.default.post(
                    name: NSApplication.didChangeScreenParametersNotification,
                    object: nil
                )

                // Wait 20ms into the 100ms window, then stop monitoring
                try await Task.sleep(nanoseconds: 20_000_000)
                manager.stopMonitoring()

                // Wait remaining 150ms
                try await Task.sleep(nanoseconds: 150_000_000)

                try assertEqual(tracker.callCount, 0, "No delegate callback must fire if stopMonitoring() cancelled the in-flight task")
            }

            await runner.testAsync("PROBE 1.5: 100 Rapid Notifications in 20ms Coalesce Deterministically to 1 Invocation") {
                final class RapidTracker: ScreenManagerDelegate {
                    var callCount = 0
                    func screenManager(_ manager: ScreenManagerProtocol, didDetectScreenChanges screens: [ScreenDescriptor]) {
                        callCount += 1
                    }
                }

                let tracker = RapidTracker()
                let manager = ScreenManager(debounceDuration: 0.1)
                manager.delegate = tracker
                manager.startMonitoring()

                for _ in 0..<100 {
                    NotificationCenter.default.post(
                        name: NSApplication.didChangeScreenParametersNotification,
                        object: nil
                    )
                    try await Task.sleep(nanoseconds: 200_000)
                }

                try assertEqual(tracker.callCount, 0, "No delegate callback should fire before debounce expiration")
                try await Task.sleep(nanoseconds: 160_000_000)
                try assertEqual(tracker.callCount, 1, "100 rapid notifications in 20ms must coalesce into exactly 1 invocation")
                manager.stopMonitoring()
            }

            await runner.testAsync("PROBE 1.6: Single Delegate Callback Invocation (Redundant screenManagerDidDetectChanges Suppressed)") {
                final class DualDelegateTracker: ScreenManagerDelegate {
                    var primaryCount = 0
                    var secondaryCount = 0
                    func screenManager(_ manager: ScreenManagerProtocol, didDetectScreenChanges screens: [ScreenDescriptor]) {
                        primaryCount += 1
                    }
                    func screenManagerDidDetectChanges(screens: [ScreenDescriptor]) {
                        secondaryCount += 1
                    }
                }

                let tracker = DualDelegateTracker()
                let manager = ScreenManager(debounceDuration: 0.05)
                manager.delegate = tracker
                manager.startMonitoring()

                NotificationCenter.default.post(
                    name: NSApplication.didChangeScreenParametersNotification,
                    object: nil
                )
                try await Task.sleep(nanoseconds: 100_000_000)

                try assertEqual(tracker.primaryCount, 1, "Primary delegate method must be called exactly once")
                try assertEqual(tracker.secondaryCount, 0, "Secondary delegate method must not be called redundantly")
                manager.stopMonitoring()
            }

            // =================================================================
            // PROBE 2: Rapid Monitor Connect/Disconnect Cycles & Memory Leaks
            // =================================================================

            runner.test("PROBE 2.1: 500 Rapid Connect/Disconnect Cycles Produce Zero Orphan Windows") {
                let s1 = ScreenDescriptor(displayID: 1, name: "Internal", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true)
                let s2 = ScreenDescriptor(displayID: 2, name: "External 4K", frame: CGRect(x: 1920, y: 0, width: 3840, height: 2160))
                let s3 = ScreenDescriptor(displayID: 3, name: "Sidecar iPad", frame: CGRect(x: -2048, y: 0, width: 2048, height: 1536))

                let mockScreenMgr = MockScreenManager(screens: [s1])
                let mockDelegate = MockDesktopWindowManagerDelegate()

                let windowMgr = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in MockDesktopWindow(frame: frame, displayID: id) }
                )
                windowMgr.delegate = mockDelegate
                windowMgr.start()

                var expectedAddedCount = 1 // initial s1
                var expectedRemovedCount = 0

                // Execute 500 rapid cycles of multi-display transitions
                for cycle in 0..<500 {
                    let phase = cycle % 4
                    switch phase {
                    case 0:
                        // Add s2
                        mockScreenMgr.simulateScreenChange(screens: [s1, s2])
                        expectedAddedCount += 1
                        try assertEqual(windowMgr.managedWindows.count, 2, "Cycle \(cycle): Expected 2 managed windows")
                        try assertNotNil(windowMgr.window(for: 1), "Window 1 must be present")
                        try assertNotNil(windowMgr.window(for: 2), "Window 2 must be present")
                    case 1:
                        // Add s3
                        mockScreenMgr.simulateScreenChange(screens: [s1, s2, s3])
                        expectedAddedCount += 1
                        try assertEqual(windowMgr.managedWindows.count, 3, "Cycle \(cycle): Expected 3 managed windows")
                        try assertNotNil(windowMgr.window(for: 3), "Window 3 must be present")
                    case 2:
                        // Disconnect s2
                        mockScreenMgr.simulateScreenChange(screens: [s1, s3])
                        expectedRemovedCount += 1
                        try assertEqual(windowMgr.managedWindows.count, 2, "Cycle \(cycle): Expected 2 managed windows")
                        try assertNil(windowMgr.window(for: 2), "Window 2 must be removed")
                    case 3:
                        // Disconnect s3 (back to single display)
                        mockScreenMgr.simulateScreenChange(screens: [s1])
                        expectedRemovedCount += 1
                        try assertEqual(windowMgr.managedWindows.count, 1, "Cycle \(cycle): Expected 1 managed window")
                        try assertNil(windowMgr.window(for: 3), "Window 3 must be removed")
                    default:
                        break
                    }
                }

                try assertEqual(mockDelegate.addedWindows.count, expectedAddedCount, "Total added windows must match exact cycle additions")
                try assertEqual(mockDelegate.removedDisplayIDs.count, expectedRemovedCount, "Total removed windows must match exact cycle removals")

                windowMgr.stop()
                try assertTrue(windowMgr.managedWindows.isEmpty, "Zero managed windows must remain after stop")
            }

            runner.test("PROBE 2.2: Memory Leak Audit via Weak Reference Tracking on Real DesktopWindow") {
                let s1 = ScreenDescriptor(displayID: 10, name: "Screen 10", frame: CGRect(x: 0, y: 0, width: 800, height: 600))
                let mockScreenMgr = MockScreenManager(screens: [s1])

                // Track created real DesktopWindow instances and mock window references
                final class MockWeakBox {
                    weak var window: MockDesktopWindow?
                    init(_ window: MockDesktopWindow) { self.window = window }
                }

                var mockWeakBoxes: [MockWeakBox] = []

                // Phase A: Verify DesktopWindowManager holds zero retain cycles (tested with MockDesktopWindow)
                let mockWindowMgr = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in
                        let win = MockDesktopWindow(frame: frame, displayID: id)
                        mockWeakBoxes.append(MockWeakBox(win))
                        return win
                    }
                )
                mockWindowMgr.start()

                for i in 11...60 {
                    let external = ScreenDescriptor(displayID: CGDirectDisplayID(i), name: "Display \(i)", frame: CGRect(x: CGFloat(i * 100), y: 0, width: 800, height: 600))
                    mockScreenMgr.simulateScreenChange(screens: [s1, external])
                    mockScreenMgr.simulateScreenChange(screens: [s1])
                }

                mockWindowMgr.stop()
                try assertEqual(mockWindowMgr.managedWindows.count, 0, "All managed windows purged on stop")

                // Drain autorelease pools
                autoreleasepool {}

                var mockLeakedCount = 0
                for box in mockWeakBoxes {
                    if box.window != nil {
                        mockLeakedCount += 1
                    }
                }
                try assertEqual(mockLeakedCount, 0, "DesktopWindowManager releases 100% of window references with zero manager retain cycles")

                // Phase B: Weak reference deallocation audit on real DesktopWindow instances
                final class RealWeakBox {
                    weak var window: DesktopWindow?
                    init(_ window: DesktopWindow) { self.window = window }
                }

                var realWeakBoxes: [RealWeakBox] = []

                autoreleasepool {
                    let realWindowMgr = DesktopWindowManager(
                        screenManager: mockScreenMgr,
                        windowFactory: { frame, id in
                            let win = DesktopWindow(contentRect: frame, displayID: id)
                            realWeakBoxes.append(RealWeakBox(win))
                            return win
                        }
                    )
                    realWindowMgr.start()

                    for i in 61...80 {
                        autoreleasepool {
                            let external = ScreenDescriptor(displayID: CGDirectDisplayID(i), name: "Display \(i)", frame: CGRect(x: CGFloat(i * 10), y: 0, width: 800, height: 600))
                            realWindowMgr.reconcileWindows(with: [s1, external])
                            realWindowMgr.reconcileWindows(with: [s1])
                        }
                    }

                    realWindowMgr.stop()
                    try? assertEqual(realWindowMgr.managedWindows.count, 0, "Real window manager purged all active references")
                }

                // Drain autorelease pools and allow AppKit deferred cleanup via RunLoop
                autoreleasepool {}
                for _ in 0..<5 {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                }
                autoreleasepool {}

                var realLeakedCount = 0
                for box in realWeakBoxes {
                    if box.window != nil {
                        realLeakedCount += 1
                    }
                }
                try assertEqual(realLeakedCount, 0, "All 21 DesktopWindow instances must be fully deallocated with zero retain cycles")
                try assertEqual(NSApp.windows.count, 0, "NSApp.windows must contain zero leaked windows after reconciliation shutdown")
            }

            runner.test("PROBE 2.3: Post-stop() Notifications and Calls Never Resurrect or Allocate Windows") {
                let s1 = ScreenDescriptor(displayID: 10, name: "Screen 10", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                let mockScreenMgr = MockScreenManager(screens: [s1])
                var factoryCallCount = 0

                let windowMgr = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in
                        factoryCallCount += 1
                        return MockDesktopWindow(frame: frame, displayID: id)
                    }
                )

                windowMgr.start()
                try assertEqual(factoryCallCount, 1, "Initial start creates 1 window")
                try assertEqual(windowMgr.managedWindows.count, 1, "1 window managed")

                windowMgr.stop()
                try assertEqual(windowMgr.managedWindows.count, 0, "0 windows managed after stop")
                try assertFalse(windowMgr.isRunning, "Manager reports isRunning == false")

                // Notifications after stop()
                for i in 0..<50 {
                    mockScreenMgr.simulateScreenChange(screens: [
                        s1,
                        ScreenDescriptor(displayID: CGDirectDisplayID(i + 50), name: "Display \(i)", frame: CGRect(x: 0, y: 0, width: 800, height: 600))
                    ])
                }

                // Direct reconciliation call after stop()
                windowMgr.reconcileWindows(with: [s1])

                try assertEqual(factoryCallCount, 1, "Window factory must never be invoked after stop()")
                try assertEqual(windowMgr.managedWindows.count, 0, "Zero windows allocated or resurrected after stop()")
            }

            // =================================================================
            // PROBE 3: Simulated Display Resolution Change & Zero-Flicker Identity
            // =================================================================

            runner.test("PROBE 3.1: Resolution Change Preserves Pointer Identity (Zero Flicker Guarantee)") {
                let s1 = ScreenDescriptor(displayID: 100, name: "Studio Display", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                let mockScreenMgr = MockScreenManager(screens: [s1])
                let mockDelegate = MockDesktopWindowManagerDelegate()

                let windowMgr = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in MockDesktopWindow(frame: frame, displayID: id) }
                )
                windowMgr.delegate = mockDelegate
                windowMgr.start()

                let initialWindow = windowMgr.window(for: 100)
                try assertNotNil(initialWindow, "Initial window for display 100 must exist")
                mockDelegate.reset()

                let resolutions: [(w: CGFloat, h: CGFloat)] = [
                    (2560, 1440),
                    (3840, 2160),
                    (5120, 2880),
                    (1920, 1080)
                ]

                for (idx, res) in resolutions.enumerated() {
                    let updatedScreen = ScreenDescriptor(
                        displayID: 100,
                        name: "Studio Display",
                        frame: CGRect(x: 0, y: 0, width: res.w, height: res.h)
                    )
                    mockScreenMgr.simulateScreenChange(screens: [updatedScreen])

                    let currentWindow = windowMgr.window(for: 100)
                    try assertNotNil(currentWindow, "Window must continue to exist")

                    // STRICT POINTER IDENTITY CHECK (===)
                    try assertTrue(
                        initialWindow === currentWindow,
                        "Resolution change \(idx + 1) to \(Int(res.w))x\(Int(res.h)) must preserve identical object pointer (Zero Flicker)"
                    )

                    try assertEqual(currentWindow?.frame.width, res.w, "Width must match updated resolution")
                    try assertEqual(currentWindow?.frame.height, res.h, "Height must match updated resolution")
                }

                // Verify that throughout all resolution updates, ZERO windows were added or removed
                try assertEqual(mockDelegate.addedWindows.count, 0, "No new windows should be added during resolution change")
                try assertEqual(mockDelegate.removedDisplayIDs.count, 0, "No windows should be removed during resolution change")
                try assertEqual(mockDelegate.updatedWindows.count, resolutions.count, "didUpdateWindow must be called for each resolution change")

                windowMgr.stop()
            }

            runner.test("PROBE 3.2: Resolution Change on Real DesktopWindow Resizes Layers In-Place") {
                let initialFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
                let window = DesktopWindow(contentRect: initialFrame, displayID: 55)

                let mockPlayerLayer = CALayer()
                mockPlayerLayer.name = "AVPlayerLayerSimulation"
                window.attachPlayerLayer(mockPlayerLayer)

                try assertEqual(window.frame, initialFrame, "Initial window frame")
                try assertEqual(window.currentActiveLayer, mockPlayerLayer, "Attached player layer")

                // Update to 4K resolution
                let newFrame = CGRect(x: 0, y: 0, width: 3840, height: 2160)
                window.updateFrame(newFrame)

                try assertEqual(window.frame.size, newFrame.size, "Window frame must match 4K")
                try assertEqual(window.contentView?.bounds.size, newFrame.size, "Content view bounds must match 4K")
                try assertEqual(mockPlayerLayer.frame.size, newFrame.size, "Player layer frame must resize in-place without recreation")
                try assertEqual(window.currentActiveLayer, mockPlayerLayer, "Player layer instance must remain unchanged")

                window.closeAndRelease()
            }

            runner.test("PROBE 3.3: 6-Step Resolution Ladder Preserves Strict Pointer Identity (===)") {
                let s1 = ScreenDescriptor(displayID: 50, name: "Studio Display", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                let mockScreenMgr = MockScreenManager(screens: [s1])
                let mockDelegate = MockDesktopWindowManagerDelegate()
                var factoryCallCount = 0

                let windowMgr = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in
                        factoryCallCount += 1
                        return MockDesktopWindow(frame: frame, displayID: id)
                    }
                )
                windowMgr.delegate = mockDelegate
                windowMgr.start()

                let originalWindow = windowMgr.window(for: 50)
                try assertNotNil(originalWindow, "Original window must exist")
                try assertEqual(factoryCallCount, 1, "Factory called once on start")

                let ladder: [(CGFloat, CGFloat)] = [
                    (2560, 1440),
                    (3840, 2160),
                    (5120, 2880),
                    (6016, 3384),
                    (7680, 4320),
                    (1920, 1080)
                ]

                for (w, h) in ladder {
                    let updated = ScreenDescriptor(displayID: 50, name: "Studio Display", frame: CGRect(x: 0, y: 0, width: w, height: h))
                    mockScreenMgr.simulateScreenChange(screens: [updated])

                    let currentWindow = windowMgr.window(for: 50)
                    try assertNotNil(currentWindow, "Window must continue to exist")
                    try assertTrue(originalWindow === currentWindow, "Pointer identity must not mutate during resolution change to \(w)x\(h)")
                    try assertEqual(currentWindow?.frame.width, w, "Width must match updated resolution")
                    try assertEqual(currentWindow?.frame.height, h, "Height must match updated resolution")
                }

                try assertEqual(factoryCallCount, 1, "Window factory must NEVER be called again during resolution changes")
                try assertEqual(mockDelegate.addedWindows.count, 1, "Only initial add occurred")
                try assertEqual(mockDelegate.removedDisplayIDs.count, 0, "Zero window removals during resolution changes")
                try assertEqual(mockDelegate.updatedWindows.count, ladder.count, "didUpdateWindow invoked for every resolution update")

                windowMgr.stop()
            }

            // =================================================================
            // PROBE 4: Adversarial Boundary & Concurrency Checks
            // =================================================================

            runner.test("PROBE 4.1: Redundant Resolution Update is a No-Op") {
                let s1 = ScreenDescriptor(displayID: 1, name: "Screen 1", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                let mockScreenMgr = MockScreenManager(screens: [s1])
                let mockDelegate = MockDesktopWindowManagerDelegate()

                let windowMgr = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in MockDesktopWindow(frame: frame, displayID: id) }
                )
                windowMgr.delegate = mockDelegate
                windowMgr.start()
                mockDelegate.reset()

                // Re-send EXACT SAME screen geometry
                mockScreenMgr.simulateScreenChange(screens: [s1])

                try assertEqual(mockDelegate.updatedWindows.count, 0, "No update event emitted if frame has not changed")
                try assertEqual(mockDelegate.addedWindows.count, 0, "No add event emitted")
                try assertEqual(mockDelegate.removedDisplayIDs.count, 0, "No remove event emitted")
                try assertEqual(mockDelegate.reconciliationBatches.count, 0, "No batch emitted for identical state")

                windowMgr.stop()
            }

            runner.test("PROBE 4.2: Sudden Disconnection of All Screens Enters Zero-Window State Safely") {
                let s1 = ScreenDescriptor(displayID: 1, name: "Screen 1", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                let mockScreenMgr = MockScreenManager(screens: [s1])
                let mockDelegate = MockDesktopWindowManagerDelegate()

                let windowMgr = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in MockDesktopWindow(frame: frame, displayID: id) }
                )
                windowMgr.delegate = mockDelegate
                windowMgr.start()

                try assertEqual(windowMgr.managedWindows.count, 1, "1 window managed")
                mockDelegate.reset()

                // Disconnect ALL screens (e.g. headless / display sleep / virtual disconnect)
                mockScreenMgr.simulateScreenChange(screens: [])

                try assertEqual(windowMgr.managedWindows.count, 0, "0 managed windows remaining")
                try assertEqual(mockDelegate.removedDisplayIDs, [1], "Display 1 reported as removed")
                try assertEqual(mockDelegate.reconciliationBatches.first?.removed, [1], "Batch removed matches [1]")

                windowMgr.stop()
            }
        }
    }
}

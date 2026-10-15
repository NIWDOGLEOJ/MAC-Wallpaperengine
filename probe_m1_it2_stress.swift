//
//  probe_m1_it2_stress.swift
//  WallpaperEngineCore
//
//  Milestone 1 Iteration 2 Challenger Stress Probes:
//  1. High-frequency notification spam & debounce coalescing (100 rapid notifications in 20ms)
//  2. Post-stop() notification immunity & zero resurrection / allocation
//  3. Display resolution updates with zero pointer mutation & in-place layer resizing
//  4. Manager deallocation lifecycle & weak reference memory audit
//

import AppKit
import CoreGraphics
import Foundation
import QuartzCore
@testable import WallpaperEngineCore

@MainActor
func drainAppKitEvents() {
    autoreleasepool {}
    for _ in 0..<5 {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    autoreleasepool {}
}

@MainActor
final class TrackingMockWindow: DesktopWindowProtocol {
    private let mock: MockDesktopWindow
    var underlyingWindow: NSWindow { mock.underlyingWindow }
    var rootHostingLayer: CALayer? { mock.rootHostingLayer }
    var contentLayer: CALayer? { get { mock.contentLayer } set { mock.contentLayer = newValue } }
    var currentActiveLayer: CALayer? { mock.currentActiveLayer }
    var windowLevel: Int { mock.windowLevel }
    var collectionBehaviorFlags: NSWindow.CollectionBehavior { mock.collectionBehaviorFlags }
    var ignoresMouseEventsFlag: Bool { mock.ignoresMouseEventsFlag }
    var canBecomeKey: Bool { mock.canBecomeKey }
    var canBecomeMain: Bool { mock.canBecomeMain }
    var frame: CGRect { mock.frame }
    var displayID: CGDirectDisplayID { mock.displayID }
    var isVisible: Bool { mock.isVisible }
    var onClose: () -> Void

    init(frame: CGRect, displayID: CGDirectDisplayID, onClose: @escaping () -> Void) {
        self.mock = MockDesktopWindow(frame: frame, displayID: displayID)
        self.onClose = onClose
    }

    func attachPlayerLayer(_ playerLayer: CALayer) { mock.attachPlayerLayer(playerLayer) }
    func removePlayerLayer() { mock.removePlayerLayer() }
    func transitionToPlayerLayer(_ newPlayerLayer: CALayer, duration: TimeInterval) { mock.transitionToPlayerLayer(newPlayerLayer, duration: duration) }
    func updateFrame(_ newFrame: CGRect) { mock.updateFrame(newFrame) }
    func orderToDesktopLevel() { mock.orderToDesktopLevel() }
    func closeAndRelease() {
        mock.closeAndRelease()
        onClose()
    }
}

@main
@MainActor
struct StressChallengerProbes {
    static func main() async {
        print("╔════════════════════════════════════════════════════════════════════╗")
        print("║   Milestone 1 Iteration 2 Challenger Empirical Stress Suite        ║")
        print("║   Testing: Debounce Storm, Post-Stop Lifecycle, Resolution Resizing ║")
        print("╚════════════════════════════════════════════════════════════════════╝\n")

        var totalPassed = 0
        var totalFailed = 0

        func probe(_ name: String, _ block: () async throws -> Void) async {
            print("  - Probe: [\(name)]...", terminator: " ")
            fflush(stdout)
            do {
                try await block()
                totalPassed += 1
                print("[\u{001B}[32mPASS\u{001B}[0m]")
            } catch {
                totalFailed += 1
                print("[\u{001B}[31mFAIL\u{001B}[0m]: \(error)")
            }
        }

        struct ProbeError: Error, CustomStringConvertible {
            let description: String
            init(_ description: String) { self.description = description }
        }

        func require(_ condition: Bool, _ msg: String) throws {
            if !condition { throw ProbeError(msg) }
        }

        func requireEqual<T: Equatable>(_ actual: T, _ expected: T, _ msg: String) throws {
            if actual != expected { throw ProbeError("\(msg) (Expected: [\(expected)], Got: [\(actual)])") }
        }

        // =====================================================================
        // CATEGORY 1: High-Frequency Notification Bursts & Debounce Coalescing
        // =====================================================================
        print("=== Category 1: High-Frequency Notification Bursts & Debouncing ===")

        await probe("P1.1: 100 Rapid Notifications in 20ms (0.2ms interval) Coalesce to 1 Callback") {
            final class Tracker: ScreenManagerDelegate {
                var callCount = 0
                func screenManager(_ manager: ScreenManagerProtocol, didDetectScreenChanges screens: [ScreenDescriptor]) {
                    callCount += 1
                }
            }

            let tracker = Tracker()
            let manager = ScreenManager(debounceDuration: 0.1) // 100ms
            manager.delegate = tracker
            manager.startMonitoring()

            // Fire 100 notifications within 20ms
            for _ in 0..<100 {
                NotificationCenter.default.post(
                    name: NSApplication.didChangeScreenParametersNotification,
                    object: nil
                )
                try await Task.sleep(nanoseconds: 200_000) // 0.2ms
            }

            // Verify 0 callbacks during debounce period
            try requireEqual(tracker.callCount, 0, "No callback during debounce window")

            // Wait for debounce window to expire (100ms + 60ms)
            try await Task.sleep(nanoseconds: 160_000_000)

            try requireEqual(tracker.callCount, 1, "Exactly 1 coalesced invocation must occur")
            manager.stopMonitoring()
        }

        await probe("P1.2: Multi-Threaded Burst: 200 Notifications Across 5 Tasks in 20ms") {
            final class ConcurrentTracker: ScreenManagerDelegate {
                var callCount = 0
                func screenManager(_ manager: ScreenManagerProtocol, didDetectScreenChanges screens: [ScreenDescriptor]) {
                    callCount += 1
                }
            }

            let tracker = ConcurrentTracker()
            let manager = ScreenManager(debounceDuration: 0.08) // 80ms
            manager.delegate = tracker
            manager.startMonitoring()

            // 5 tasks x 40 notifications = 200 notifications
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<5 {
                    group.addTask {
                        for _ in 0..<40 {
                            NotificationCenter.default.post(
                                name: NSApplication.didChangeScreenParametersNotification,
                                object: nil
                            )
                            try? await Task.sleep(nanoseconds: 500_000) // 0.5ms
                        }
                    }
                }
            }

            // Wait for debounce window (80ms + 70ms)
            try await Task.sleep(nanoseconds: 150_000_000)

            try requireEqual(tracker.callCount, 1, "Concurrent multi-threaded notification burst must coalesce to 1")
            manager.stopMonitoring()
        }

        await probe("P1.3: Single Delegate Method Invocation (No Duplicate or Redundant Callback)") {
            final class DualDelegateTracker: ScreenManagerDelegate {
                var primaryCallCount = 0
                var secondaryCallCount = 0

                func screenManager(_ manager: ScreenManagerProtocol, didDetectScreenChanges screens: [ScreenDescriptor]) {
                    primaryCallCount += 1
                }

                func screenManagerDidDetectChanges(screens: [ScreenDescriptor]) {
                    secondaryCallCount += 1
                }
            }

            let tracker = DualDelegateTracker()
            let manager = ScreenManager(debounceDuration: 0.05) // 50ms
            manager.delegate = tracker
            manager.startMonitoring()

            NotificationCenter.default.post(
                name: NSApplication.didChangeScreenParametersNotification,
                object: nil
            )

            try await Task.sleep(nanoseconds: 100_000_000)

            // When primary is implemented by adopter, ONLY primary is called
            try requireEqual(tracker.primaryCallCount, 1, "Primary delegate method must be called exactly once")
            try requireEqual(tracker.secondaryCallCount, 0, "Secondary delegate method must NOT be called redundantly")

            manager.stopMonitoring()
        }

        await probe("P1.4: Continuous Notification Flood Resets Debounce Window Repeatedly") {
            final class FloodTracker: ScreenManagerDelegate {
                var callCount = 0
                func screenManager(_ manager: ScreenManagerProtocol, didDetectScreenChanges screens: [ScreenDescriptor]) {
                    callCount += 1
                }
            }

            let tracker = FloodTracker()
            let manager = ScreenManager(debounceDuration: 0.06) // 60ms
            manager.delegate = tracker
            manager.startMonitoring()

            // Post every 15ms for 150ms (10 notifications total)
            // Since 15ms < 60ms debounce, timer must reset continuously
            for _ in 0..<10 {
                NotificationCenter.default.post(
                    name: NSApplication.didChangeScreenParametersNotification,
                    object: nil
                )
                try await Task.sleep(nanoseconds: 15_000_000) // 15ms
                try requireEqual(tracker.callCount, 0, "Callback must NOT fire while flood continues")
            }

            // Wait for debounce settling (60ms + 40ms)
            try await Task.sleep(nanoseconds: 100_000_000)

            try requireEqual(tracker.callCount, 1, "Exactly 1 trailing edge callback must fire after flood subsides")
            manager.stopMonitoring()
        }

        await probe("P1.5: Configurable Debounce Durations (0.02s vs 0.15s)") {
            final class DurationTracker: ScreenManagerDelegate {
                var callCount = 0
                func screenManager(_ manager: ScreenManagerProtocol, didDetectScreenChanges screens: [ScreenDescriptor]) {
                    callCount += 1
                }
            }

            // Short debounce: 20ms
            let fastTracker = DurationTracker()
            let fastMgr = ScreenManager(debounceDuration: 0.02)
            fastMgr.delegate = fastTracker
            fastMgr.startMonitoring()

            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            try await Task.sleep(nanoseconds: 40_000_000) // 40ms > 20ms
            try requireEqual(fastTracker.callCount, 1, "Fast manager must fire after 20ms window")
            fastMgr.stopMonitoring()

            // Longer debounce: 150ms
            let slowTracker = DurationTracker()
            let slowMgr = ScreenManager(debounceDuration: 0.15)
            slowMgr.delegate = slowTracker
            slowMgr.startMonitoring()

            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms < 150ms
            try requireEqual(slowTracker.callCount, 0, "Slow manager must NOT fire at 50ms")
            try await Task.sleep(nanoseconds: 130_000_000) // total 180ms > 150ms
            try requireEqual(slowTracker.callCount, 1, "Slow manager must fire after 150ms window")
            slowMgr.stopMonitoring()
        }

        // =====================================================================
        // CATEGORY 2: Post-stop() Lifecycle & Zombie Window Prevention
        // =====================================================================
        print("\n=== Category 2: Post-stop() Lifecycle & Zombie Window Prevention ===")

        await probe("P2.1: Post-stop() Notification Does Not Resurrect or Allocate Windows") {
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
            try requireEqual(factoryCallCount, 1, "Initial start creates 1 window")
            try requireEqual(windowMgr.managedWindows.count, 1, "1 window managed")

            windowMgr.stop()
            try requireEqual(windowMgr.managedWindows.count, 0, "0 windows managed after stop")
            try require(!windowMgr.isRunning, "Manager must report isRunning == false")

            // Fire simulated notification AFTER stop
            mockScreenMgr.simulateScreenChange(screens: [s1])

            try requireEqual(factoryCallCount, 1, "Window factory must NOT be invoked after stop()")
            try requireEqual(windowMgr.managedWindows.count, 0, "Zero windows allocated or resurrected after stop()")
        }

        await probe("P2.2: 100 Burst Notifications After stop() Produce Zero Window Allocations") {
            let s1 = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
            let s2 = ScreenDescriptor(displayID: 2, name: "Ext", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
            let mockScreenMgr = MockScreenManager(screens: [s1, s2])

            var factoryCount = 0
            let windowMgr = DesktopWindowManager(
                screenManager: mockScreenMgr,
                windowFactory: { frame, id in
                    factoryCount += 1
                    return MockDesktopWindow(frame: frame, displayID: id)
                }
            )

            windowMgr.start()
            try requireEqual(factoryCount, 2, "2 windows created initially")
            windowMgr.stop()
            try requireEqual(windowMgr.managedWindows.count, 0, "0 windows managed")

            // Spam 100 screen updates after stop
            for i in 0..<100 {
                mockScreenMgr.simulateScreenChange(screens: [
                    s1,
                    ScreenDescriptor(displayID: CGDirectDisplayID(i + 10), name: "Display \(i)", frame: CGRect(x: 0, y: 0, width: 800, height: 600))
                ])
            }

            try requireEqual(factoryCount, 2, "Factory must remain at 2; zero post-stop windows created")
            try requireEqual(windowMgr.managedWindows.count, 0, "managedWindows must remain strictly empty")
        }

        await probe("P2.3: Direct reconcileWindows(with:) Call While Stopped Is Strict No-Op") {
            let s1 = ScreenDescriptor(displayID: 1, name: "Screen", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
            let mockScreenMgr = MockScreenManager(screens: [])
            var factoryCount = 0

            let windowMgr = DesktopWindowManager(
                screenManager: mockScreenMgr,
                windowFactory: { frame, id in
                    factoryCount += 1
                    return MockDesktopWindow(frame: frame, displayID: id)
                }
            )

            // Direct call before start()
            windowMgr.reconcileWindows(with: [s1])
            try requireEqual(factoryCount, 0, "reconcileWindows before start() is a no-op")
            try requireEqual(windowMgr.managedWindows.count, 0, "0 managed windows")

            // Start then stop
            windowMgr.start()
            windowMgr.stop()

            // Direct call after stop()
            windowMgr.reconcileWindows(with: [s1])
            try requireEqual(factoryCount, 0, "reconcileWindows after stop() is a strict no-op")
            try requireEqual(windowMgr.managedWindows.count, 0, "managedWindows remains empty")
        }

        await probe("P2.4: Race Condition: In-Flight Notification Storm Interrupted by stop()") {
            let s1 = ScreenDescriptor(displayID: 1, name: "Display 1", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
            let mockScreenMgr = MockScreenManager(screens: [s1])

            let windowMgr = DesktopWindowManager(
                screenManager: mockScreenMgr,
                windowFactory: { frame, id in MockDesktopWindow(frame: frame, displayID: id) }
            )

            windowMgr.start()

            // Fire 50 notifications in background tasks, then call stop mid-burst
            let stopTask = Task { @MainActor in
                for i in 0..<50 {
                    let external = ScreenDescriptor(displayID: CGDirectDisplayID(i + 20), name: "Display \(i)", frame: CGRect(x: 0, y: 0, width: 800, height: 600))
                    mockScreenMgr.simulateScreenChange(screens: [s1, external])
                    if i == 25 {
                        windowMgr.stop()
                    }
                    try? await Task.sleep(nanoseconds: 100_000)
                }
            }

            _ = await stopTask.result

            try requireEqual(windowMgr.isRunning, false, "Manager must be stopped")
            try requireEqual(windowMgr.managedWindows.count, 0, "managedWindows must be empty after stop()")
        }

        await probe("P2.5: Idempotent stop() Calls Produce No Errors or Spurious Events") {
            let mockScreenMgr = MockScreenManager(screens: [])
            let mockDelegate = MockDesktopWindowManagerDelegate()
            let windowMgr = DesktopWindowManager(
                screenManager: mockScreenMgr,
                windowFactory: { frame, id in MockDesktopWindow(frame: frame, displayID: id) }
            )
            windowMgr.delegate = mockDelegate

            // Multiple stops on unstarted manager
            windowMgr.stop()
            windowMgr.stop()
            try requireEqual(mockDelegate.removedDisplayIDs.count, 0, "Zero removed events on unstarted stop")

            // Start, stop, and redundant stop
            windowMgr.start()
            windowMgr.stop()
            let removalsAfterFirstStop = mockDelegate.removedDisplayIDs.count

            windowMgr.stop()
            windowMgr.stop()
            try requireEqual(mockDelegate.removedDisplayIDs.count, removalsAfterFirstStop, "Redundant stop calls must not fire delegate events")
        }

        await probe("P2.6: Manager Deallocation via isolated deinit Tears Down All Windows Cleanly") {
            let s1 = ScreenDescriptor(displayID: 101, name: "Screen 101", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
            let mockScreenMgr = MockScreenManager(screens: [s1])

            var closedWindowCount = 0

            autoreleasepool {
                var localMgr: DesktopWindowManager? = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in
                        TrackingMockWindow(frame: frame, displayID: id) {
                            closedWindowCount += 1
                        }
                    }
                )
                localMgr?.start()
                try? requireEqual(localMgr?.managedWindows.count ?? 0, 1, "1 window managed")
                localMgr = nil // Trigger isolated deinit
            }

            try requireEqual(closedWindowCount, 1, "isolated deinit must invoke stop() and close all windows")
        }

        // =====================================================================
        // CATEGORY 3: Display Resolution Updates & Zero-Flicker Pointer Identity
        // =====================================================================
        print("\n=== Category 3: Display Resolution Updates & Zero-Flicker Identity ===")

        await probe("P3.1: Resolution Ladder Preserves Strict Pointer Identity Across 6 Transitions") {
            let s1 = ScreenDescriptor(displayID: 50, name: "Studio Display", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
            let mockScreenMgr = MockScreenManager(screens: [s1])
            let mockDelegate = MockDesktopWindowManagerDelegate()

            var factoryCount = 0
            let windowMgr = DesktopWindowManager(
                screenManager: mockScreenMgr,
                windowFactory: { frame, id in
                    factoryCount += 1
                    return MockDesktopWindow(frame: frame, displayID: id)
                }
            )
            windowMgr.delegate = mockDelegate
            windowMgr.start()

            let originalWindow = windowMgr.window(for: 50)
            try require(originalWindow != nil, "Original window must exist")
            try requireEqual(factoryCount, 1, "Factory called once on start")

            let resolutionLadder: [(CGFloat, CGFloat)] = [
                (2560, 1440), // 1440p
                (3840, 2160), // 4K
                (5120, 2880), // 5K
                (6016, 3384), // 6K Pro Display XDR
                (7680, 4320), // 8K
                (1920, 1080)  // Return to 1080p
            ]

            for (w, h) in resolutionLadder {
                let updated = ScreenDescriptor(displayID: 50, name: "Studio Display", frame: CGRect(x: 0, y: 0, width: w, height: h))
                mockScreenMgr.simulateScreenChange(screens: [updated])

                let currentWindow = windowMgr.window(for: 50)
                try require(currentWindow != nil, "Window must continue to exist")

                // STRICT POINTER IDENTITY CHECK (===)
                try require(originalWindow === currentWindow, "Pointer identity must NOT mutate during resolution change to \(w)x\(h)")
                try requireEqual(currentWindow?.frame.width ?? 0, w, "Width must match updated resolution")
                try requireEqual(currentWindow?.frame.height ?? 0, h, "Height must match updated resolution")
            }

            try requireEqual(factoryCount, 1, "Window factory must NEVER be called again during resolution changes")
            try requireEqual(mockDelegate.addedWindows.count, 1, "Only initial add occurred")
            try requireEqual(mockDelegate.removedDisplayIDs.count, 0, "Zero window removals during resolution changes")
            try requireEqual(mockDelegate.updatedWindows.count, resolutionLadder.count, "didUpdateWindow invoked for every resolution update")

            windowMgr.stop()
        }

        await probe("P3.2: Real DesktopWindow In-Place CALayer & NSView Bounds Synchronization") {
            let initialRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
            let realWin = DesktopWindow(contentRect: initialRect, displayID: 99)
            defer { realWin.closeAndRelease() }

            let playerLayer = CALayer()
            playerLayer.name = "RealAVPlayerLayer"
            realWin.attachPlayerLayer(playerLayer)

            try requireEqual(realWin.frame.size, initialRect.size, "Initial window size")
            try requireEqual(realWin.contentView?.bounds.size, initialRect.size, "Initial contentView size")
            try requireEqual(playerLayer.frame.size, initialRect.size, "Initial playerLayer size")
            try require(realWin.currentActiveLayer === playerLayer, "Player layer attached")

            // Resize to 4K
            let rect4K = CGRect(x: 0, y: 0, width: 3840, height: 2160)
            realWin.updateFrame(rect4K)

            try requireEqual(realWin.frame.size, rect4K.size, "Window resized to 4K")
            try requireEqual(realWin.contentView?.bounds.size, rect4K.size, "contentView resized to 4K")
            try requireEqual(playerLayer.frame.size, rect4K.size, "playerLayer resized in-place to 4K")
            try require(realWin.currentActiveLayer === playerLayer, "Player layer pointer identity preserved")

            // Invariants check after resize
            try requireEqual(realWin.level.rawValue, -2147483623, "Window level preserved at kCGDesktopWindowLevelKey")
            try requireEqual(Int(realWin.collectionBehavior.rawValue), 337, "Collection behavior flags preserved")
            try require(realWin.ignoresMouseEvents, "ignoresMouseEvents preserved")
        }

        await probe("P3.3: Multi-Display Independent Resolution Update (Display A Resizes, Display B Fixed)") {
            let s1 = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
            let s2 = ScreenDescriptor(displayID: 2, name: "Side", frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
            let mockScreenMgr = MockScreenManager(screens: [s1, s2])
            let mockDelegate = MockDesktopWindowManagerDelegate()

            let windowMgr = DesktopWindowManager(
                screenManager: mockScreenMgr,
                windowFactory: { frame, id in MockDesktopWindow(frame: frame, displayID: id) }
            )
            windowMgr.delegate = mockDelegate
            windowMgr.start()

            let win1 = windowMgr.window(for: 1)
            let win2 = windowMgr.window(for: 2)
            mockDelegate.reset()

            // Update ONLY display 1 to 4K, keep display 2 unchanged
            let s1Updated = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 3840, height: 2160))
            mockScreenMgr.simulateScreenChange(screens: [s1Updated, s2])

            let currentWin1 = windowMgr.window(for: 1)
            let currentWin2 = windowMgr.window(for: 2)

            try require(win1 === currentWin1, "Display 1 window pointer preserved")
            try require(win2 === currentWin2, "Display 2 window pointer preserved")
            try requireEqual(currentWin1?.frame.size.width ?? 0, 3840, "Display 1 width updated to 3840")
            try requireEqual(currentWin2?.frame.size.width ?? 0, 2560, "Display 2 width untouched at 2560")

            try requireEqual(mockDelegate.updatedWindows.count, 1, "Only 1 window marked as updated")
            try requireEqual(mockDelegate.updatedWindows.first?.id ?? 0, 1, "Updated window is display 1")
            try requireEqual(mockDelegate.addedWindows.count, 0, "Zero windows added")
            try requireEqual(mockDelegate.removedDisplayIDs.count, 0, "Zero windows removed")

            windowMgr.stop()
        }

        await probe("P3.4: Redundant Resolution Update is Strict No-Op with Zero Delegate Events") {
            let s1 = ScreenDescriptor(displayID: 10, name: "Display", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
            let mockScreenMgr = MockScreenManager(screens: [s1])
            let mockDelegate = MockDesktopWindowManagerDelegate()

            let windowMgr = DesktopWindowManager(
                screenManager: mockScreenMgr,
                windowFactory: { frame, id in MockDesktopWindow(frame: frame, displayID: id) }
            )
            windowMgr.delegate = mockDelegate
            windowMgr.start()
            mockDelegate.reset()

            // Simulate identical screen parameters
            mockScreenMgr.simulateScreenChange(screens: [s1])

            try requireEqual(mockDelegate.updatedWindows.count, 0, "Zero update events emitted for identical frame")
            try requireEqual(mockDelegate.addedWindows.count, 0, "Zero add events")
            try requireEqual(mockDelegate.removedDisplayIDs.count, 0, "Zero remove events")
            try requireEqual(mockDelegate.reconciliationBatches.count, 0, "Zero reconciliation batch events")

            windowMgr.stop()
        }

        await probe("P3.5: Negative Origin Geometry and Off-Screen Coordinates Handled Smoothly") {
            // Secondary monitor placed to the left with negative X origin
            let sNeg = ScreenDescriptor(displayID: 77, name: "Left Screen", frame: CGRect(x: -2560, y: 0, width: 2560, height: 1440))
            let realWin = DesktopWindow(contentRect: sNeg.frame, displayID: 77)
            defer { realWin.closeAndRelease() }

            try requireEqual(realWin.frame.origin.x, -2560, "Window origin accepts negative X")
            try requireEqual(realWin.frame.size.width, 2560, "Window width matches 2560")

            // Update to a different negative origin and resolution
            let sNeg2 = CGRect(x: -3840, y: -200, width: 3840, height: 2160)
            realWin.updateFrame(sNeg2)

            try requireEqual(realWin.frame.origin.x, -3840, "Updated origin accepts -3840")
            try requireEqual(realWin.frame.origin.y, -200, "Updated origin accepts -200")
            try requireEqual(realWin.frame.size.width, 3840, "Updated width matches 3840")
        }

        // =====================================================================
        // CATEGORY 4: Memory Leak Audit & Multiple Start/Stop Cycles
        // =====================================================================
        print("\n=== Category 4: Memory Leak Audit & Reusable Lifecycle ===")

        await probe("P4.1: 50 Connect/Disconnect/Resolution Cycles on Real DesktopWindow Release 100% of Memory") {
            let s1 = ScreenDescriptor(displayID: 100, name: "Screen 100", frame: CGRect(x: 0, y: 0, width: 800, height: 600))
            let mockScreenMgr = MockScreenManager(screens: [s1])

            final class RealWeakBox {
                weak var window: DesktopWindow?
                init(_ window: DesktopWindow) { self.window = window }
            }

            var weakBoxes: [RealWeakBox] = []

            autoreleasepool {
                let windowMgr = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in
                        let win = DesktopWindow(contentRect: frame, displayID: id)
                        weakBoxes.append(RealWeakBox(win))
                        return win
                    }
                )
                windowMgr.start()

                for i in 1...25 {
                    autoreleasepool {
                        let external = ScreenDescriptor(displayID: CGDirectDisplayID(i + 200), name: "Display \(i)", frame: CGRect(x: CGFloat(i * 10), y: 0, width: 800, height: 600))
                        windowMgr.reconcileWindows(with: [s1, external])
                        windowMgr.reconcileWindows(with: [s1])
                    }
                }

                windowMgr.stop()
                try? requireEqual(windowMgr.managedWindows.count, 0, "managedWindows empty after stop")
            }

            drainAppKitEvents()

            var leakedCount = 0
            for box in weakBoxes {
                if box.window != nil {
                    leakedCount += 1
                }
            }

            try requireEqual(leakedCount, 0, "Zero DesktopWindow memory leaks across 26 total windows")
            try requireEqual(NSApp.windows.count, 0, "NSApp.windows must contain zero lingering windows")
        }

        await probe("P4.2: 10 Successive Start / Stop Cycles on Same DesktopWindowManager Instance") {
            let s1 = ScreenDescriptor(displayID: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
            let mockScreenMgr = MockScreenManager(screens: [s1])

            var createdCount = 0
            var closedCount = 0

            let windowMgr = DesktopWindowManager(
                screenManager: mockScreenMgr,
                windowFactory: { frame, id in
                    createdCount += 1
                    return TrackingMockWindow(frame: frame, displayID: id) {
                        closedCount += 1
                    }
                }
            )

            for cycle in 1...10 {
                windowMgr.start()
                try requireEqual(windowMgr.isRunning, true, "Cycle \(cycle): isRunning must be true after start")
                try requireEqual(windowMgr.managedWindows.count, 1, "Cycle \(cycle): 1 window managed")

                windowMgr.stop()
                try requireEqual(windowMgr.isRunning, false, "Cycle \(cycle): isRunning must be false after stop")
                try requireEqual(windowMgr.managedWindows.count, 0, "Cycle \(cycle): 0 windows managed after stop")
            }

            try requireEqual(createdCount, 10, "Exactly 10 windows created across 10 start cycles")
            try requireEqual(closedCount, 10, "Exactly 10 windows closed across 10 stop cycles")
        }

        print("\n==================================================")
        print("EMPIRICAL STRESS PROBE SUMMARY:")
        print("  Total Probes: \(totalPassed + totalFailed)")
        print("  Passed:       \u{001B}[32m\(totalPassed)\u{001B}[0m")
        print("  Failed:       \(totalFailed > 0 ? "\u{001B}[31m\(totalFailed)\u{001B}[0m" : "0")")
        print("==================================================")

        if totalFailed > 0 {
            print("\n\u{001B}[31mFAILURES DETECTED IN STRESS PROBE RUN!\u{001B}[0m\n")
            exit(1)
        } else {
            print("\n\u{001B}[32mAll Milestone 1 Iteration 2 Stress Probes PASSED successfully!\u{001B}[0m\n")
            exit(0)
        }
    }
}

import AppKit
import CoreGraphics
import Foundation
import QuartzCore
@testable import WallpaperEngineCore

final class WeakBox<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

@main
@MainActor
struct DeallocationChallengerProbes {
    static func drainAppKit(cycles: Int = 10) {
        autoreleasepool {}
        for _ in 0..<cycles {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        autoreleasepool {}
    }

    static func main() {
        print("╔════════════════════════════════════════════════════════════════════╗")
        print("║   Milestone 1 It2 DesktopWindow Deallocation Empirical Probes      ║")
        print("║   Stress Testing: Purge, Dealloc, Autorelease Pools, Invariants    ║")
        print("╚════════════════════════════════════════════════════════════════════╝")

        var passed = 0
        var failed = 0

        func probe(_ name: String, _ check: () throws -> Void) {
            print("  - Probe: [\(name)]...", terminator: " ")
            fflush(stdout)
            do {
                try check()
                passed += 1
                print("[\u{001B}[32mPASS\u{001B}[0m]")
            } catch {
                failed += 1
                print("[\u{001B}[31mFAIL\u{001B}[0m]: \(error)")
            }
        }

        struct ProbeFailure: Error, CustomStringConvertible {
            let description: String
            init(_ description: String) { self.description = description }
        }

        func require(_ condition: Bool, _ msg: String) throws {
            if !condition { throw ProbeFailure(msg) }
        }

        // Initialize NSApplication.shared
        _ = NSApplication.shared

        // -----------------------------------------------------------------
        // Category 1: NSApplication.shared.windows Purge Verification
        // -----------------------------------------------------------------
        print("\n=== Category 1: NSApplication.shared.windows Purge Verification ===")

        probe("P1.1: Single DesktopWindow ordered front and closed is purged from NSApp.windows") {
            var box: WeakBox<DesktopWindow>?
            autoreleasepool {
                let win = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), displayID: 101)
                win.orderToDesktopLevel()
                box = WeakBox(win)
                try? require(NSApp.windows.contains(where: { $0 === win }), "Window must be in NSApp.windows while open")
                win.closeAndRelease()
            }
            drainAppKit()
            try require(!NSApp.windows.contains(where: { $0 === box?.value }), "Closed window must not be in NSApp.windows")
            try require(NSApp.windows.count == 0, "NSApp.windows count must be 0, got \(NSApp.windows.count)")
        }

        probe("P1.2: Multi-window (10 displays) batch close purges all instances from NSApp.windows") {
            var boxes: [WeakBox<DesktopWindow>] = []
            autoreleasepool {
                for i in 1...10 {
                    let win = DesktopWindow(contentRect: CGRect(x: CGFloat(i * 100), y: 0, width: 800, height: 600), displayID: CGDirectDisplayID(200 + i))
                    win.orderToDesktopLevel()
                    boxes.append(WeakBox(win))
                }
                try? require(NSApp.windows.count == 10, "NSApp.windows must have 10 windows before close")
                for box in boxes {
                    box.value?.closeAndRelease()
                }
            }
            drainAppKit()
            try require(NSApp.windows.count == 0, "NSApp.windows count must be 0 after batch close, got \(NSApp.windows.count)")
        }

        probe("P1.3: Unordered DesktopWindow (never ordered front) closed cleanly without orphan") {
            var box: WeakBox<DesktopWindow>?
            autoreleasepool {
                let win = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), displayID: 103)
                box = WeakBox(win)
                win.closeAndRelease()
            }
            drainAppKit()
            try require(NSApp.windows.count == 0, "NSApp.windows count must remain 0, got \(NSApp.windows.count)")
            try require(box?.value == nil, "Unordered window must deallocate cleanly")
        }

        probe("P1.4: Window ordered front then ordered out before closeAndRelease leaves 0 orphans") {
            var box: WeakBox<DesktopWindow>?
            autoreleasepool {
                let win = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), displayID: 104)
                win.orderToDesktopLevel()
                win.orderOut(nil)
                box = WeakBox(win)
                win.closeAndRelease()
            }
            drainAppKit()
            try require(NSApp.windows.count == 0, "NSApp.windows count must be 0, got \(NSApp.windows.count)")
            try require(box?.value == nil, "Window must deallocate cleanly after orderOut and close")
        }

        // -----------------------------------------------------------------
        // Category 2: Weak Reference Deallocation & Retain Cycle Probes
        // -----------------------------------------------------------------
        print("\n=== Category 2: Weak Reference Deallocation & Retain Cycle Probes ===")

        probe("P2.1: Single DesktopWindow deallocates cleanly (weak reference drops to nil)") {
            var box: WeakBox<DesktopWindow>?
            autoreleasepool {
                let win = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1024, height: 768), displayID: 105)
                box = WeakBox(win)
                win.orderToDesktopLevel()
                win.closeAndRelease()
            }
            drainAppKit()
            try require(box?.value == nil, "DesktopWindow must deallocate (weak reference == nil)")
        }

        probe("P2.2: 50 DesktopWindow instances with CALayers deallocate with 0 retain cycles") {
            var boxes: [WeakBox<DesktopWindow>] = []
            autoreleasepool {
                for i in 1...50 {
                    autoreleasepool {
                        let win = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: CGDirectDisplayID(300 + i))
                        let layer = CALayer()
                        layer.backgroundColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
                        win.attachPlayerLayer(layer)
                        win.orderToDesktopLevel()
                        boxes.append(WeakBox(win))
                        win.closeAndRelease()
                    }
                }
            }
            drainAppKit()
            let leakedCount = boxes.filter { $0.value != nil }.count
            try require(leakedCount == 0, "All 50 DesktopWindow instances must deallocate, leaked \(leakedCount)")
            try require(NSApp.windows.count == 0, "NSApp.windows count must be 0, got \(NSApp.windows.count)")
        }

        probe("P2.3: In-flight CATransaction crossfade animation interrupted by closeAndRelease") {
            var box: WeakBox<DesktopWindow>?
            autoreleasepool {
                let win = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), displayID: 106)
                box = WeakBox(win)
                let layerA = CALayer()
                win.attachPlayerLayer(layerA)
                let layerB = CALayer()
                win.transitionToPlayerLayer(layerB, duration: 1.0)
                // Interrupt mid-animation with closeAndRelease
                win.closeAndRelease()
            }
            drainAppKit(cycles: 20)
            try require(box?.value == nil, "DesktopWindow must deallocate even when closed mid-animation")
            try require(NSApp.windows.count == 0, "NSApp.windows must be empty")
        }

        probe("P2.4: Content view and player layers are completely severed on closeAndRelease") {
            let win = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), displayID: 107)
            let layer = CALayer()
            win.attachPlayerLayer(layer)
            try require(win.currentActiveLayer === layer, "active layer should be attached")
            try require(win.contentView != nil, "contentView must exist initially")
            win.closeAndRelease()
            try require(win.contentView == nil, "contentView must be nil after closeAndRelease")
            try require(win.currentActiveLayer == nil, "currentActiveLayer must be nil after closeAndRelease")
            drainAppKit()
        }

        // -----------------------------------------------------------------
        // Category 3: Autorelease Pool Drain Safety & ARC Over-Release Probes
        // -----------------------------------------------------------------
        print("\n=== Category 3: Autorelease Pool Drain Safety & ARC Over-Release Probes ===")

        probe("P3.1: Strict autoreleasepool drainage executes without crash or over-release") {
            for _ in 1...20 {
                autoreleasepool {
                    let win = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 400), displayID: 108)
                    win.orderToDesktopLevel()
                    win.closeAndRelease()
                }
            }
            drainAppKit()
            try require(NSApp.windows.count == 0, "NSApp.windows count must be 0 after scoped pools")
        }

        probe("P3.2: 200 consecutive rapid allocations and closures inside nested autoreleasepools") {
            var boxes: [WeakBox<DesktopWindow>] = []
            for i in 1...200 {
                autoreleasepool {
                    autoreleasepool {
                        let win = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 480), displayID: CGDirectDisplayID(500 + i))
                        win.orderToDesktopLevel()
                        boxes.append(WeakBox(win))
                        win.closeAndRelease()
                    }
                }
            }
            drainAppKit(cycles: 15)
            let leaked = boxes.filter { $0.value != nil }.count
            try require(leaked == 0, "Expected 0 leaks after 200 cycles, got \(leaked)")
            try require(NSApp.windows.count == 0, "NSApp.windows count must be 0 after 200 cycles, got \(NSApp.windows.count)")
        }

        probe("P3.3: Idempotent closeAndRelease: 10 consecutive calls on same instance cause no crash") {
            var box: WeakBox<DesktopWindow>?
            autoreleasepool {
                let win = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), displayID: 109)
                box = WeakBox(win)
                win.orderToDesktopLevel()
                for _ in 1...10 {
                    win.closeAndRelease()
                }
            }
            drainAppKit()
            try require(box?.value == nil, "Instance must deallocate after multiple closeAndRelease calls")
            try require(NSApp.windows.count == 0, "NSApp.windows count must be 0")
        }

        probe("P3.4: Delayed reference drop across runloop turns deallocates cleanly") {
            var box: WeakBox<DesktopWindow>?
            autoreleasepool {
                var win: DesktopWindow? = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), displayID: 110)
                box = WeakBox(win!)
                print(" [rc initial: \(CFGetRetainCount(win!))]", terminator: "")
                win?.orderToDesktopLevel()
                print(" [rc after order: \(CFGetRetainCount(win!))]", terminator: "")
                win?.closeAndRelease()
                print(" [rc after closeAndRelease: \(CFGetRetainCount(win!))]", terminator: "")
                // Keep strong reference active across 5 runloop turns
                for _ in 1...5 {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.005))
                }
                print(" [rc after runloop: \(CFGetRetainCount(win!))]", terminator: "")
                try? require(box?.value != nil, "Instance must remain alive while strong reference is held")
                win = nil // Drop strong reference
            }
            drainAppKit()
            print(" [box.value: \(String(describing: box?.value)), rc: \(box?.value != nil ? String(CFGetRetainCount(box!.value!)) : "nil")]", terminator: "")
            try require(box?.value == nil, "Instance must deallocate after strong reference is dropped")
            try require(NSApp.windows.count == 0, "NSApp.windows count must be 0")
        }

        // -----------------------------------------------------------------
        // Category 4: DesktopWindowManager Teardown & Stopped-State Guards
        // -----------------------------------------------------------------
        print("\n=== Category 4: DesktopWindowManager Teardown & Stopped-State Guards ===")

        let s1 = ScreenDescriptor(displayID: 1, name: "Screen 1", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let s2 = ScreenDescriptor(displayID: 2, name: "Screen 2", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        let s3 = ScreenDescriptor(displayID: 3, name: "Screen 3", frame: CGRect(x: 3840, y: 0, width: 1920, height: 1080))

        probe("P4.1: Manager stop() purges all managed windows from NSApp.windows and deallocates") {
            var boxes: [WeakBox<DesktopWindow>] = []
            autoreleasepool {
                let mockScreenMgr = MockScreenManager(screens: [s1, s2, s3])
                let manager = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in
                        let win = DesktopWindow(contentRect: frame, displayID: id)
                        boxes.append(WeakBox(win))
                        return win
                    }
                )
                manager.start()
                try? require(manager.managedWindows.count == 3, "Manager should have 3 windows")
                try? require(NSApp.windows.count == 3, "NSApp.windows should have 3 windows")
                manager.stop()
                try? require(manager.managedWindows.count == 0, "Manager should have 0 windows after stop")
            }
            drainAppKit()
            try require(NSApp.windows.count == 0, "NSApp.windows count must be 0, got \(NSApp.windows.count)")
            let leaked = boxes.filter { $0.value != nil }.count
            try require(leaked == 0, "All managed windows must deallocate after manager stop, leaked \(leaked)")
        }

        probe("P4.2: 50 multi-screen churn cycles deallocate 100% of windows with 0 leaks") {
            var boxes: [WeakBox<DesktopWindow>] = []
            autoreleasepool {
                let mockScreenMgr = MockScreenManager(screens: [s1])
                let manager = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in
                        let win = DesktopWindow(contentRect: frame, displayID: id)
                        boxes.append(WeakBox(win))
                        return win
                    }
                )
                manager.start()
                for i in 1...50 {
                    autoreleasepool {
                        let dynamicScreen = ScreenDescriptor(displayID: CGDirectDisplayID(1000 + i), name: "Display \(i)", frame: CGRect(x: CGFloat(i * 10), y: 0, width: 1000, height: 800))
                        manager.reconcileWindows(with: [s1, s2, dynamicScreen])
                        manager.reconcileWindows(with: [s1])
                    }
                }
                manager.stop()
            }
            drainAppKit(cycles: 15)
            try require(NSApp.windows.count == 0, "NSApp.windows count must be 0 after churn, got \(NSApp.windows.count)")
            let leaked = boxes.filter { $0.value != nil }.count
            try require(leaked == 0, "All churn windows must deallocate with 0 leaks, got \(leaked) leaked")
        }

        probe("P4.3: Stopped manager ignores reconcileWindows calls (guard isRunning else { return })") {
            let mockScreenMgr = MockScreenManager(screens: [s1])
            var createdCount = 0
            let manager = DesktopWindowManager(
                screenManager: mockScreenMgr,
                windowFactory: { frame, id in
                    createdCount += 1
                    return DesktopWindow(contentRect: frame, displayID: id)
                }
            )
            manager.start()
            try require(createdCount == 1, "Initial start creates 1 window")
            manager.stop()
            try require(manager.managedWindows.count == 0, "Stop clears windows")

            // Attempt reconciliation after stop
            manager.reconcileWindows(with: [s1, s2, s3])
            try require(manager.managedWindows.count == 0, "reconcileWindows after stop must be ignored")
            try require(createdCount == 1, "No new windows must be created when stopped")
            drainAppKit()
            try require(NSApp.windows.count == 0, "NSApp.windows count must remain 0")
        }

        probe("P4.4: Manager deallocation without explicit stop() triggers isolated deinit cleanup") {
            var boxes: [WeakBox<DesktopWindow>] = []
            autoreleasepool {
                let mockScreenMgr = MockScreenManager(screens: [s1, s2])
                var mgr: DesktopWindowManager? = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in
                        let win = DesktopWindow(contentRect: frame, displayID: id)
                        boxes.append(WeakBox(win))
                        return win
                    }
                )
                mgr?.start()
                try? require(NSApp.windows.count == 2, "2 windows created")
                // Do NOT call mgr.stop(); drop reference directly
                _ = mgr
                mgr = nil
            }
            drainAppKit()
            try require(NSApp.windows.count == 0, "isolated deinit must purge all windows from NSApp.windows, got \(NSApp.windows.count)")
            let leaked = boxes.filter { $0.value != nil }.count
            try require(leaked == 0, "All windows must deallocate on manager deinit, leaked \(leaked)")
        }

        // -----------------------------------------------------------------
        // Category 5: Invariant Levels & Collection Behaviors
        // -----------------------------------------------------------------
        print("\n=== Category 5: Invariant Levels & Collection Behaviors ===")

        probe("P5.1: Exact CGWindowLevelForKey(.desktopWindow) value is -2147483623") {
            let expected = Int(CGWindowLevelForKey(.desktopWindow))
            try require(expected == -2147483623, "Expected -2147483623, got \(expected)")
            let win = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), displayID: 111)
            defer { win.closeAndRelease(); drainAppKit() }
            try require(win.level.rawValue == -2147483623, "DesktopWindow level must be -2147483623, got \(win.level.rawValue)")
            try require(win.windowLevel == -2147483623, "windowLevel protocol property mismatch")
        }

        probe("P5.2: Composite collection behavior bitmask exact raw value equals 337") {
            let win = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), displayID: 112)
            defer { win.closeAndRelease(); drainAppKit() }
            let b = win.collectionBehavior
            try require(b.contains(.canJoinAllSpaces), "Must contain .canJoinAllSpaces (1)")
            try require(b.contains(.stationary), "Must contain .stationary (16)")
            try require(b.contains(.ignoresCycle), "Must contain .ignoresCycle (64)")
            try require(b.contains(.fullScreenAuxiliary), "Must contain .fullScreenAuxiliary (256)")
            let expectedRaw = 1 | 16 | 64 | 256 // 337
            try require(Int(b.rawValue) == expectedRaw, "Collection behavior bitmask must equal 337, got \(b.rawValue)")
            try require(win.collectionBehaviorFlags == b, "collectionBehaviorFlags mismatch")
        }

        probe("P5.3: Event transparency invariants (ignoresMouseEvents, non-activating)") {
            let win = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), displayID: 113)
            defer { win.closeAndRelease(); drainAppKit() }
            try require(win.ignoresMouseEvents == true, "ignoresMouseEvents must be true")
            try require(win.ignoresMouseEventsFlag == true, "ignoresMouseEventsFlag must be true")
            try require(win.canBecomeKey == false, "canBecomeKey must be false")
            try require(win.canBecomeMain == false, "canBecomeMain must be false")
        }

        probe("P5.4: Z-Order spacing relative to Finder desktop icons and baseWindow") {
            let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
            let baseLevel = Int(CGWindowLevelForKey(.baseWindow))
            try require(iconLevel == -2147483603, "desktopIconWindow must be -2147483603")
            try require(baseLevel == -2147483648, "baseWindow must be -2147483648")

            let win = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), displayID: 114)
            defer { win.closeAndRelease(); drainAppKit() }
            let lvl = win.level.rawValue
            try require(iconLevel - lvl == 20, "Must be exactly 20 levels below Finder desktop icons, got \(iconLevel - lvl)")
            try require(lvl - baseLevel == 25, "Must be exactly 25 levels above baseWindow, got \(lvl - baseLevel)")
        }

        // -----------------------------------------------------------------
        // Category 6: Extreme Adversarial & Edge Case Stress Probes
        // -----------------------------------------------------------------
        print("\n=== Category 6: Extreme Adversarial & Edge Case Stress Probes ===")

        probe("P6.1: Post-close mutation safety: mutations after closeAndRelease do not crash or resurrect") {
            let win = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), displayID: 115)
            win.orderToDesktopLevel()
            win.closeAndRelease()
            drainAppKit()

            // Attempt operations on already closed window
            win.updateFrame(CGRect(x: 10, y: 10, width: 500, height: 400))
            let extraLayer = CALayer()
            win.attachPlayerLayer(extraLayer)
            win.removePlayerLayer()
            win.orderToDesktopLevel()
            win.closeAndRelease() // secondary close
            drainAppKit()

            try require(NSApp.windows.count == 0, "Window must not be resurrected in NSApp.windows")
        }

        probe("P6.2: 1,000 rapid window create & close lifecycle churn") {
            var weakBoxes: [WeakBox<DesktopWindow>] = []
            for i in 1...1000 {
                autoreleasepool {
                    let win = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), displayID: CGDirectDisplayID(2000 + i))
                    win.orderToDesktopLevel()
                    weakBoxes.append(WeakBox(win))
                    win.closeAndRelease()
                }
                if i % 100 == 0 {
                    drainAppKit(cycles: 2)
                }
            }
            drainAppKit(cycles: 15)
            let leaked = weakBoxes.filter { $0.value != nil }.count
            try require(leaked == 0, "Expected 0 leaks after 1000 iterations, got \(leaked)")
            try require(NSApp.windows.count == 0, "NSApp.windows count must be 0 after 1000 iterations, got \(NSApp.windows.count)")
        }

        probe("P6.3: Boundary display IDs (0, UInt32.max, negative coordinate frames, zero rect)") {
            autoreleasepool {
                let winZero = DesktopWindow(contentRect: .zero, displayID: 0)
                try? require(winZero.windowLevel == -2147483623, "Zero frame window level mismatch")
                winZero.closeAndRelease()

                let winMax = DesktopWindow(contentRect: CGRect(x: -1920, y: -1080, width: 3840, height: 2160), displayID: UInt32.max)
                try? require(winMax.windowLevel == -2147483623, "Max displayID window level mismatch")
                try? require(winMax.collectionBehaviorFlags.rawValue == 337, "Collection behavior bitmask mismatch")
                winMax.closeAndRelease()
            }
            drainAppKit()
            try require(NSApp.windows.count == 0, "NSApp.windows count must be 0")
        }

        probe("P6.4: CALayer leak verification: attached video CALayers deallocate cleanly") {
            var layerBox: WeakBox<CALayer>?
            autoreleasepool {
                let win = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), displayID: 116)
                autoreleasepool {
                    let playerLayer = CALayer()
                    layerBox = WeakBox(playerLayer)
                    win.attachPlayerLayer(playerLayer)
                }
                win.orderToDesktopLevel()
                try? require(layerBox?.value != nil, "Layer must be retained by window hierarchy")
                win.closeAndRelease()
            }
            drainAppKit(cycles: 10)
            try require(layerBox?.value == nil, "Attached CALayer must deallocate when window closes")
            try require(NSApp.windows.count == 0, "NSApp.windows count must be 0")
        }

        probe("P6.5: Rapid multi-screen churn during active CALayer transitions") {
            var boxes: [WeakBox<DesktopWindow>] = []
            autoreleasepool {
                let mockScreenMgr = MockScreenManager(screens: [s1])
                let manager = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in
                        let win = DesktopWindow(contentRect: frame, displayID: id)
                        boxes.append(WeakBox(win))
                        return win
                    }
                )
                manager.start()

                for i in 1...20 {
                    autoreleasepool {
                        let newScreen = ScreenDescriptor(displayID: CGDirectDisplayID(3000 + i), name: "Display \(i)", frame: CGRect(x: CGFloat(i * 10), y: 0, width: 800, height: 600))
                        manager.reconcileWindows(with: [s1, newScreen])

                        // Trigger transition on all managed windows
                        for (_, win) in manager.managedWindows {
                            let nextLayer = CALayer()
                            win.transitionToPlayerLayer(nextLayer, duration: 0.1)
                        }

                        // Immediately disconnect while transition is in-flight
                        manager.reconcileWindows(with: [s1])
                    }
                }
                manager.stop()
            }
            drainAppKit(cycles: 20)
            let leaked = boxes.filter { $0.value != nil }.count
            try require(leaked == 0, "All windows during transition churn must deallocate, leaked \(leaked)")
            try require(NSApp.windows.count == 0, "NSApp.windows must be empty")
        }

        // Final sanity check
        drainAppKit()
        try? require(NSApp.windows.count == 0, "All probes completed; NSApp.windows must be completely clean (0)")

        print("\n==================================================")
        print("EMPIRICAL PROBE SUMMARY:")
        print("  Total Probes: \(passed + failed)")
        print("  Passed:       \(passed)")
        print("  Failed:       \(failed)")
        print("==================================================")

        if failed > 0 {
            print("FAILURE: \(failed) empirical probe(s) failed!")
            exit(1)
        } else {
            print("All DesktopWindow deallocation empirical probes PASSED successfully!")
            exit(0)
        }
    }
}

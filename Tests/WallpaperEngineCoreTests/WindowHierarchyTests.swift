//
//  WindowHierarchyTests.swift
//  WallpaperEngineCoreTests
//
//  Automated Unit and Integration Tests for Milestone 1: Window & Space Hierarchy Management.
//

import AppKit
import CoreGraphics
import Foundation
import QuartzCore
@testable import WallpaperEngineCore

@MainActor
public struct WindowHierarchyTests {

    public static func runAllTests() async {
        let runner = TestRunner.shared

        // =====================================================================
        // SUITE 1: Window Level & Quartz Z-Order Invariants
        // =====================================================================
        await runner.runSuite("Suite 1: Window Level & Quartz Z-Order Invariants") {

            runner.test("F1.1: Exact Desktop Window Level is -2147483623") {
                let window = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                let expectedLevel = Int(CGWindowLevelForKey(.desktopWindow))
                try assertEqual(window.level.rawValue, expectedLevel, "Window level must equal CGWindowLevelForKey(.desktopWindow)")
                try assertEqual(window.level.rawValue, -2147483623, "Window level raw value must be exactly -2147483623")
                try assertEqual(window.windowLevel, -2147483623, "Protocol property windowLevel must match raw level")
                window.closeAndRelease()
            }

            runner.test("F1.2: Window Level is Strictly 20 Levels Below Finder Desktop Icons") {
                let window = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                let desktopLevel = window.level.rawValue
                let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
                try assertEqual(iconLevel, -2147483603, "Finder icon level must be -2147483603")
                try assertTrue(desktopLevel < iconLevel, "Desktop window must sit strictly beneath desktop icons")
                try assertEqual(iconLevel - desktopLevel, 20, "Distance between desktop icons and desktop window must be exactly 20")
                window.closeAndRelease()
            }

            runner.test("F1.3: Window Level is Strictly Above Root Base Window Layer") {
                let window = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                let baseLevel = Int(CGWindowLevelForKey(.baseWindow))
                try assertEqual(baseLevel, -2147483648, "Base window level must be -2147483648")
                try assertTrue(window.level.rawValue > baseLevel, "Desktop window must sit strictly above base window layer")
                window.closeAndRelease()
            }

            runner.test("F1.4: Window Level Persists After Ordering and Frame Updates") {
                let window = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                window.orderToDesktopLevel()
                try assertEqual(window.level.rawValue, -2147483623, "Level must persist after orderToDesktopLevel")
                window.updateFrame(CGRect(x: 0, y: 0, width: 2560, height: 1440))
                try assertEqual(window.level.rawValue, -2147483623, "Level must persist after frame update")
                window.closeAndRelease()
            }

            runner.test("F1.5: Multi-Screen Window Levels Are Uniformly kCGDesktopWindowLevelKey") {
                let displays: [CGDirectDisplayID] = [1, 2, 3]
                let windows = displays.map { id in
                    DesktopWindow(contentRect: CGRect(x: CGFloat(id * 1920), y: 0, width: 1920, height: 1080), displayID: id)
                }
                for w in windows {
                    try assertEqual(w.level.rawValue, -2147483623, "All display windows must have level -2147483623")
                    w.closeAndRelease()
                }
            }
        }

        // =====================================================================
        // SUITE 2: Spaces, Mission Control & Window Cycling Collection Behaviors
        // =====================================================================
        await runner.runSuite("Suite 2: Spaces & Mission Control Collection Behaviors") {

            runner.test("F2.1: Collection Behaviors Contain All 4 Required Flags") {
                let window = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                let b = window.collectionBehavior
                try assertTrue(b.contains(.canJoinAllSpaces), "Must contain .canJoinAllSpaces")
                try assertTrue(b.contains(.stationary), "Must contain .stationary")
                try assertTrue(b.contains(.ignoresCycle), "Must contain .ignoresCycle")
                try assertTrue(b.contains(.fullScreenAuxiliary), "Must contain .fullScreenAuxiliary")
                try assertEqual(window.collectionBehaviorFlags, b, "collectionBehaviorFlags protocol property must match")
                window.closeAndRelease()
            }

            runner.test("F2.2: Composite Bitmask Raw Value Equals Exactly 337") {
                let window = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                // 1 (.canJoinAllSpaces) | 16 (.stationary) | 64 (.ignoresCycle) | 256 (.fullScreenAuxiliary) = 337
                try assertEqual(Int(window.collectionBehavior.rawValue), 337, "Raw collectionBehavior bitmask must be 337")
                window.closeAndRelease()
            }

            runner.test("F2.3: Collection Behaviors Invariant Across Display Resizing") {
                let window = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                window.updateFrame(CGRect(x: 0, y: 0, width: 3840, height: 2160))
                try assertEqual(Int(window.collectionBehavior.rawValue), 337, "Bitmask must remain 337 after resolution update")
                window.closeAndRelease()
            }
        }

        // =====================================================================
        // SUITE 3: Hit-Testing, Event Transparency & Focus Immunity
        // =====================================================================
        await runner.runSuite("Suite 3: Hit-Testing & Focus Immunity") {

            runner.test("F3.1: ignoresMouseEvents is Strictly True") {
                let window = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                try assertTrue(window.ignoresMouseEvents, "ignoresMouseEvents must be true for click pass-through")
                try assertTrue(window.ignoresMouseEventsFlag, "ignoresMouseEventsFlag protocol property must be true")
                window.closeAndRelease()
            }

            runner.test("F3.2: Focus Overrides Prevent Key and Main Window Activation") {
                let window = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                try assertFalse(window.canBecomeKey, "canBecomeKey must be false to prevent keyboard capture")
                try assertFalse(window.canBecomeMain, "canBecomeMain must be false to prevent document capture")
                try assertFalse(window.canBecomeKeyWindow, "canBecomeKeyWindow protocol property must be false")
                try assertFalse(window.canBecomeMainWindow, "canBecomeMainWindow protocol property must be false")
                window.closeAndRelease()
            }

            runner.test("F3.3: Visual & Chrome Properties (Borderless, Shadowless, Opaque)") {
                let window = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                try assertTrue(window.styleMask.contains(.borderless), "Window must be borderless")
                try assertFalse(window.hasShadow, "Window must not have drop shadows")
                try assertTrue(window.isOpaque, "Window must be opaque for performance")
                try assertEqual(window.backgroundColor, .black, "Default background color must be black")
                try assertFalse(window.canHide, "canHide must be false")
                try assertFalse(window.hidesOnDeactivate, "hidesOnDeactivate must be false")
                try assertEqual(window.animationBehavior, .none, "Animation behavior must be .none")
                try assertEqual(window.sharingType, .readOnly, "Sharing type must be .readOnly so screenshots and capture utilities capture wallpaper & widget")
                window.closeAndRelease()
            }
        }

        // =====================================================================
        // SUITE 4: CALayer Video Scanout Hosting & Transitions
        // =====================================================================
        await runner.runSuite("Suite 4: CALayer Video Hosting & Transitions") {

            runner.test("F4.1: Layer Hosting View Hierarchy Initialized") {
                let window = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                try assertNotNil(window.contentView, "contentView must exist")
                try assertTrue(window.contentView?.wantsLayer == true, "contentView must be layer-backed")
                try assertNotNil(window.rootHostingLayer, "rootHostingLayer must exist")
                window.closeAndRelease()
            }

            runner.test("F4.2: Attach and Remove Player Layer") {
                let window = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                let playerLayer = CALayer()
                playerLayer.name = "TestPlayerLayer"

                window.attachPlayerLayer(playerLayer)
                try assertEqual(window.currentActiveLayer, playerLayer, "Attached layer must be active")

                window.removePlayerLayer()
                try assertNil(window.currentActiveLayer, "Active layer must be nil after removal")
                window.closeAndRelease()
            }

            runner.test("F4.3: Smooth Crossfade Transition Mounts New Layer") {
                let window = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                let layer1 = CALayer()
                let layer2 = CALayer()

                window.attachPlayerLayer(layer1)
                try assertEqual(window.currentActiveLayer, layer1, "Initial layer must be layer1")

                window.transitionToPlayerLayer(layer2, duration: 0.1)
                try assertEqual(window.currentActiveLayer, layer2, "Current active layer must immediately point to layer2")
                window.closeAndRelease()
            }

            runner.test("F4.4: updateFrame Synchronizes Content View Bounds") {
                let window = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                let newFrame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
                window.updateFrame(newFrame)
                try assertEqual(window.frame, newFrame, "Window frame must match newFrame")
                try assertEqual(window.contentView?.bounds.size, newFrame.size, "ContentView bounds must match new frame size")
                window.closeAndRelease()
            }
        }

        // =====================================================================
        // SUITE 5: Screen Parameter Extraction & Geometry Modeling
        // =====================================================================
        await runner.runSuite("Suite 5: Screen Parameter Extraction & Models") {

            runner.test("F5.1: ScreenDescriptor Initialization & Identifiers") {
                let desc = ScreenDescriptor(
                    displayID: 42,
                    name: "Studio Display",
                    frame: CGRect(x: 0, y: 0, width: 5120, height: 2880),
                    scaleFactor: 2.0,
                    isMain: true,
                    isBuiltin: false
                )
                try assertEqual(desc.displayID, 42, "Display ID must match")
                try assertEqual(desc.id, 42, "Identifiable ID must match displayID")
                try assertEqual(desc.name, "Studio Display", "Display name must match")
                try assertEqual(desc.frame.width, 5120, "Frame width must match")
                try assertEqual(desc.scaleFactor, 2.0, "Scale factor must match")
                try assertTrue(desc.isMain, "isMain flag must be preserved")
                try assertFalse(desc.isBuiltin, "isBuiltin flag must be preserved")
            }

            runner.test("F5.2: ScreenDescriptor Equatable and Hashable Semantics") {
                let desc1 = ScreenDescriptor(displayID: 1, name: "Screen", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                let desc2 = ScreenDescriptor(displayID: 1, name: "Screen", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                let desc3 = ScreenDescriptor(displayID: 2, name: "Screen 2", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))

                try assertEqual(desc1, desc2, "Identical descriptors must be equal")
                try assertNotEqual(desc1, desc3, "Different display IDs must not be equal")

                let set: Set<ScreenDescriptor> = [desc1, desc2, desc3]
                try assertEqual(set.count, 2, "Set deduplication must collapse identical descriptors")
            }
        }

        // =====================================================================
        // SUITE 6: Multi-Display Lifecycle & Reconciliation (Mock Screen Provider)
        // =====================================================================
        await runner.runSuite("Suite 6: Multi-Display Lifecycle & Reconciliation") {

            runner.test("F6.1: Initial Boot Creates Windows for Active Displays") {
                let mockScreen1 = ScreenDescriptor(displayID: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true)
                let mockScreen2 = ScreenDescriptor(displayID: 2, name: "External", frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))

                let mockScreenMgr = MockScreenManager(screens: [mockScreen1, mockScreen2])
                let mockDelegate = MockDesktopWindowManagerDelegate()

                let windowMgr = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in MockDesktopWindow(frame: frame, displayID: id) }
                )
                windowMgr.delegate = mockDelegate

                windowMgr.start()

                try assertTrue(windowMgr.isRunning, "Window manager must be running")
                try assertEqual(windowMgr.managedWindows.count, 2, "Must manage exactly 2 windows")
                try assertNotNil(windowMgr.window(for: 1), "Must have window for Display 1")
                try assertNotNil(windowMgr.window(for: 2), "Must have window for Display 2")
                try assertEqual(mockDelegate.addedWindows.count, 2, "Delegate must receive 2 didAddWindow calls")

                let w1 = windowMgr.window(for: 1) as? MockDesktopWindow
                try assertTrue(w1?.isVisible == true, "Display 1 window must be visible")
                try assertEqual(w1?.orderToDesktopLevelCallCount, 1, "Must order to desktop level on creation")

                windowMgr.stop()
                try assertTrue(windowMgr.managedWindows.isEmpty, "Managed windows must be empty after stop")
            }

            runner.test("F6.2: External Display Hot-Plug Spawns New Window") {
                let screen1 = ScreenDescriptor(displayID: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                let mockScreenMgr = MockScreenManager(screens: [screen1])
                let mockDelegate = MockDesktopWindowManagerDelegate()

                let windowMgr = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in MockDesktopWindow(frame: frame, displayID: id) }
                )
                windowMgr.delegate = mockDelegate
                windowMgr.start()

                try assertEqual(windowMgr.managedWindows.count, 1, "Initial display count is 1")
                mockDelegate.reset()

                // Simulate plugging in external 4K monitor
                let screen2 = ScreenDescriptor(displayID: 2, name: "External 4K", frame: CGRect(x: 1920, y: 0, width: 3840, height: 2160))
                mockScreenMgr.simulateScreenChange(screens: [screen1, screen2])

                try assertEqual(windowMgr.managedWindows.count, 2, "Managed windows count must now be 2")
                try assertEqual(mockDelegate.addedWindows.count, 1, "didAddWindow must be called once for new monitor")
                try assertEqual(mockDelegate.addedWindows.first?.id, 2, "Added window must correspond to Display 2")

                windowMgr.stop()
            }

            runner.test("F6.3: External Display Disconnect Tears Down Orphan Window") {
                let screen1 = ScreenDescriptor(displayID: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                let screen2 = ScreenDescriptor(displayID: 2, name: "External", frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))

                let mockScreenMgr = MockScreenManager(screens: [screen1, screen2])
                let mockDelegate = MockDesktopWindowManagerDelegate()

                let windowMgr = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in MockDesktopWindow(frame: frame, displayID: id) }
                )
                windowMgr.delegate = mockDelegate
                windowMgr.start()

                let window2 = windowMgr.window(for: 2) as? MockDesktopWindow
                try assertNotNil(window2, "Window for Display 2 must exist initially")
                mockDelegate.reset()

                // Simulate unplugging Display 2
                mockScreenMgr.simulateScreenChange(screens: [screen1])

                try assertEqual(windowMgr.managedWindows.count, 1, "Managed windows count must reduce to 1")
                try assertNil(windowMgr.window(for: 2), "Window 2 must be purged from map")
                try assertEqual(mockDelegate.removedDisplayIDs, [2], "didRemoveWindowFor must be invoked for Display 2")
                try assertEqual(window2?.closeAndReleaseCallCount, 1, "closeAndRelease must be invoked on removed window")
                try assertFalse(window2?.isVisible ?? true, "Window 2 must no longer be visible")

                windowMgr.stop()
            }

            runner.test("F6.4: Display Resolution Change Preserves Pointer Identity (Zero Flicker)") {
                let screen1 = ScreenDescriptor(displayID: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                let mockScreenMgr = MockScreenManager(screens: [screen1])
                let mockDelegate = MockDesktopWindowManagerDelegate()

                let windowMgr = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in MockDesktopWindow(frame: frame, displayID: id) }
                )
                windowMgr.delegate = mockDelegate
                windowMgr.start()

                let originalWindow = windowMgr.window(for: 1) as? MockDesktopWindow
                try assertNotNil(originalWindow, "Original window must exist")
                mockDelegate.reset()

                // Simulate resolution change from 1080p to 1440p
                let updatedScreen1 = ScreenDescriptor(displayID: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 2560, height: 1440))
                mockScreenMgr.simulateScreenChange(screens: [updatedScreen1])

                let currentWindow = windowMgr.window(for: 1) as? MockDesktopWindow
                try assertTrue(originalWindow === currentWindow, "Pointer identity must be preserved across resolution changes (Zero Flicker)")
                try assertEqual(currentWindow?.frame.size.width, 2560, "Frame width must be updated to 2560")
                try assertEqual(currentWindow?.updateFrameCallCount, 1, "updateFrame must be called once")
                try assertEqual(mockDelegate.updatedWindows.count, 1, "didUpdateWindow must be called once")

                windowMgr.stop()
            }

            runner.test("F6.5: Batch Reconciliation Emits Accurate Composite Notification") {
                let s1 = ScreenDescriptor(displayID: 1, name: "Screen 1", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                let s2 = ScreenDescriptor(displayID: 2, name: "Screen 2", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
                let mockScreenMgr = MockScreenManager(screens: [s1, s2])
                let mockDelegate = MockDesktopWindowManagerDelegate()

                let windowMgr = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in MockDesktopWindow(frame: frame, displayID: id) }
                )
                windowMgr.delegate = mockDelegate
                windowMgr.start()
                mockDelegate.reset()

                // Complex simultaneous delta: remove s2, update s1 resolution, add s3
                let s1Updated = ScreenDescriptor(displayID: 1, name: "Screen 1", frame: CGRect(x: 0, y: 0, width: 2560, height: 1440))
                let s3 = ScreenDescriptor(displayID: 3, name: "Screen 3", frame: CGRect(x: 2560, y: 0, width: 1920, height: 1080))
                mockScreenMgr.simulateScreenChange(screens: [s1Updated, s3])

                try assertEqual(mockDelegate.reconciliationBatches.count, 1, "Must emit exactly 1 batch reconciliation notification")
                let batch = mockDelegate.reconciliationBatches[0]
                try assertEqual(batch.added, [3], "Batch added must be [3]")
                try assertEqual(batch.removed, [2], "Batch removed must be [2]")
                try assertEqual(batch.updated, [1], "Batch updated must be [1]")

                try assertEqual(mockDelegate.configChangeBatches.count, 1, "Must emit exactly 1 displayConfigurationDidChange notification")
                let configBatch = mockDelegate.configChangeBatches[0]
                try assertEqual(configBatch.added, [3], "ConfigBatch added must be [3]")
                try assertEqual(configBatch.removed, [2], "ConfigBatch removed must be [2]")
                try assertEqual(configBatch.updated, [1], "ConfigBatch updated must be [1]")

                windowMgr.stop()
            }

            runner.test("F6.6: Clean Shutdown Clears All Windows and Notifies Observers") {
                let s1 = ScreenDescriptor(displayID: 1, name: "S1", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                let s2 = ScreenDescriptor(displayID: 2, name: "S2", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
                let mockScreenMgr = MockScreenManager(screens: [s1, s2])
                let mockDelegate = MockDesktopWindowManagerDelegate()

                let windowMgr = DesktopWindowManager(
                    screenManager: mockScreenMgr,
                    windowFactory: { frame, id in MockDesktopWindow(frame: frame, displayID: id) }
                )
                windowMgr.delegate = mockDelegate
                windowMgr.start()

                try assertEqual(windowMgr.managedWindows.count, 2, "2 windows managed before stop")
                mockDelegate.reset()

                windowMgr.stop()

                try assertFalse(windowMgr.isRunning, "Manager must be stopped")
                try assertTrue(windowMgr.managedWindows.isEmpty, "All managed windows must be purged")
                try assertEqual(mockDelegate.removedDisplayIDs.count, 2, "Both displays must receive didRemoveWindowFor")
                try assertEqual(mockScreenMgr.stopMonitoringCallCount, 1, "Screen monitoring must be stopped")
            }
        }
    }
}

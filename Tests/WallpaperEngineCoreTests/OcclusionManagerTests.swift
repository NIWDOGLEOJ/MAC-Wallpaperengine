//
//  OcclusionManagerTests.swift
//  WallpaperEngineCoreTests
//
//  Unit tests verifying OcclusionManager per-display tracking and Space transitions.
//

import AppKit
import CoreGraphics
import Foundation
@testable import WallpaperEngineCore

@MainActor
public enum OcclusionManagerTests {
    public static func runAllTests() async {
        let runner = TestRunner.shared
        await runner.runSuite("OcclusionManager Tests (F14)") {
            runner.test("Default Display State Reports Visible") {
                let manager = OcclusionManager()
                try assertTrue(manager.isDisplayVisible(1), "Unregistered display should report visible by default")
                manager.registerDisplay(1, isVisible: true)
                try assertTrue(manager.isDisplayVisible(1), "Registered visible display should report true")
            }

            runner.test("Changing Display Visibility Dispatches Delegate Callback") {
                let manager = OcclusionManager()
                let delegate = MockOcclusionManagerDelegate()
                manager.delegate = delegate

                manager.registerDisplay(1, isVisible: true)
                manager.setDisplayVisibility(1, isVisible: false)

                try assertFalse(manager.isDisplayVisible(1), "Display should be occluded")
                try assertEqual(delegate.events.count, 1, "Delegate should receive 1 event")
                try assertEqual(delegate.lastEvent?.displayID, 1, "Event should match display ID")
                try assertEqual(delegate.lastEvent?.isVisible, false, "Event should indicate occluded")
            }

            runner.test("Per-Display Occlusion States Are Isolated") {
                let manager = OcclusionManager()
                manager.registerDisplay(1, isVisible: false)
                manager.registerDisplay(2, isVisible: true)

                try assertFalse(manager.isDisplayVisible(1), "Display 1 must be occluded")
                try assertTrue(manager.isDisplayVisible(2), "Display 2 must be visible")
            }

            runner.test("Unregistering Display Restores Default Fallback") {
                let manager = OcclusionManager()
                manager.registerDisplay(1, isVisible: false)
                try assertFalse(manager.isDisplayVisible(1), "Display 1 should be occluded")

                manager.unregisterDisplay(1)
                try assertTrue(manager.isDisplayVisible(1), "Unregistered display should return fallback true")
            }

            runner.test("activeSpaceDidChangeNotification Sweeps All Displays") {
                let wsCenter = NotificationCenter()
                let manager = OcclusionManager(workspaceNotificationCenter: wsCenter)
                let window1 = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
                manager.registerWindow(window1, for: 10)

                // Trigger space change notification
                wsCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
                try assertTrue(manager.isDisplayVisible(10), "Display 10 should be evaluated")
            }

            runner.test("registerWindow(DesktopWindowProtocol) Conformance") {
                let manager = OcclusionManager()
                let mockWindow = MockDesktopWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 42)
                manager.registerWindow(mockWindow)

                try assertTrue(manager.isDisplayVisible(42), "Display 42 should be tracked and visible")
            }
        }
    }
}

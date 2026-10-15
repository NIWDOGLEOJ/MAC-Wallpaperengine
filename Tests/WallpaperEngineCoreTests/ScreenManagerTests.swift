//
//  ScreenManagerTests.swift
//  WallpaperEngineCoreTests
//
//  Unit tests for ScreenManager, notification debouncing, and ScreenDescriptor extraction.
//

import AppKit
import CoreGraphics
import Foundation
@testable import WallpaperEngineCore

@MainActor
public struct ScreenManagerTests {

    public static func runAllTests() async {
        let runner = TestRunner.shared

        await runner.runSuite("Suite 7: ScreenManager & Screen Parameter Extraction") {

            runner.test("SM.1: NSScreen Display Identifier Extraction") {
                if let screen = NSScreen.screens.first {
                    let descriptor = ScreenDescriptor(screen: screen)
                    try assertTrue(descriptor.displayID != 0, "Display ID extracted from NSScreen must be non-zero")
                    try assertEqual(descriptor.frame, screen.frame, "Frame must match NSScreen.frame")
                    try assertEqual(descriptor.scaleFactor, screen.backingScaleFactor, "Scale factor must match NSScreen")
                    try assertTrue(descriptor.isMain, "First screen must be main screen")
                } else {
                    print("(Skipping physical screen check in headless environment)")
                }
            }

            runner.test("SM.2: ScreenManager DisplaysHaveSeparateSpaces Reflection") {
                let manager = ScreenManager()
                try assertEqual(manager.displaysHaveSeparateSpaces, NSScreen.screensHaveSeparateSpaces, "Must reflect NSScreen.screensHaveSeparateSpaces")
            }

            runner.test("SM.3: ScreenManager Screen Lookup by DisplayID") {
                let manager = ScreenManager()
                if let firstScreen = NSScreen.screens.first {
                    let descriptor = ScreenDescriptor(screen: firstScreen)
                    let foundScreen = manager.screen(for: descriptor.displayID)
                    try assertNotNil(foundScreen, "Must find NSScreen by displayID")
                    try assertEqual(foundScreen?.frame, firstScreen.frame, "Found screen frame must match")
                }
                let invalidLookup = manager.screen(for: 99999999)
                try assertNil(invalidLookup, "Invalid display ID must return nil")
            }

            runner.test("SM.4: ScreenManager Monitoring Start and Stop Lifecycle") {
                let manager = ScreenManager()
                manager.startMonitoring()
                // Starting again should be idempotent
                manager.startMonitoring()
                manager.stopMonitoring()
                // Stopping again should be safe
                manager.stopMonitoring()
            }

            await runner.testAsync("SM.5: ScreenManager Notification Debouncing Coalesces Rapid Events") {
                // Class to capture delegate invocations
                final class NotificationTracker: ScreenManagerDelegate {
                    var callCount = 0
                    var detectedScreens: [ScreenDescriptor] = []

                    func screenManager(_ manager: ScreenManagerProtocol, didDetectScreenChanges screens: [ScreenDescriptor]) {
                        callCount += 1
                        detectedScreens = screens
                    }
                }

                let tracker = NotificationTracker()
                let manager = ScreenManager(debounceDuration: 0.1) // 100ms debounce
                manager.delegate = tracker
                manager.startMonitoring()

                // Rapidly post 5 screen parameter notifications within 20ms
                for _ in 0..<5 {
                    NotificationCenter.default.post(
                        name: NSApplication.didChangeScreenParametersNotification,
                        object: nil
                    )
                    try await Task.sleep(nanoseconds: 5_000_000) // 5ms sleep
                }

                // Wait 160ms to allow debounce timer to expire
                try await Task.sleep(nanoseconds: 160_000_000)

                // The delegate must have been invoked exactly once!
                try assertEqual(tracker.callCount, 1, "5 rapid notifications within debounce window must coalesce into exactly 1 delegate invocation")

                manager.stopMonitoring()
            }

            runner.test("SM.6: ScreenProviderProtocol Dependency Injection Interchangeability") {
                let mockProvider: ScreenProviderProtocol = MockScreenManager()
                try assertTrue(mockProvider.activeScreens.isEmpty, "Mock provider conforms to ScreenProviderProtocol")
            }
        }
    }
}

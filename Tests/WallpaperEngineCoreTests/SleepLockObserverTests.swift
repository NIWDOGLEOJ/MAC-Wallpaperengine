//
//  SleepLockObserverTests.swift
//  WallpaperEngineCoreTests
//
//  Unit tests verifying SleepLockObserver against NSWorkspace and Darwin events.
//

import AppKit
import Foundation
@testable import WallpaperEngineCore

@MainActor
public enum SleepLockObserverTests {
    public static func runAllTests() async {
        let runner = TestRunner.shared
        await runner.runSuite("SleepLockObserver Tests (F12 & F13)") {
            runner.test("Initial State Synchronously Probes Session Status") {
                let session = MockSessionStateProvider(locked: true, onConsole: false)
                let observer = SleepLockObserver(sessionProvider: session)
                try assertTrue(observer.currentState.isScreenLocked, "Should detect locked state on startup")
                try assertFalse(observer.currentState.isSessionActive, "Should detect inactive console session")
            }

            runner.test("NSWorkspace willSleepNotification sets isSystemSleeping") {
                let center = NotificationCenter()
                let observer = SleepLockObserver(workspaceNotificationCenter: center)
                let delegate = MockSleepLockObserverDelegate()
                observer.delegate = delegate
                observer.start()

                center.post(name: NSWorkspace.willSleepNotification, object: nil)
                try assertTrue(observer.currentState.isSystemSleeping, "System should be marked sleeping")
                try assertEqual(delegate.states.count, 1, "Delegate should be notified once")
            }

            runner.test("NSWorkspace didWakeNotification clears isSystemSleeping") {
                let center = NotificationCenter()
                let initial = SleepLockState(isSystemSleeping: true)
                let observer = SleepLockObserver(initialState: initial, workspaceNotificationCenter: center)
                observer.start()

                center.post(name: NSWorkspace.didWakeNotification, object: nil)
                try assertFalse(observer.currentState.isSystemSleeping, "System sleeping flag should clear")
            }

            runner.test("NSWorkspace screensDidSleepNotification sets areScreensSleeping") {
                let center = NotificationCenter()
                let observer = SleepLockObserver(workspaceNotificationCenter: center)
                observer.start()

                center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
                try assertTrue(observer.currentState.areScreensSleeping, "Screens should be marked sleeping")
            }

            runner.test("NSWorkspace screensDidWakeNotification clears areScreensSleeping") {
                let center = NotificationCenter()
                let initial = SleepLockState(areScreensSleeping: true)
                let observer = SleepLockObserver(initialState: initial, workspaceNotificationCenter: center)
                observer.start()

                center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
                try assertFalse(observer.currentState.areScreensSleeping, "Screens sleeping flag should clear")
            }

            runner.test("Display Wake with Active Lock Maintains isScreenLocked") {
                let center = NotificationCenter()
                let session = MockSessionStateProvider(locked: true)
                let initial = SleepLockState(areScreensSleeping: true, isScreenLocked: true)
                let observer = SleepLockObserver(initialState: initial, workspaceNotificationCenter: center, sessionProvider: session)
                observer.start()

                center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
                try assertFalse(observer.currentState.areScreensSleeping, "Screens should wake")
                try assertTrue(observer.currentState.isScreenLocked, "Lock state must remain true on wake")
            }

            runner.test("Fast User Switching Resign Notification Inactivates Session") {
                let center = NotificationCenter()
                let observer = SleepLockObserver(workspaceNotificationCenter: center)
                observer.start()

                center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
                try assertFalse(observer.currentState.isSessionActive, "Session must be marked inactive")
            }

            runner.test("Fast User Switching Active Notification Reactivates Session") {
                let center = NotificationCenter()
                let initial = SleepLockState(isSessionActive: false)
                let observer = SleepLockObserver(initialState: initial, workspaceNotificationCenter: center)
                observer.start()

                center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
                try assertTrue(observer.currentState.isSessionActive, "Session must be marked active")
            }

            runner.test("Darwin com.apple.screenIsLocked Sets isScreenLocked") {
                let darwin = MockDarwinNotificationProvider()
                let observer = SleepLockObserver(darwinProvider: darwin)
                observer.start()

                darwin.simulateNotification("com.apple.screenIsLocked")
                try assertTrue(observer.currentState.isScreenLocked, "Screen must be marked locked")
            }

            runner.test("Darwin com.apple.screenIsUnlocked Clears isScreenLocked") {
                let darwin = MockDarwinNotificationProvider()
                let initial = SleepLockState(isScreenLocked: true)
                let observer = SleepLockObserver(initialState: initial, darwinProvider: darwin)
                observer.start()

                darwin.simulateNotification("com.apple.screenIsUnlocked")
                try assertFalse(observer.currentState.isScreenLocked, "Screen must be marked unlocked")
            }

            runner.test("Darwin Screensaver Start and Stop Correctly Toggles State") {
                let darwin = MockDarwinNotificationProvider()
                let observer = SleepLockObserver(darwinProvider: darwin)
                observer.start()

                darwin.simulateNotification("com.apple.screensaver.didstart")
                try assertTrue(observer.currentState.isScreensaverActive, "Screensaver must be active")

                darwin.simulateNotification("com.apple.screensaver.didstop")
                try assertFalse(observer.currentState.isScreensaverActive, "Screensaver must be inactive")
            }

            runner.test("Calling stop() Deregisters Darwin and Workspace Observers") {
                let center = NotificationCenter()
                let darwin = MockDarwinNotificationProvider()
                let observer = SleepLockObserver(workspaceNotificationCenter: center, darwinProvider: darwin)
                observer.start()
                try assertTrue(observer.isRunning, "Observer should be running")

                observer.stop()
                try assertFalse(observer.isRunning, "Observer should not be running")
                try assertEqual(darwin.unregisterCallCount, 1, "Darwin observer should be unregistered")

                // Posting after stop should have no effect
                center.post(name: NSWorkspace.willSleepNotification, object: nil)
                try assertFalse(observer.currentState.isSystemSleeping, "Notification after stop must be ignored")
            }
        }
    }
}

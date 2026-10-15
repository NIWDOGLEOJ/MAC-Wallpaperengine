//
//  TestHarness.swift
//  WallpaperEngineCoreTests
//
//  Lightweight, zero-dependency test runner, assertions, and mock infrastructure.
//

import AppKit
import CoreGraphics
import Foundation
import QuartzCore
@testable import WallpaperEngineCore

// MARK: - Lightweight Test Framework

@MainActor
public final class TestRunner {
    public static let shared = TestRunner()

    public private(set) var totalTests: Int = 0
    public private(set) var passedTests: Int = 0
    public private(set) var failedTests: Int = 0
    public private(set) var failures: [String] = []

    private var currentSuiteName: String = ""

    public func runSuite(_ name: String, _ body: () async throws -> Void) async {
        currentSuiteName = name
        print("\n=== Running Suite: \(name) ===")
        do {
            try await body()
        } catch {
            recordFailure("Suite '\(name)' threw unexpected error: \(error)")
        }
    }

    public func test(_ name: String, _ body: () throws -> Void) {
        totalTests += 1
        print("  - Running test: \(name)...", terminator: " ")
        fflush(stdout)

        let start = DispatchTime.now()
        do {
            try body()
            passedTests += 1
            let end = DispatchTime.now()
            let elapsedMs = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            print("[\u{001B}[32mPASS\u{001B}[0m] (\(String(format: "%.2f", elapsedMs))ms)")
        } catch {
            failedTests += 1
            print("[\u{001B}[31mFAIL\u{001B}[0m]")
            recordFailure("[\(currentSuiteName)] \(name) failed: \(error)")
        }
    }

    public func testAsync(_ name: String, _ body: () async throws -> Void) async {
        totalTests += 1
        print("  - Running test: \(name)...", terminator: " ")
        fflush(stdout)

        let start = DispatchTime.now()
        do {
            try await body()
            passedTests += 1
            let end = DispatchTime.now()
            let elapsedMs = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            print("[\u{001B}[32mPASS\u{001B}[0m] (\(String(format: "%.2f", elapsedMs))ms)")
        } catch {
            failedTests += 1
            print("[\u{001B}[31mFAIL\u{001B}[0m]")
            recordFailure("[\(currentSuiteName)] \(name) failed: \(error)")
        }
    }

    public func recordFailure(_ message: String) {
        failures.append(message)
    }

    public func printSummary() -> Int32 {
        print("\n==================================================")
        print("Test Execution Summary:")
        print("  Total Tests:  \(totalTests)")
        print("  Passed:       \u{001B}[32m\(passedTests)\u{001B}[0m")
        print("  Failed:       \(failedTests > 0 ? "\u{001B}[31m\(failedTests)\u{001B}[0m" : "0")")
        print("==================================================")

        if !failures.isEmpty {
            print("\nFailures:")
            for (idx, f) in failures.enumerated() {
                print("  \(idx + 1). \(f)")
            }
            return 1
        }
        print("\n\u{001B}[32mAll test assertions passed successfully!\u{001B}[0m\n")
        return 0
    }
}

// MARK: - Assertion Utilities

public struct TestFailure: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

public func assertTrue(_ condition: Bool, _ message: String = "Expected condition to be true", file: StaticString = #file, line: UInt = #line) throws {
    guard condition else {
        throw TestFailure("\(message) at \(file):\(line)")
    }
}

public func assertFalse(_ condition: Bool, _ message: String = "Expected condition to be false", file: StaticString = #file, line: UInt = #line) throws {
    guard !condition else {
        throw TestFailure("\(message) at \(file):\(line)")
    }
}

public func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "Values not equal", file: StaticString = #file, line: UInt = #line) throws {
    guard actual == expected else {
        throw TestFailure("\(message) — expected [\(expected)], got [\(actual)] at \(file):\(line)")
    }
}

public func assertNotEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "Values must not be equal", file: StaticString = #file, line: UInt = #line) throws {
    guard actual != expected else {
        throw TestFailure("\(message) — both values equal [\(actual)] at \(file):\(line)")
    }
}

public func assertNil<T>(_ value: T?, _ message: String = "Expected nil", file: StaticString = #file, line: UInt = #line) throws {
    guard value == nil else {
        throw TestFailure("\(message) — expected nil, got [\(value!)] at \(file):\(line)")
    }
}

public func assertNotNil<T>(_ value: T?, _ message: String = "Expected non-nil value", file: StaticString = #file, line: UInt = #line) throws {
    guard value != nil else {
        throw TestFailure("\(message) — got nil at \(file):\(line)")
    }
}

// MARK: - Mock Infrastructure for Milestone 1

/// Mock screen manager providing controllable display states for headless reconciliation testing.
@MainActor
public final class MockScreenManager: ScreenManagerProtocol {
    public weak var delegate: ScreenManagerDelegate?
    public var activeScreens: [ScreenDescriptor] = []
    public var displaysHaveSeparateSpaces: Bool = true

    public private(set) var isMonitoring: Bool = false
    public private(set) var startMonitoringCallCount: Int = 0
    public private(set) var stopMonitoringCallCount: Int = 0

    public init(screens: [ScreenDescriptor] = []) {
        self.activeScreens = screens
    }

    public func startMonitoring() {
        isMonitoring = true
        startMonitoringCallCount += 1
    }

    public func stopMonitoring() {
        isMonitoring = false
        stopMonitoringCallCount += 1
    }

    public func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        nil
    }

    /// Programmatically updates screen list and triggers delegate notifications.
    public func simulateScreenChange(screens: [ScreenDescriptor]) {
        self.activeScreens = screens
        delegate?.screenManager(self, didDetectScreenChanges: screens)
    }
}

/// Mock desktop window tracking lifecycle events and operations.
@MainActor
public final class MockDesktopWindow: DesktopWindowProtocol {
    public let displayID: CGDirectDisplayID
    public var underlyingWindow: NSWindow { mockWindow }
    public var rootHostingLayer: CALayer? = CALayer()
    public var contentLayer: CALayer?
    public var currentActiveLayer: CALayer?
    public var isVisible: Bool = false

    public var windowLevel: Int { mockWindow.level.rawValue }
    public var collectionBehaviorFlags: NSWindow.CollectionBehavior { mockWindow.collectionBehavior }
    public var ignoresMouseEventsFlag: Bool { mockWindow.ignoresMouseEvents }
    public var canBecomeKey: Bool { mockWindow.canBecomeKey }
    public var canBecomeMain: Bool { mockWindow.canBecomeMain }
    public var canBecomeKeyWindow: Bool { mockWindow.canBecomeKey }
    public var canBecomeMainWindow: Bool { mockWindow.canBecomeMain }

    public private(set) var frame: CGRect
    public private(set) var attachedLayers: [CALayer] = []
    public private(set) var removedLayerCount: Int = 0
    public private(set) var updateFrameCallCount: Int = 0
    public private(set) var orderToDesktopLevelCallCount: Int = 0
    public private(set) var closeAndReleaseCallCount: Int = 0
    public private(set) var transitionDuration: TimeInterval?

    private let mockWindow: NSWindow

    public init(frame: CGRect, displayID: CGDirectDisplayID) {
        self.frame = frame
        self.displayID = displayID
        self.mockWindow = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.mockWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        self.mockWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.mockWindow.ignoresMouseEvents = true
    }

    public func attachPlayerLayer(_ playerLayer: CALayer) {
        attachedLayers.append(playerLayer)
        currentActiveLayer = playerLayer
        contentLayer = playerLayer
    }

    public func removePlayerLayer() {
        currentActiveLayer = nil
        contentLayer = nil
        removedLayerCount += 1
    }

    public func transitionToPlayerLayer(_ newLayer: CALayer, duration: TimeInterval) {
        transitionDuration = duration
        attachedLayers.append(newLayer)
        currentActiveLayer = newLayer
        contentLayer = newLayer
    }

    public func updateFrame(_ newFrame: CGRect) {
        self.frame = newFrame
        self.mockWindow.setFrame(newFrame, display: false)
        updateFrameCallCount += 1
    }

    public func orderToDesktopLevel() {
        isVisible = true
        orderToDesktopLevelCallCount += 1
    }

    private var isClosed = false

    public func closeAndRelease() {
        guard !isClosed else { return }
        isClosed = true
        isVisible = false
        closeAndReleaseCallCount += 1
        mockWindow.orderOut(nil)
        mockWindow.isReleasedWhenClosed = true
        _ = Unmanaged.passRetained(mockWindow)
        mockWindow.close()
    }
}

/// Mock delegate recording granular and batch reconciliation events.
@MainActor
public final class MockDesktopWindowManagerDelegate: DesktopWindowManagerDelegate {
    public var addedWindows: [(window: DesktopWindowProtocol, id: CGDirectDisplayID)] = []
    public var removedDisplayIDs: [CGDirectDisplayID] = []
    public var updatedWindows: [(window: DesktopWindowProtocol, id: CGDirectDisplayID)] = []
    public var reconciliationBatches: [(added: [CGDirectDisplayID], removed: [CGDirectDisplayID], updated: [CGDirectDisplayID])] = []
    public var configChangeBatches: [(added: [CGDirectDisplayID], removed: [CGDirectDisplayID], updated: [CGDirectDisplayID])] = []

    public init() {}

    public func desktopWindowManager(_ manager: DesktopWindowManagerProtocol, didAddWindow window: DesktopWindowProtocol, for displayID: CGDirectDisplayID) {
        addedWindows.append((window, displayID))
    }

    public func desktopWindowManager(_ manager: DesktopWindowManagerProtocol, didRemoveWindowFor displayID: CGDirectDisplayID) {
        removedDisplayIDs.append(displayID)
    }

    public func desktopWindowManager(_ manager: DesktopWindowManagerProtocol, didUpdateWindow window: DesktopWindowProtocol, for displayID: CGDirectDisplayID) {
        updatedWindows.append((window, displayID))
    }

    public func desktopWindowManager(_ manager: DesktopWindowManagerProtocol, didReconcileWindows added: [CGDirectDisplayID], removed: [CGDirectDisplayID], updated: [CGDirectDisplayID]) {
        reconciliationBatches.append((added, removed, updated))
    }

    public func displayConfigurationDidChange(added: [CGDirectDisplayID], removed: [CGDirectDisplayID], updated: [CGDirectDisplayID]) {
        configChangeBatches.append((added, removed, updated))
    }

    public func reset() {
        addedWindows.removeAll()
        removedDisplayIDs.removeAll()
        updatedWindows.removeAll()
        reconciliationBatches.removeAll()
        configChangeBatches.removeAll()
    }
}

// MARK: - M3 Test Doubles

public final class MockDarwinNotificationProvider: DarwinNotificationProviderProtocol, @unchecked Sendable {
    public var handler: (@Sendable (String) -> Void)?
    public var registeredEvents: [String] = []
    public var unregisterCallCount: Int = 0

    public init() {}

    public func register(events: [String], onNotification: @escaping @Sendable (String) -> Void) {
        self.registeredEvents = events
        self.handler = onNotification
    }

    public func unregister() {
        unregisterCallCount += 1
        registeredEvents.removeAll()
        handler = nil
    }

    public func simulateNotification(_ event: String) {
        handler?(event)
    }
}

public final class MockSessionStateProvider: SessionStateProviderProtocol, @unchecked Sendable {
    public var locked: Bool
    public var onConsole: Bool

    public init(locked: Bool = false, onConsole: Bool = true) {
        self.locked = locked
        self.onConsole = onConsole
    }

    public func isSessionLocked() -> Bool { locked }
    public func isSessionOnConsole() -> Bool { onConsole }
}

@MainActor
public final class MockSleepLockObserverDelegate: SleepLockObserverDelegate {
    public var states: [SleepLockState] = []
    public var lastState: SleepLockState? { states.last }

    public init() {}

    public func sleepLockStateDidChange(_ newState: SleepLockState) {
        states.append(newState)
    }

    public func reset() {
        states.removeAll()
    }
}

@MainActor
public final class MockOcclusionManagerDelegate: OcclusionManagerDelegate {
    public var events: [(displayID: CGDirectDisplayID, isVisible: Bool)] = []
    public var lastEvent: (displayID: CGDirectDisplayID, isVisible: Bool)? { events.last }

    public init() {}

    public func occlusionDidChange(for displayID: CGDirectDisplayID, isVisible: Bool) {
        events.append((displayID, isVisible))
    }

    public func reset() {
        events.removeAll()
    }
}

public struct MockSleepLockEventGenerator {
    public static func normalActive() -> SleepLockState {
        SleepLockState(isSystemSleeping: false, areScreensSleeping: false, isScreenLocked: false, isScreensaverActive: false, isSessionActive: true)
    }

    public static func locked() -> SleepLockState {
        SleepLockState(isSystemSleeping: false, areScreensSleeping: false, isScreenLocked: true, isScreensaverActive: false, isSessionActive: true)
    }

    public static func screensSleeping() -> SleepLockState {
        SleepLockState(isSystemSleeping: false, areScreensSleeping: true, isScreenLocked: false, isScreensaverActive: false, isSessionActive: true)
    }

    public static func screensaver() -> SleepLockState {
        SleepLockState(isSystemSleeping: false, areScreensSleeping: false, isScreenLocked: false, isScreensaverActive: true, isSessionActive: true)
    }

    public static func sessionInactive() -> SleepLockState {
        SleepLockState(isSystemSleeping: false, areScreensSleeping: false, isScreenLocked: false, isScreensaverActive: false, isSessionActive: false)
    }
}

public struct MockPowerEventGenerator {
    public static func ac(isLowPowerMode: Bool = false, thermalState: ProcessInfo.ThermalState = .nominal) -> PowerState {
        PowerState(source: .ac, batteryLevel: 1.0, isCharging: true, isLowPowerModeEnabled: isLowPowerMode, thermalState: thermalState)
    }

    public static func battery(batteryLevel: Double = 0.8, isCharging: Bool = false, isLowPowerMode: Bool = false, thermalState: ProcessInfo.ThermalState = .nominal) -> PowerState {
        PowerState(source: .battery, batteryLevel: batteryLevel, isCharging: isCharging, isLowPowerModeEnabled: isLowPowerMode, thermalState: thermalState)
    }

    public static func thermalSerious(onBattery: Bool = false) -> PowerState {
        PowerState(source: onBattery ? .battery : .ac, batteryLevel: onBattery ? 0.8 : 1.0, isCharging: !onBattery, isLowPowerModeEnabled: false, thermalState: .serious)
    }

    public static func thermalCritical(onBattery: Bool = false) -> PowerState {
        PowerState(source: onBattery ? .battery : .ac, batteryLevel: onBattery ? 0.8 : 1.0, isCharging: !onBattery, isLowPowerModeEnabled: false, thermalState: .critical)
    }
}

// MARK: - M4 Test Doubles

@MainActor
public final class MockStatusItemButton: StatusItemButtonProtocol {
    public var title: String = ""
    public var toolTip: String?
    public var image: NSImage?
    public var isEnabled: Bool = true

    public init() {}
}

@MainActor
public final class MockStatusItem: StatusItemProtocol {
    public var length: CGFloat = 0
    public var menu: NSMenu?
    public var isVisible: Bool = true
    public var mockButton = MockStatusItemButton()

    public var button: (any StatusItemButtonProtocol)? {
        mockButton
    }

    public init() {}
}

@MainActor
public final class MockStatusItemProvider: StatusItemProviderProtocol {
    public var createdItems: [MockStatusItem] = []
    public var removedItems: [MockStatusItem] = []

    public init() {}

    public func makeStatusItem(length: CGFloat) -> any StatusItemProtocol {
        let item = MockStatusItem()
        item.length = length
        createdItems.append(item)
        return item
    }

    public func removeStatusItem(_ item: any StatusItemProtocol) {
        if let mock = item as? MockStatusItem {
            removedItems.append(mock)
        }
    }
}

@MainActor
public final class MockMenuBarControllerDelegate: MenuBarControllerDelegate {
    public var togglePlaybackCount = 0
    public var selectedAssets: [(url: URL, displayID: CGDirectDisplayID?)] = []
    public var updatedConfigs: [EngineConfig] = []
    public var selectedFrameRates: [Int] = []
    public var toggledPauseDisplays: [CGDirectDisplayID] = []
    public var revealWallpapersCount = 0
    public var quitCount = 0

    public init() {}

    public func menuBarDidTogglePlayback(_ controller: MenuBarControllerProtocol) {
        togglePlaybackCount += 1
    }

    public func menuBar(_ controller: MenuBarControllerProtocol, didSelectAssetURL url: URL, for displayID: CGDirectDisplayID?) {
        selectedAssets.append((url, displayID))
    }

    public func menuBar(_ controller: MenuBarControllerProtocol, didUpdateConfig config: EngineConfig) {
        updatedConfigs.append(config)
    }

    public func menuBar(_ controller: MenuBarControllerProtocol, didSelectTargetFrameRate fps: Int) {
        selectedFrameRates.append(fps)
    }

    public func menuBar(_ controller: MenuBarControllerProtocol, didTogglePauseFor displayID: CGDirectDisplayID) {
        toggledPauseDisplays.append(displayID)
    }

    public func menuBarDidRequestRevealWallpapers(_ controller: MenuBarControllerProtocol) {
        revealWallpapersCount += 1
    }

    public func menuBarDidRequestQuit(_ controller: MenuBarControllerProtocol) {
        quitCount += 1
    }
}

public final class MockConfigStorage: ConfigStorageProtocol, @unchecked Sendable {
    public var storedConfig: EngineConfig?
    public var loadCount = 0
    public var saveCount = 0
    public var shouldThrowOnSave = false

    public init(initialConfig: EngineConfig? = nil) {
        self.storedConfig = initialConfig
    }

    public func load() -> EngineConfig? {
        loadCount += 1
        return storedConfig
    }

    public func save(_ config: EngineConfig) throws {
        if shouldThrowOnSave {
            throw NSError(domain: "MockConfigStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Simulated save error"])
        }
        saveCount += 1
        storedConfig = config
    }
}




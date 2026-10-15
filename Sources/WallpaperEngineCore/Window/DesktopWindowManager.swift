//
//  DesktopWindowManager.swift
//  WallpaperEngineCore
//
//  Multi-display desktop window lifecycle coordinator and layout reconciliation engine.
//

import AppKit
import CoreGraphics
import QuartzCore

// MARK: - Desktop Window Manager Delegate

/// Delegate interface receiving window lifecycle and multi-display layout change events.
@MainActor
public protocol DesktopWindowManagerDelegate: AnyObject {
    /// Invoked when a new desktop window has been created and ordered to desktop level.
    func desktopWindowManager(_ manager: DesktopWindowManagerProtocol, didAddWindow window: DesktopWindowProtocol, for displayID: CGDirectDisplayID)

    /// Invoked immediately before a window is closed and destroyed due to display disconnection.
    func desktopWindowManager(_ manager: DesktopWindowManagerProtocol, didRemoveWindowFor displayID: CGDirectDisplayID)

    /// Invoked when an existing window's frame or resolution has been updated.
    func desktopWindowManager(_ manager: DesktopWindowManagerProtocol, didUpdateWindow window: DesktopWindowProtocol, for displayID: CGDirectDisplayID)

    /// Invoked at the conclusion of an atomic reconciliation pass with lists of affected display IDs.
    func desktopWindowManager(_ manager: DesktopWindowManagerProtocol, didReconcileWindows added: [CGDirectDisplayID], removed: [CGDirectDisplayID], updated: [CGDirectDisplayID])

    /// Contract method for VideoEngine synchronization defined in PROJECT.md.
    func displayConfigurationDidChange(added: [CGDirectDisplayID], removed: [CGDirectDisplayID], updated: [CGDirectDisplayID])
}

// Default empty implementations for selective adoption
extension DesktopWindowManagerDelegate {
    public func desktopWindowManager(_ manager: DesktopWindowManagerProtocol, didAddWindow window: DesktopWindowProtocol, for displayID: CGDirectDisplayID) {}
    public func desktopWindowManager(_ manager: DesktopWindowManagerProtocol, didRemoveWindowFor displayID: CGDirectDisplayID) {}
    public func desktopWindowManager(_ manager: DesktopWindowManagerProtocol, didUpdateWindow window: DesktopWindowProtocol, for displayID: CGDirectDisplayID) {}
    public func desktopWindowManager(_ manager: DesktopWindowManagerProtocol, didReconcileWindows added: [CGDirectDisplayID], removed: [CGDirectDisplayID], updated: [CGDirectDisplayID]) {}
    public func displayConfigurationDidChange(added: [CGDirectDisplayID], removed: [CGDirectDisplayID], updated: [CGDirectDisplayID]) {}
}

// MARK: - Desktop Window Manager Protocol

/// Defines the capabilities and lifecycle of the desktop window manager.
@MainActor
public protocol DesktopWindowManagerProtocol: AnyObject {
    /// Active windows keyed by CGDirectDisplayID.
    var managedWindows: [CGDirectDisplayID: DesktopWindowProtocol] { get }

    /// Delegate receiving window manager events.
    var delegate: DesktopWindowManagerDelegate? { get set }

    /// Associated screen manager monitoring displays.
    var screenManager: ScreenManagerProtocol { get }

    /// Whether the window manager is actively monitoring and managing windows.
    var isRunning: Bool { get }

    /// Starts screen monitoring and reconciles initial desktop windows.
    func start()

    /// Stops monitoring, closes all managed windows, and resets state.
    func stop()

    /// Returns the active desktop window for a given screen ID.
    func window(for displayID: CGDirectDisplayID) -> DesktopWindowProtocol?

    /// Reconciles desktop window allocations against a given list of screens.
    func reconcileWindows(with screens: [ScreenDescriptor])
}

// MARK: - Factory Type for Headless Dependency Injection

/// Factory closure signature for creating desktop windows, enabling headless mock injection.
public typealias DesktopWindowFactory = @MainActor (CGRect, CGDirectDisplayID) -> DesktopWindowProtocol

// MARK: - Concrete DesktopWindowManager Implementation

/// Coordinates desktop window lifecycles across multiple displays, diffing geometries and preventing flicker.
@MainActor
public final class DesktopWindowManager: DesktopWindowManagerProtocol, ScreenManagerDelegate {
    public private(set) var managedWindows: [CGDirectDisplayID: DesktopWindowProtocol] = [:]
    public weak var delegate: DesktopWindowManagerDelegate?
    public let screenManager: ScreenManagerProtocol
    public private(set) var isRunning: Bool = false

    private let windowFactory: DesktopWindowFactory

    /// Initializes DesktopWindowManager with injectable screen provider and window factory.
    public init(
        screenManager: ScreenManagerProtocol = ScreenManager(),
        windowFactory: @escaping DesktopWindowFactory = { frame, id in
            DesktopWindow(contentRect: frame, displayID: id)
        }
    ) {
        self.screenManager = screenManager
        self.windowFactory = windowFactory
        self.screenManager.delegate = self
    }

    /// Starts screen monitoring and performs initial window reconciliation.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        screenManager.startMonitoring()
        reconcileWindows(with: screenManager.activeScreens)
    }

    /// Stops monitoring and tears down all managed desktop windows.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        screenManager.stopMonitoring()
        let removedIDs = Array(managedWindows.keys)
        for (id, window) in managedWindows {
            delegate?.desktopWindowManager(self, didRemoveWindowFor: id)
            window.closeAndRelease()
        }
        managedWindows.removeAll()
        if !removedIDs.isEmpty {
            delegate?.desktopWindowManager(self, didReconcileWindows: [], removed: removedIDs, updated: [])
            delegate?.displayConfigurationDidChange(added: [], removed: removedIDs, updated: [])
        }
    }

    /// Retrieves the managed window associated with a specific display ID.
    public func window(for displayID: CGDirectDisplayID) -> DesktopWindowProtocol? {
        managedWindows[displayID]
    }

    // MARK: - ScreenManagerDelegate

    public func screenManager(_ manager: ScreenManagerProtocol, didDetectScreenChanges screens: [ScreenDescriptor]) {
        reconcileWindows(with: screens)
    }

    public func screenManagerDidDetectChanges(screens: [ScreenDescriptor]) {
        // Redundant callback suppressed: reconciliation is handled exclusively by
        // screenManager(_:didDetectScreenChanges:).
    }

    // MARK: - Diff-Based Layout Reconciliation

    public func reconcileWindows(with screens: [ScreenDescriptor]) {
        guard isRunning else { return }

        let currentIDs = Set(screens.map(\.displayID))
        let existingIDs = Set(managedWindows.keys)

        let removedIDs = existingIDs.subtracting(currentIDs)
        var addedIDs: [CGDirectDisplayID] = []
        var updatedIDs: [CGDirectDisplayID] = []

        // 1. Close and remove disconnected display windows
        for id in removedIDs {
            if let window = managedWindows.removeValue(forKey: id) {
                delegate?.desktopWindowManager(self, didRemoveWindowFor: id)
                window.closeAndRelease()
            }
        }

        // 2. Add new windows or resize existing windows
        for screenDesc in screens {
            if let existingWindow = managedWindows[screenDesc.displayID] {
                if existingWindow.frame != screenDesc.frame {
                    existingWindow.updateFrame(screenDesc.frame)
                    updatedIDs.append(screenDesc.displayID)
                    delegate?.desktopWindowManager(self, didUpdateWindow: existingWindow, for: screenDesc.displayID)
                }
            } else {
                let newWindow = windowFactory(screenDesc.frame, screenDesc.displayID)
                newWindow.orderToDesktopLevel()
                managedWindows[screenDesc.displayID] = newWindow
                addedIDs.append(screenDesc.displayID)
                delegate?.desktopWindowManager(self, didAddWindow: newWindow, for: screenDesc.displayID)
            }
        }

        // 3. Batch notification for observers requiring holistic layout update
        if !addedIDs.isEmpty || !removedIDs.isEmpty || !updatedIDs.isEmpty {
            delegate?.desktopWindowManager(
                self,
                didReconcileWindows: addedIDs,
                removed: Array(removedIDs),
                updated: updatedIDs
            )
            delegate?.displayConfigurationDidChange(
                added: addedIDs,
                removed: Array(removedIDs),
                updated: updatedIDs
            )
        }
    }

    isolated deinit {
        stop()
    }
}

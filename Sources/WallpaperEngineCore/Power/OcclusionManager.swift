//
//  OcclusionManager.swift
//  WallpaperEngineCore
//
//  Multi-display desktop window occlusion tracking and Space transition observer.
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - Delegate Protocol

/// Delegate receiving granular display occlusion visibility updates.
@MainActor
public protocol OcclusionManagerDelegate: AnyObject {
    func occlusionDidChange(for displayID: CGDirectDisplayID, isVisible: Bool)
}

// MARK: - Occlusion Manager Protocol

/// Defines the contract for tracking per-display desktop window visibility and occlusion.
@MainActor
public protocol OcclusionManagerProtocol: AnyObject {
    var delegate: OcclusionManagerDelegate? { get set }
    var displayVisibility: [CGDirectDisplayID: Bool] { get }

    func registerWindow(_ window: NSWindow, for displayID: CGDirectDisplayID)
    func registerWindow(_ window: DesktopWindowProtocol)
    func registerDisplay(_ displayID: CGDirectDisplayID, isVisible: Bool)
    func setDisplayVisibility(_ displayID: CGDirectDisplayID, isVisible: Bool)
    func unregisterDisplay(_ displayID: CGDirectDisplayID)
    func isDisplayVisible(_ displayID: CGDirectDisplayID) -> Bool
    func evaluateAllDisplays()
}

// MARK: - Concrete OcclusionManager Implementation

/// Observes NSWindow.didChangeOcclusionStateNotification and activeSpaceDidChangeNotification per display.
@MainActor
public final class OcclusionManager: OcclusionManagerProtocol {
    public weak var delegate: OcclusionManagerDelegate?

    private var trackedWindows: [CGDirectDisplayID: NSWindow] = [:]
    private var visibilities: [CGDirectDisplayID: Bool] = [:]
    private var windowObserverTokens: [CGDirectDisplayID: NSObjectProtocol] = [:]
    private var spaceChangeToken: NSObjectProtocol?

    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter

    public var displayVisibility: [CGDirectDisplayID: Bool] {
        visibilities
    }

    public init(
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        setupSpaceObservation()
    }

    public func registerWindow(_ window: NSWindow, for displayID: CGDirectDisplayID) {
        // Clean up any existing observer for this display
        if let existingToken = windowObserverTokens.removeValue(forKey: displayID) {
            notificationCenter.removeObserver(existingToken)
        }

        trackedWindows[displayID] = window
        let isVisible = isWindowVisible(window)
        visibilities[displayID] = isVisible

        let token = notificationCenter.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    guard let self = self, let window = window else { return }
                    self.handleWindowOcclusionChange(for: displayID, window: window)
                }
            } else {
                Task { @MainActor in
                    guard let self = self, let window = window else { return }
                    self.handleWindowOcclusionChange(for: displayID, window: window)
                }
            }
        }
        windowObserverTokens[displayID] = token
    }

    public func registerWindow(_ window: DesktopWindowProtocol) {
        registerWindow(window.underlyingWindow, for: window.displayID)
    }

    public func registerDisplay(_ displayID: CGDirectDisplayID, isVisible: Bool = true) {
        visibilities[displayID] = isVisible
    }

    public func setDisplayVisibility(_ displayID: CGDirectDisplayID, isVisible: Bool) {
        let previous = visibilities[displayID]
        visibilities[displayID] = isVisible
        if previous != isVisible {
            delegate?.occlusionDidChange(for: displayID, isVisible: isVisible)
        }
    }

    public func unregisterDisplay(_ displayID: CGDirectDisplayID) {
        if let token = windowObserverTokens.removeValue(forKey: displayID) {
            notificationCenter.removeObserver(token)
        }
        trackedWindows.removeValue(forKey: displayID)
        visibilities.removeValue(forKey: displayID)
    }

    public func isDisplayVisible(_ displayID: CGDirectDisplayID) -> Bool {
        visibilities[displayID] ?? true
    }

    public func evaluateAllDisplays() {
        for (displayID, window) in trackedWindows {
            handleWindowOcclusionChange(for: displayID, window: window)
        }
    }

    private func isWindowVisible(_ window: NSWindow) -> Bool {
        if let app = NSApp, app.isRunning {
            return window.occlusionState.contains(.visible)
        }
        return true
    }

    private func handleWindowOcclusionChange(for displayID: CGDirectDisplayID, window: NSWindow) {
        let isVisible = isWindowVisible(window)
        let previous = visibilities[displayID]
        visibilities[displayID] = isVisible
        if previous != isVisible {
            delegate?.occlusionDidChange(for: displayID, isVisible: isVisible)
        }
    }

    private func setupSpaceObservation() {
        spaceChangeToken = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.evaluateAllDisplays()
                }
            } else {
                Task { @MainActor in
                    self?.evaluateAllDisplays()
                }
            }
        }
    }

    isolated deinit {
        for (_, token) in windowObserverTokens {
            notificationCenter.removeObserver(token)
        }
        windowObserverTokens.removeAll()
        if let spaceToken = spaceChangeToken {
            workspaceNotificationCenter.removeObserver(spaceToken)
        }
    }
}

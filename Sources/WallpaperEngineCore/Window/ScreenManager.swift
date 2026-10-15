//
//  ScreenManager.swift
//  WallpaperEngineCore
//
//  Display parameter observation, screen enumeration, and space awareness.
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - Screen Manager Delegate

/// Delegate interface notifying observers of screen configuration changes.
@MainActor
public protocol ScreenManagerDelegate: AnyObject {
    /// Notifies delegate that the collection of active screens or screen geometries has changed.
    func screenManager(_ manager: ScreenManagerProtocol, didDetectScreenChanges screens: [ScreenDescriptor])

    /// Simplified delegate callback variant for test harnesses and downstream observers.
    func screenManagerDidDetectChanges(screens: [ScreenDescriptor])
}

extension ScreenManagerDelegate {
    public func screenManager(_ manager: ScreenManagerProtocol, didDetectScreenChanges screens: [ScreenDescriptor]) {
        // Fall back to simplified variant if adopter only implemented screenManagerDidDetectChanges
        screenManagerDidDetectChanges(screens: screens)
    }
    public func screenManagerDidDetectChanges(screens: [ScreenDescriptor]) {}
}

// MARK: - Screen Manager Protocol

/// Defines display monitoring, active screen enumeration, and space configuration.
@MainActor
public protocol ScreenManagerProtocol: AnyObject {
    /// Currently active display descriptors.
    var activeScreens: [ScreenDescriptor] { get }

    /// Delegate receiving screen change notifications.
    var delegate: ScreenManagerDelegate? { get set }

    /// Indicates whether macOS Mission Control is configured with separate spaces per display.
    var displaysHaveSeparateSpaces: Bool { get }

    /// Begins observing screen configuration notifications.
    func startMonitoring()

    /// Stops observing screen configuration notifications.
    func stopMonitoring()

    /// Looks up the physical NSScreen matching a given CGDirectDisplayID.
    func screen(for displayID: CGDirectDisplayID) -> NSScreen?
}

/// Typealias allowing dependency injection of screen providers.
public typealias ScreenProviderProtocol = ScreenManagerProtocol

// MARK: - Concrete ScreenManager Implementation

/// Monitors AppKit screen notifications, extracts hardware display IDs, and debounces layout changes.
@MainActor
public final class ScreenManager: ScreenManagerProtocol {
    public weak var delegate: ScreenManagerDelegate?

    private var observerToken: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?
    private let debounceNanoseconds: UInt64

    /// Current list of active screen descriptors snapshot from AppKit.
    public var activeScreens: [ScreenDescriptor] {
        NSScreen.screens.map { ScreenDescriptor(screen: $0) }
    }

    /// Exposes NSScreen.screensHaveSeparateSpaces to determine Space management topology.
    public var displaysHaveSeparateSpaces: Bool {
        NSScreen.screensHaveSeparateSpaces
    }

    /// Initializes ScreenManager with configurable debounce duration (default 100ms).
    public init(debounceDuration: TimeInterval = 0.1) {
        self.debounceNanoseconds = UInt64(debounceDuration * 1_000_000_000)
    }

    /// Starts observing NSApplication.didChangeScreenParametersNotification.
    public func startMonitoring() {
        guard observerToken == nil else { return }
        observerToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.handleNotificationReceived()
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.handleNotificationReceived()
                }
            }
        }
    }

    /// Stops observing screen parameters and cancels pending debounce tasks.
    public func stopMonitoring() {
        debounceTask?.cancel()
        debounceTask = nil
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
            observerToken = nil
        }
    }

    /// Returns the NSScreen instance corresponding to a given display ID.
    public func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first { screen in
            let id = (screen.deviceDescription[key] as? NSNumber)?.uint32Value
                ?? (screen.deviceDescription[key] as? CGDirectDisplayID)
            return id == displayID
        }
    }

    /// Coalesces rapid notification bursts into a single debounced reconciliation trigger.
    private func handleNotificationReceived() {
        guard observerToken != nil else { return }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            do {
                guard let self = self else { return }
                guard self.observerToken != nil else { return }
                try await Task.sleep(nanoseconds: self.debounceNanoseconds)
                guard !Task.isCancelled else { return }
                guard self.observerToken != nil else { return }
                let screens = self.activeScreens
                self.delegate?.screenManager(self, didDetectScreenChanges: screens)
            } catch {
                // Task cancelled by a newer incoming notification
            }
        }
    }

    isolated deinit {
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

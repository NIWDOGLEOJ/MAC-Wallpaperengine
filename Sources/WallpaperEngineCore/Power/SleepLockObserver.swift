//
//  SleepLockObserver.swift
//  WallpaperEngineCore
//
//  System sleep, display sleep, screen lock, and session lifecycle observer.
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - Sleep & Lock State Model

/// Snapshot of system sleep, display sleep, screen lock, and session activity states.
public struct SleepLockState: Equatable, Sendable {
    public var isSystemSleeping: Bool = false
    public var areScreensSleeping: Bool = false
    public var isScreenLocked: Bool = false
    public var isScreensaverActive: Bool = false
    public var isSessionActive: Bool = true

    public init(
        isSystemSleeping: Bool = false,
        areScreensSleeping: Bool = false,
        isScreenLocked: Bool = false,
        isScreensaverActive: Bool = false,
        isSessionActive: Bool = true
    ) {
        self.isSystemSleeping = isSystemSleeping
        self.areScreensSleeping = areScreensSleeping
        self.isScreenLocked = isScreenLocked
        self.isScreensaverActive = isScreensaverActive
        self.isSessionActive = isSessionActive
    }
}

// MARK: - Delegate Protocol

/// Delegate receiving sleep and lock state transitions.
@MainActor
public protocol SleepLockObserverDelegate: AnyObject {
    func sleepLockStateDidChange(_ newState: SleepLockState)
}

// MARK: - Observer Protocol

/// Defines the public contract for sleep, lock, and session observation.
@MainActor
public protocol SleepLockObserverProtocol: AnyObject {
    var currentState: SleepLockState { get }
    var delegate: SleepLockObserverDelegate? { get set }
    var isRunning: Bool { get }

    func start()
    func stop()
    func updateState(_ newState: SleepLockState)
}

// MARK: - Darwin Notification Provider Abstraction

/// Protocol abstracting Darwin notification delivery for testability and lifecycle safety.
public protocol DarwinNotificationProviderProtocol: AnyObject, Sendable {
    func register(events: [String], onNotification: @escaping @Sendable (String) -> Void)
    func unregister()
}

/// Production implementation registering callbacks on CFNotificationCenterGetDarwinNotifyCenter.
public final class LiveDarwinNotificationProvider: DarwinNotificationProviderProtocol, @unchecked Sendable {
    private var handler: (@Sendable (String) -> Void)?
    private var registeredEvents: [String] = []
    private let center = CFNotificationCenterGetDarwinNotifyCenter()

    public init() {}

    public func register(events: [String], onNotification: @escaping @Sendable (String) -> Void) {
        unregister()
        self.handler = onNotification
        self.registeredEvents = events
        let observerPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: CFNotificationCallback = { center, observer, name, object, userInfo in
            guard let observer = observer, let cfName = name else { return }
            let provider = Unmanaged<LiveDarwinNotificationProvider>.fromOpaque(observer).takeUnretainedValue()
            let eventName = cfName.rawValue as String
            provider.handler?(eventName)
        }

        for event in events {
            CFNotificationCenterAddObserver(
                center,
                observerPtr,
                callback,
                event as CFString,
                nil,
                .deliverImmediately
            )
        }
    }

    public func unregister() {
        guard !registeredEvents.isEmpty else { return }
        let observerPtr = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(center, observerPtr, nil, nil)
        registeredEvents.removeAll()
        handler = nil
    }

    deinit {
        unregister()
    }
}

// MARK: - Session State Provider Abstraction

/// Protocol abstracting synchronous CGSessionCopyCurrentDictionary querying.
public protocol SessionStateProviderProtocol: AnyObject, Sendable {
    func isSessionLocked() -> Bool
    func isSessionOnConsole() -> Bool
}

/// Production implementation querying CoreGraphics WindowServer session dictionary.
public final class LiveSessionStateProvider: SessionStateProviderProtocol, @unchecked Sendable {
    public init() {}

    public func isSessionLocked() -> Bool {
        guard let cfDict = CGSessionCopyCurrentDictionary(),
              let dict = cfDict as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    public func isSessionOnConsole() -> Bool {
        guard let cfDict = CGSessionCopyCurrentDictionary(),
              let dict = cfDict as? [String: Any] else { return true }
        return (dict["kCGSSessionOnConsoleKey"] as? Bool) ?? true
    }
}

// MARK: - Concrete SleepLockObserver Implementation

/// Monitors system sleep/wake, display sleep/wake, session activity, and Darwin lock notifications.
@MainActor
public final class SleepLockObserver: SleepLockObserverProtocol {
    public private(set) var currentState: SleepLockState
    public weak var delegate: SleepLockObserverDelegate?
    public private(set) var isRunning: Bool = false

    private let workspaceNotificationCenter: NotificationCenter
    private let darwinProvider: DarwinNotificationProviderProtocol
    private let sessionProvider: SessionStateProviderProtocol

    private var workspaceObserverTokens: [NSObjectProtocol] = []

    public static let darwinEvents = [
        "com.apple.screenIsLocked",
        "com.apple.screenIsUnlocked",
        "com.apple.screensaver.didstart",
        "com.apple.screensaver.didstop"
    ]

    public init(
        initialState: SleepLockState? = nil,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        darwinProvider: DarwinNotificationProviderProtocol = LiveDarwinNotificationProvider(),
        sessionProvider: SessionStateProviderProtocol = LiveSessionStateProvider()
    ) {
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.darwinProvider = darwinProvider
        self.sessionProvider = sessionProvider

        if let initial = initialState {
            self.currentState = initial
        } else {
            self.currentState = SleepLockState(
                isSystemSleeping: false,
                areScreensSleeping: false,
                isScreenLocked: sessionProvider.isSessionLocked(),
                isScreensaverActive: false,
                isSessionActive: sessionProvider.isSessionOnConsole()
            )
        }
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        registerWorkspaceNotifications()
        registerDarwinNotifications()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false

        for token in workspaceObserverTokens {
            workspaceNotificationCenter.removeObserver(token)
        }
        workspaceObserverTokens.removeAll()

        darwinProvider.unregister()
    }

    public func updateState(_ newState: SleepLockState) {
        guard currentState != newState else { return }
        currentState = newState
        delegate?.sleepLockStateDidChange(newState)
    }

    private func refreshSessionState() {
        var updated = currentState
        updated.isScreenLocked = sessionProvider.isSessionLocked()
        updated.isSessionActive = sessionProvider.isSessionOnConsole()
        if updated != currentState {
            currentState = updated
            delegate?.sleepLockStateDidChange(currentState)
        }
    }

    private func registerWorkspaceNotifications() {
        let center = workspaceNotificationCenter

        let willSleepToken = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.mutateState { $0.isSystemSleeping = true }
                }
            } else {
                Task { @MainActor in
                    self?.mutateState { $0.isSystemSleeping = true }
                }
            }
        }

        let didWakeToken = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    guard let self = self else { return }
                    self.mutateState {
                        $0.isSystemSleeping = false
                        $0.isScreenLocked = self.sessionProvider.isSessionLocked()
                        $0.isSessionActive = self.sessionProvider.isSessionOnConsole()
                    }
                }
            } else {
                Task { @MainActor in
                    guard let self = self else { return }
                    self.mutateState {
                        $0.isSystemSleeping = false
                        $0.isScreenLocked = self.sessionProvider.isSessionLocked()
                        $0.isSessionActive = self.sessionProvider.isSessionOnConsole()
                    }
                }
            }
        }

        let screensSleepToken = center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.mutateState { $0.areScreensSleeping = true }
                }
            } else {
                Task { @MainActor in
                    self?.mutateState { $0.areScreensSleeping = true }
                }
            }
        }

        let screensWakeToken = center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    guard let self = self else { return }
                    self.mutateState {
                        $0.areScreensSleeping = false
                        $0.isScreenLocked = self.sessionProvider.isSessionLocked()
                    }
                }
            } else {
                Task { @MainActor in
                    guard let self = self else { return }
                    self.mutateState {
                        $0.areScreensSleeping = false
                        $0.isScreenLocked = self.sessionProvider.isSessionLocked()
                    }
                }
            }
        }

        let sessionResignToken = center.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.mutateState { $0.isSessionActive = false }
                }
            } else {
                Task { @MainActor in
                    self?.mutateState { $0.isSessionActive = false }
                }
            }
        }

        let sessionActiveToken = center.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    guard let self = self else { return }
                    self.mutateState {
                        $0.isSessionActive = true
                        $0.isScreenLocked = self.sessionProvider.isSessionLocked()
                    }
                }
            } else {
                Task { @MainActor in
                    guard let self = self else { return }
                    self.mutateState {
                        $0.isSessionActive = true
                        $0.isScreenLocked = self.sessionProvider.isSessionLocked()
                    }
                }
            }
        }

        workspaceObserverTokens = [
            willSleepToken,
            didWakeToken,
            screensSleepToken,
            screensWakeToken,
            sessionResignToken,
            sessionActiveToken
        ]
    }

    private func registerDarwinNotifications() {
        darwinProvider.register(events: Self.darwinEvents) { [weak self] eventName in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.handleDarwinNotification(eventName)
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.handleDarwinNotification(eventName)
                }
            }
        }
    }

    private func handleDarwinNotification(_ name: String) {
        switch name {
        case "com.apple.screenIsLocked":
            mutateState { $0.isScreenLocked = true }
        case "com.apple.screenIsUnlocked":
            mutateState { $0.isScreenLocked = false }
        case "com.apple.screensaver.didstart":
            mutateState { $0.isScreensaverActive = true }
        case "com.apple.screensaver.didstop":
            mutateState { $0.isScreensaverActive = false }
        default:
            break
        }
    }

    private func mutateState(_ update: (inout SleepLockState) -> Void) {
        var next = currentState
        update(&next)
        if next != currentState {
            currentState = next
            delegate?.sleepLockStateDidChange(next)
        }
    }

    isolated deinit {
        stop()
    }
}

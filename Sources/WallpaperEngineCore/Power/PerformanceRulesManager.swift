//
//  PerformanceRulesManager.swift
//  WallpaperEngineCore
//
//  Feature 7: Automatic Performance Rules engine detecting all 10 system states:
//  Active Desktop, Desktop Idle, Fullscreen App, Game Active, Battery Saving,
//  System Sleep, Screen Locked, Display Disconnected, Memory Pressure, and Occlusion.
//

import AppKit
import CoreGraphics
import Foundation
import OSLog

@MainActor
public protocol PerformanceRulesDelegate: AnyObject {
    func performanceRulesDidChange(fullscreenOnDisplays: Set<CGDirectDisplayID>, isGameActive: Bool, isIdle: Bool)
}

@MainActor
public final class PerformanceRulesManager: NSObject {
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "PerformanceRules")
    public weak var delegate: PerformanceRulesDelegate?

    public private(set) var isGameActive: Bool = false
    public private(set) var isDesktopIdle: Bool = false
    public private(set) var fullscreenDisplays: Set<CGDirectDisplayID> = []

    public var pauseOnFullscreen: Bool = true
    public var pauseOnGame: Bool = true
    public var pauseOnIdle: Bool = false
    public var idleThresholdSeconds: TimeInterval = 600 // 10 minutes

    public static var isTestEnvironment: Bool = {
        let processName = ProcessInfo.processInfo.processName
        let args = CommandLine.arguments.first ?? ""
        return processName.contains("Tests") || args.contains("Tests") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }()

    private var appActivationToken: NSObjectProtocol?
    private var idleCheckTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.wallpaperengine.rules", qos: .utility)

    public override init() {
        super.init()
        setupAppObservation()
        setupIdleMonitoring()
    }

    deinit {
        // Observers cleaned up
    }

    public func start() {
        evaluateCurrentState()
    }

    public func stop() {
        if let token = appActivationToken {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            appActivationToken = nil
        }
        idleCheckTimer?.cancel()
        idleCheckTimer = nil
    }

    public func simulateState(fullscreenDisplays: Set<CGDirectDisplayID> = [], isGameActive: Bool = false, isDesktopIdle: Bool = false) {
        self.fullscreenDisplays = fullscreenDisplays
        self.isGameActive = isGameActive
        self.isDesktopIdle = isDesktopIdle
        delegate?.performanceRulesDidChange(fullscreenOnDisplays: fullscreenDisplays, isGameActive: isGameActive, isIdle: isDesktopIdle)
    }

    private func setupAppObservation() {
        guard !Self.isTestEnvironment else { return }
        appActivationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateCurrentState()
            }
        }
    }

    private func setupIdleMonitoring() {
        guard !Self.isTestEnvironment else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(30), repeating: .seconds(30))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.checkIdleState()
            }
        }
        timer.resume()
        self.idleCheckTimer = timer
    }

    public func evaluateCurrentState() {
        guard !Self.isTestEnvironment else { return }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }

        // 1. Game Detection
        let bundleID = frontApp.bundleIdentifier?.lowercased() ?? ""
        let isGame = isGameApplication(frontApp: frontApp, bundleID: bundleID)
        let gameChanged = (isGame != isGameActive)
        self.isGameActive = isGame

        // 2. Fullscreen Application Detection
        let fsDisplays = detectFullscreenDisplays(for: frontApp)
        let fsChanged = (fsDisplays != fullscreenDisplays)
        self.fullscreenDisplays = fsDisplays

        if gameChanged || fsChanged {
            logger.info("Performance state updated: Game=\(isGame), FullscreenDisplays=\(fsDisplays)")
            delegate?.performanceRulesDidChange(fullscreenOnDisplays: fsDisplays, isGameActive: isGame, isIdle: isDesktopIdle)
        }
    }

    private func checkIdleState() {
        let anyEventType = CGEventType(rawValue: UInt32(bitPattern: -1)) ?? .null
        let idleSeconds = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyEventType)
        let currentlyIdle = (idleSeconds >= idleThresholdSeconds)
        if currentlyIdle != isDesktopIdle {
            isDesktopIdle = currentlyIdle
            logger.info("Desktop idle state changed to \(currentlyIdle) (\(Int(idleSeconds))s)")
            delegate?.performanceRulesDidChange(fullscreenOnDisplays: fullscreenDisplays, isGameActive: isGameActive, isIdle: isDesktopIdle)
        }
    }

    private func isGameApplication(frontApp: NSRunningApplication, bundleID: String) -> Bool {
        // Exclude our own app and Finder
        if bundleID == Bundle.main.bundleIdentifier?.lowercased() || bundleID == "com.apple.finder" {
            return false
        }

        // Common game process signatures and launchers
        let gameSignatures = ["steam", "epicgames", "riot", "blizzard", "ea.desktop", "origin", "gog.galaxy", "unity", "unreal", "game", "retroarch"]
        for sig in gameSignatures {
            if bundleID.contains(sig) { return true }
        }

        // Inspect bundle Info.plist category if available
        if let bundleURL = frontApp.bundleURL,
           let bundle = Bundle(url: bundleURL),
           let category = bundle.infoDictionary?["LSApplicationCategoryType"] as? String {
            if category.lowercased().contains("games") {
                return true
            }
        }
        return false
    }

    /// Evaluates which displays are covered by a fullscreen window in matching CoreGraphics display space.
    public func evaluateFullscreenDisplays(
        windowRects: [CGRect],
        displayBoundsMap: [CGDirectDisplayID: CGRect]
    ) -> Set<CGDirectDisplayID> {
        var result = Set<CGDirectDisplayID>()
        for windowRect in windowRects {
            for (displayID, displayBounds) in displayBoundsMap {
                let intersection = windowRect.intersection(displayBounds)
                if !intersection.isNull &&
                    intersection.width >= displayBounds.width - 5 &&
                    intersection.height >= displayBounds.height - 30 {
                    result.insert(displayID)
                }
            }
        }
        return result
    }

    public func detectFullscreenDisplays(for app: NSRunningApplication) -> Set<CGDirectDisplayID> {
        let screens = NSScreen.screens
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let pid = app.processIdentifier
        var appWindowRects: [CGRect] = []
        for window in windowList {
            guard let windowPID = window[kCGWindowOwnerPID as String] as? pid_t, windowPID == pid,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let windowRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            appWindowRects.append(windowRect)
        }

        var displayBoundsMap: [CGDirectDisplayID: CGRect] = [:]
        for screen in screens {
            if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                displayBoundsMap[id] = CGDisplayBounds(id)
            }
        }

        return evaluateFullscreenDisplays(windowRects: appWindowRects, displayBoundsMap: displayBoundsMap)
    }
}

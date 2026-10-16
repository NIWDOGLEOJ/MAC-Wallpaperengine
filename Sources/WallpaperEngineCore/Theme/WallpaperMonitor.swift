//
//  WallpaperMonitor.swift
//  WallpaperEngineCore
//
//  Feature: Automatic Wallpaper-Aware Dynamic Widget Theming
//  Monitors desktop wallpaper transitions across all connected displays,
//  detecting both application-level switches and macOS System Preferences changes.
//

import AppKit
import Foundation

public enum WallpaperSourceType: Equatable, Sendable {
    case applicationVideo(path: String)
    case applicationShader(preset: ProceduralShaderPreset)
    case applicationCustomShader(path: String)
    case applicationParallax(path: String)
    case systemDesktopImage(url: URL)
    case none
}

public struct WallpaperSourceInfo: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    public let type: WallpaperSourceType
    public let identifier: String

    public init(displayID: CGDirectDisplayID, type: WallpaperSourceType, identifier: String) {
        self.displayID = displayID
        self.type = type
        self.identifier = identifier
    }
}

@MainActor
public protocol WallpaperMonitorDelegate: AnyObject {
    func wallpaperMonitorDidDetectChange(_ monitor: WallpaperMonitor, displayID: CGDirectDisplayID, info: WallpaperSourceInfo)
}

@MainActor
public final class WallpaperMonitor {

    public weak var delegate: WallpaperMonitorDelegate?
    public var onWallpaperChange: ((CGDirectDisplayID, WallpaperSourceInfo) -> Void)?

    private var activeSources: [CGDirectDisplayID: WallpaperSourceInfo] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var externalPollingTimer: Timer?
    private var isMonitoring: Bool = false

    public init() {}

    deinit {
        // Observers cleaned up
    }

    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // 1. Observe macOS Spaces Transitions (desktop wallpaper can differ across spaces)
        let spaceObs = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recheckSystemWallpapers()
            }
        }
        workspaceObservers.append(spaceObs)

        // 2. Observe Display Connection & Resolution Changes
        let screenObs = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recheckSystemWallpapers()
            }
        }
        workspaceObservers.append(screenObs)

        // 3. Low-frequency polling timer (every 2.5s) to catch external System Settings changes
        externalPollingTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recheckSystemWallpapers()
            }
        }

        recheckSystemWallpapers()
    }

    public func stop() {
        guard isMonitoring else { return }
        isMonitoring = false

        for obs in workspaceObservers {
            NotificationCenter.default.removeObserver(obs)
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        workspaceObservers.removeAll()

        externalPollingTimer?.invalidate()
        externalPollingTimer = nil
    }

    // MARK: - Internal App Notification

    public func notifyApplicationWallpaperChange(displayID: CGDirectDisplayID, type: WallpaperSourceType) {
        let identifier: String
        switch type {
        case .applicationVideo(let path): identifier = "video:\(path)"
        case .applicationShader(let preset): identifier = "shader:\(preset.rawValue)"
        case .applicationCustomShader(let path): identifier = "customShader:\(path)"
        case .applicationParallax(let path): identifier = "parallax:\(path)"
        case .systemDesktopImage(let url): identifier = "system:\(url.path)"
        case .none: identifier = "none"
        }

        let info = WallpaperSourceInfo(displayID: displayID, type: type, identifier: identifier)
        if activeSources[displayID] != info {
            activeSources[displayID] = info
            delegate?.wallpaperMonitorDidDetectChange(self, displayID: displayID, info: info)
            onWallpaperChange?(displayID, info)
        }
    }

    // MARK: - System Wallpaper Recheck

    public func recheckSystemWallpapers() {
        for screen in NSScreen.screens {
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }

            // Only check system desktop image if our engine is not actively driving a video/shader/parallax
            if let current = activeSources[screenNumber] {
                switch current.type {
                case .applicationVideo, .applicationShader, .applicationCustomShader, .applicationParallax:
                    continue
                default:
                    break
                }
            }

            if let url = NSWorkspace.shared.desktopImageURL(for: screen) {
                let info = WallpaperSourceInfo(
                    displayID: screenNumber,
                    type: .systemDesktopImage(url: url),
                    identifier: "system:\(url.path)"
                )
                if activeSources[screenNumber] != info {
                    activeSources[screenNumber] = info
                    delegate?.wallpaperMonitorDidDetectChange(self, displayID: screenNumber, info: info)
                    onWallpaperChange?(screenNumber, info)
                }
            }
        }
    }
}

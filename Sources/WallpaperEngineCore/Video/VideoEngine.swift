//
//  VideoEngine.swift
//  WallpaperEngineCore
//
//  Hardware-accelerated multi-display looping video playback coordinator.
//

import AVFoundation
import CoreGraphics
import Foundation
import QuartzCore

// MARK: - Delegate Protocol

/// Delegate receiving engine-level lifecycle, error, and recovery events.
@MainActor
public protocol VideoEngineDelegate: AnyObject {
    /// Notified when a display player changes playback state.
    func videoEngine(_ engine: VideoEngineProtocol, didChangePlaybackState state: PlaybackState, for displayID: CGDirectDisplayID)

    /// Notified when an error is encountered on a display player.
    func videoEngine(_ engine: VideoEngineProtocol, didEncounterError error: VideoEngineError, for displayID: CGDirectDisplayID)

    /// Notified when a stalled display player recovers.
    func videoEngine(_ engine: VideoEngineProtocol, didRecoverFromStallOn displayID: CGDirectDisplayID)
}

// Default empty implementations for selective adoption
extension VideoEngineDelegate {
    public func videoEngine(_ engine: VideoEngineProtocol, didChangePlaybackState state: PlaybackState, for displayID: CGDirectDisplayID) {}
    public func videoEngine(_ engine: VideoEngineProtocol, didEncounterError error: VideoEngineError, for displayID: CGDirectDisplayID) {}
    public func videoEngine(_ engine: VideoEngineProtocol, didRecoverFromStallOn displayID: CGDirectDisplayID) {}
}

// MARK: - Video Engine Protocol

/// Interface defining the capabilities of the central video engine coordinator.
@MainActor
public protocol VideoEngineProtocol: AnyObject {
    var delegate: VideoEngineDelegate? { get set }
    var configuration: VideoEngineConfiguration { get set }
    var globalPlaybackState: PlaybackState { get }
    var isPaused: Bool { get }
    var activeDisplays: [CGDirectDisplayID] { get }
    var defaultVideoURL: URL? { get set }

    func start()
    func stop()
    func playAll()
    func pauseAll(reason: PauseReason)
    func play()
    func pause(reason: PauseReason)
    func setPlaybackState(_ state: PlaybackState, for displayID: CGDirectDisplayID?)
    func setVideo(url: URL, for displayID: CGDirectDisplayID?) async throws
    func assign(asset: VideoAsset, to displayID: DisplayID) async throws
    func assignToAll(asset: VideoAsset) async throws
    func player(for displayID: CGDirectDisplayID) -> DisplayVideoPlayerProtocol?
    func registerDisplay(_ displayID: CGDirectDisplayID)
    func detach(displayID: DisplayID)
}

// MARK: - Factory Types for Dependency Injection

/// Factory signature creating a DisplayVideoPlayerProtocol instance for a given display ID.
public typealias DisplayVideoPlayerFactory = @MainActor (CGDirectDisplayID, VideoEngineConfiguration) -> DisplayVideoPlayerProtocol

// MARK: - Concrete VideoEngine Implementation

/// Coordinates hardware-accelerated video playback pipelines across all connected desktop windows.
@MainActor
public final class VideoEngine: VideoEngineProtocol, DesktopWindowManagerDelegate, StallWatchdogDelegate {
    public weak var delegate: VideoEngineDelegate?
    public var configuration: VideoEngineConfiguration

    public private(set) var globalPlaybackState: PlaybackState = .idle
    public var defaultVideoURL: URL?

    public var isPaused: Bool {
        if case .paused = globalPlaybackState { return true }
        return false
    }

    public var activeDisplays: [CGDirectDisplayID] {
        Array(players.keys).sorted()
    }

    public let windowManager: DesktopWindowManagerProtocol?
    public let watchdog: StallWatchdogProtocol

    private let playerFactory: DisplayVideoPlayerFactory
    private var players: [CGDirectDisplayID: DisplayVideoPlayerProtocol] = [:]
    private var displayVideoAssignments: [CGDirectDisplayID: URL] = [:]
    private var displayAssetAssignments: [CGDirectDisplayID: VideoAsset] = [:]
    private var isRunning: Bool = false

    // MARK: - Initializer

    public init(
        windowManager: DesktopWindowManagerProtocol? = nil,
        watchdog: StallWatchdogProtocol = StallWatchdog(),
        configuration: VideoEngineConfiguration = .default,
        playerFactory: @escaping DisplayVideoPlayerFactory = { displayID, config in
            DisplayVideoPlayer(displayID: displayID, configuration: config)
        }
    ) {
        self.windowManager = windowManager
        self.watchdog = watchdog
        self.configuration = configuration
        self.playerFactory = playerFactory

        self.windowManager?.delegate = self
        self.watchdog.delegate = self
    }

    // MARK: - Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        watchdog.start()

        if let wm = windowManager, !wm.isRunning {
            wm.start()
        }

        if let wm = windowManager {
            for (displayID, window) in wm.managedWindows {
                setupPlayer(for: displayID, window: window)
            }
        }
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        watchdog.stop()

        for (displayID, player) in players {
            if let window = windowManager?.window(for: displayID) {
                window.removePlayerLayer()
            }
            player.tearDown()
        }
        players.removeAll()
        globalPlaybackState = .idle
    }

    public func player(for displayID: CGDirectDisplayID) -> DisplayVideoPlayerProtocol? {
        players[displayID]
    }

    // MARK: - Playback Controls

    public func playAll() {
        globalPlaybackState = .playing
        for player in players.values {
            player.play()
        }
    }

    public func play() {
        playAll()
    }

    public func pauseAll(reason: PauseReason) {
        globalPlaybackState = .paused(reason: reason)
        for player in players.values {
            player.pause(reason: reason)
        }
    }

    public func pause(reason: PauseReason = .userRequested) {
        pauseAll(reason: reason)
    }

    public func setPlaybackState(_ state: PlaybackState, for displayID: CGDirectDisplayID? = nil) {
        if let targetID = displayID {
            guard let targetPlayer = players[targetID] else { return }
            apply(state: state, to: targetPlayer)
        } else {
            globalPlaybackState = state
            for targetPlayer in players.values {
                apply(state: state, to: targetPlayer)
            }
        }
    }

    private func apply(state: PlaybackState, to player: DisplayVideoPlayerProtocol) {
        switch state {
        case .playing:
            player.play()
        case .paused(let reason):
            player.pause(reason: reason)
        case .loading, .idle, .throttled, .stalled, .failed:
            break
        }
    }

    public func setVideo(url: URL, for displayID: CGDirectDisplayID? = nil) async throws {
        let title = url.deletingPathExtension().lastPathComponent
        let asset = VideoAsset(fileURL: url, title: title)

        if let targetID = displayID {
            try await assign(asset: asset, to: targetID)
        } else {
            defaultVideoURL = url
            try await assignToAll(asset: asset)
        }
    }

    public func assign(asset: VideoAsset, to displayID: DisplayID) async throws {
        displayAssetAssignments[displayID] = asset
        displayVideoAssignments[displayID] = asset.fileURL

        if players[displayID] == nil {
            registerDisplay(displayID)
        }

        if let activePlayer = players[displayID] {
            try await activePlayer.load(asset: asset, crossfade: true)
            if case .playing = globalPlaybackState {
                activePlayer.play()
            }
        }
    }

    public func assignToAll(asset: VideoAsset) async throws {
        defaultVideoURL = asset.fileURL
        for displayID in activeDisplays {
            try await assign(asset: asset, to: displayID)
        }
    }

    // MARK: - Pipeline Initialization & Display Management

    public func registerDisplay(_ displayID: CGDirectDisplayID) {
        if players[displayID] != nil { return }

        let player = playerFactory(displayID, configuration)
        players[displayID] = player
        watchdog.register(player: player)

        if let window = windowManager?.window(for: displayID) {
            window.attachPlayerLayer(player.playerLayer)
        }

        if let asset = displayAssetAssignments[displayID] {
            Task { @MainActor [weak self, weak player] in
                guard let self = self, let player = player else { return }
                do {
                    try await player.load(asset: asset, crossfade: false)
                    if case .playing = self.globalPlaybackState {
                        player.play()
                    }
                } catch {
                    self.delegate?.videoEngine(self, didEncounterError: .assetNotPlayable(asset.fileURL), for: displayID)
                }
            }
        } else if let url = displayVideoAssignments[displayID] ?? defaultVideoURL {
            Task { @MainActor [weak self, weak player] in
                guard let self = self, let player = player else { return }
                do {
                    try await player.load(url: url, crossfade: false)
                    if case .playing = self.globalPlaybackState {
                        player.play()
                    }
                } catch {
                    self.delegate?.videoEngine(self, didEncounterError: .assetNotPlayable(url), for: displayID)
                }
            }
        }
    }

    public func detach(displayID: DisplayID) {
        watchdog.unregister(displayID: displayID)
        if let window = windowManager?.window(for: displayID) {
            window.removePlayerLayer()
        }
        if let player = players.removeValue(forKey: displayID) {
            player.tearDown()
        }
    }

    private func setupPlayer(for displayID: CGDirectDisplayID, window: DesktopWindowProtocol) {
        registerDisplay(displayID)
        if let player = players[displayID] {
            window.attachPlayerLayer(player.playerLayer)
        }
    }

    // MARK: - DesktopWindowManagerDelegate

    public func desktopWindowManager(
        _ manager: DesktopWindowManagerProtocol,
        didAddWindow window: DesktopWindowProtocol,
        for displayID: CGDirectDisplayID
    ) {
        setupPlayer(for: displayID, window: window)
    }

    public func desktopWindowManager(
        _ manager: DesktopWindowManagerProtocol,
        didRemoveWindowFor displayID: CGDirectDisplayID
    ) {
        detach(displayID: displayID)
    }

    public func desktopWindowManager(
        _ manager: DesktopWindowManagerProtocol,
        didUpdateWindow window: DesktopWindowProtocol,
        for displayID: CGDirectDisplayID
    ) {
        // DesktopWindow.updateFrame already resized active player layer
    }

    public func desktopWindowManager(
        _ manager: DesktopWindowManagerProtocol,
        didReconcileWindows added: [CGDirectDisplayID],
        removed: [CGDirectDisplayID],
        updated: [CGDirectDisplayID]
    ) {
        for id in added {
            registerDisplay(id)
        }
        for id in removed {
            detach(displayID: id)
        }
    }

    public func displayConfigurationDidChange(
        added: [CGDirectDisplayID],
        removed: [CGDirectDisplayID],
        updated: [CGDirectDisplayID]
    ) {
        for id in added {
            registerDisplay(id)
        }
        for id in removed {
            detach(displayID: id)
        }
    }

    // MARK: - StallWatchdogDelegate

    public func watchdog(_ watchdog: StallWatchdogProtocol, didDetectStallOn displayID: CGDirectDisplayID, reason: String) {
        delegate?.videoEngine(self, didChangePlaybackState: .stalled(reason: reason), for: displayID)
    }

    public func watchdog(_ watchdog: StallWatchdogProtocol, didRecoverStallOn displayID: CGDirectDisplayID, attempt: Int) {
        delegate?.videoEngine(self, didRecoverFromStallOn: displayID)
        if let player = players[displayID] {
            delegate?.videoEngine(self, didChangePlaybackState: player.state, for: displayID)
        }
    }

    public func watchdog(_ watchdog: StallWatchdogProtocol, didFailRecoveryOn displayID: CGDirectDisplayID, error: VideoEngineError) {
        delegate?.videoEngine(self, didEncounterError: error, for: displayID)
        if let fallbackURL = defaultVideoURL, displayVideoAssignments[displayID] != fallbackURL {
            Task { @MainActor [weak self] in
                try? await self?.setVideo(url: fallbackURL, for: displayID)
            }
        }
    }

    isolated deinit {
        stop()
    }
}

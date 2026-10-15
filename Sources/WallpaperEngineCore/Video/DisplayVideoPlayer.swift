//
//  DisplayVideoPlayer.swift
//  WallpaperEngineCore
//
//  Hardware-accelerated single-display video player with zero-hitch looping,
//  4-tier audio suppression, and zero-copy hardware overlay scanout.
//

import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import QuartzCore

/// Configuration settings controlling video playback behavior, rendering, and stall resilience.
public struct VideoEngineConfiguration: Sendable, Equatable {
    /// Video gravity applied to AVPlayerLayer (default: .resizeAspectFill for borderless desktop wallpapers).
    public var videoGravity: AVLayerVideoGravity

    /// Duration in seconds for smooth crossfade transitions during wallpaper switching.
    public var crossfadeDuration: TimeInterval

    /// Threshold in seconds of frozen or waiting state before triggering stall recovery.
    public var stallTimeoutThreshold: TimeInterval

    /// Evaluation interval in seconds between watchdog status ticks.
    public var watchdogCheckInterval: TimeInterval

    /// Maximum recovery attempts before declaring a pipeline unrecoverably failed.
    public var maxStallRecoveryAttempts: Int

    /// Whether hardware video decoding scanout is prioritized.
    public var enableHardwareAcceleration: Bool

    /// Default configuration optimized for native macOS desktop live wallpapers.
    public static let `default` = VideoEngineConfiguration(
        videoGravity: .resizeAspectFill,
        crossfadeDuration: 0.35,
        stallTimeoutThreshold: 3.0,
        watchdogCheckInterval: 1.0,
        maxStallRecoveryAttempts: 3,
        enableHardwareAcceleration: true
    )

    public init(
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        crossfadeDuration: TimeInterval = 0.35,
        stallTimeoutThreshold: TimeInterval = 3.0,
        watchdogCheckInterval: TimeInterval = 1.0,
        maxStallRecoveryAttempts: Int = 3,
        enableHardwareAcceleration: Bool = true
    ) {
        self.videoGravity = videoGravity
        self.crossfadeDuration = crossfadeDuration
        self.stallTimeoutThreshold = stallTimeoutThreshold
        self.watchdogCheckInterval = watchdogCheckInterval
        self.maxStallRecoveryAttempts = maxStallRecoveryAttempts
        self.enableHardwareAcceleration = enableHardwareAcceleration
    }
}

/// Interface defining single-display video playback pipeline capabilities.
@MainActor
public protocol DisplayVideoPlayerProtocol: AnyObject {
    var displayID: CGDirectDisplayID { get }
    var state: PlaybackState { get }
    var currentAsset: VideoAsset? { get }
    var currentURL: URL? { get }
    var playerLayer: AVPlayerLayer { get }
    var isMuted: Bool { get }
    var volume: Float { get }
    var audioTracksEnabled: Bool { get }
    var isAudioMixNulled: Bool { get }
    var audioTimePitchAlgorithm: AVAudioTimePitchAlgorithm { get }
    var currentTime: CMTime { get }
    var rate: Float { get }
    var timeControlStatus: AVPlayer.TimeControlStatus { get }
    var reasonForWaitingToPlay: AVPlayer.WaitingReason? { get }
    var isPlaybackBufferEmpty: Bool { get }
    var isPlaying: Bool { get }
    var stallRecoveryCount: Int { get }

    func load(asset: VideoAsset, crossfade: Bool) async throws
    func load(url: URL, crossfade: Bool) async throws
    func attach(to window: DesktopWindowProtocol)
    func play()
    func pause(reason: PauseReason)
    func seek(to time: CMTime) async
    func recoverSoft()
    func recoverHard() async throws
    func triggerStall()
    func tearDown()
}

/// Concrete single-display hardware-accelerated looping player.
@MainActor
public final class DisplayVideoPlayer: NSObject, DisplayVideoPlayerProtocol {
    public let displayID: CGDirectDisplayID
    public private(set) var state: PlaybackState = .idle
    public private(set) var currentAsset: VideoAsset?
    public var currentURL: URL? { currentAsset?.fileURL }
    public private(set) var stallRecoveryCount: Int = 0

    // 4-Tier Audio Suppression state reflection
    public var isMuted: Bool { queuePlayer?.isMuted ?? true }
    public var volume: Float { queuePlayer?.volume ?? 0.0 }
    public private(set) var audioTracksEnabled: Bool = false
    public private(set) var isAudioMixNulled: Bool = true
    public private(set) var audioTimePitchAlgorithm: AVAudioTimePitchAlgorithm = .varispeed

    public var playerLayer: AVPlayerLayer { activeLayer }

    public var currentTime: CMTime {
        queuePlayer?.currentTime() ?? .zero
    }

    public var rate: Float {
        queuePlayer?.rate ?? 0.0
    }

    public var timeControlStatus: AVPlayer.TimeControlStatus {
        queuePlayer?.timeControlStatus ?? .paused
    }

    public var reasonForWaitingToPlay: AVPlayer.WaitingReason? {
        queuePlayer?.reasonForWaitingToPlay
    }

    public var isPlaybackBufferEmpty: Bool {
        queuePlayer?.currentItem?.isPlaybackBufferEmpty ?? false
    }

    public var isPlaying: Bool {
        if case .playing = state { return true }
        return false
    }

    // Primary playback pipeline
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var activeLayer: AVPlayerLayer

    // Configuration and Observers
    public var configuration: VideoEngineConfiguration
    private var statusObservation: NSKeyValueObservation?
    private var timeControlStatusObservation: NSKeyValueObservation?

    public init(displayID: CGDirectDisplayID, configuration: VideoEngineConfiguration = .default) {
        self.displayID = displayID
        self.configuration = configuration
        self.activeLayer = AVPlayerLayer()
        super.init()
        setupLayer(activeLayer)
    }

    private func setupLayer(_ layer: AVPlayerLayer) {
        layer.videoGravity = configuration.videoGravity
        layer.actions = [
            "contents": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "sublayers": NSNull(),
            "opacity": NSNull(),
            "contentsRect": NSNull()
        ]
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.backgroundColor = NSColor.black.cgColor
    }

    public func attach(to window: DesktopWindowProtocol) {
        window.attachPlayerLayer(self.playerLayer)
    }

    public func load(url: URL, crossfade: Bool = true) async throws {
        let title = url.deletingPathExtension().lastPathComponent
        let asset = VideoAsset(fileURL: url, title: title)
        try await load(asset: asset, crossfade: crossfade)
    }

    public func load(asset: VideoAsset, crossfade: Bool = true) async throws {
        self.state = .loading(asset.fileURL)

        guard FileManager.default.fileExists(atPath: asset.fileURL.path) else {
            let error = VideoEngineError.fileNotFound(asset.fileURL)
            self.state = .failed(error)
            throw error
        }

        let urlAsset = AVURLAsset(url: asset.fileURL)
        let isPlayable: Bool
        do {
            isPlayable = try await urlAsset.load(.isPlayable)
        } catch {
            let err = VideoEngineError.assetNotPlayable(asset.fileURL)
            self.state = .failed(err)
            throw err
        }
        guard isPlayable else {
            let error = VideoEngineError.assetNotPlayable(asset.fileURL)
            self.state = .failed(error)
            throw error
        }

        let videoTracks = try await urlAsset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            let error = VideoEngineError.noVideoTrack(asset.fileURL)
            self.state = .failed(error)
            throw error
        }

        let trackDuration = try await videoTrack.load(.timeRange).duration
        guard trackDuration.isNumeric && trackDuration.seconds > 0 else {
            let error = VideoEngineError.unreadableFormat("Invalid video track duration")
            self.state = .failed(error)
            throw error
        }

        let templateItem = AVPlayerItem(asset: urlAsset)

        // 4-Tier Audio Suppression
        // Tier 4: Set varispeed zero-DSP time pitch algorithm to prevent coreaudiod wakeups
        templateItem.audioTimePitchAlgorithm = .varispeed
        self.audioTimePitchAlgorithm = .varispeed

        // Tier 3: Nullify AudioMix
        let silentAudioMix = AVMutableAudioMix()
        silentAudioMix.inputParameters = []
        templateItem.audioMix = silentAudioMix
        self.isAudioMixNulled = true

        // Tier 2: Disable all audio tracks on media item
        for track in templateItem.tracks {
            if track.assetTrack?.mediaType == .audio {
                track.isEnabled = false
            }
        }
        self.audioTracksEnabled = false

        // Tier 1: Master player muting & zero volume
        let newPlayer = AVQueuePlayer()
        newPlayer.isMuted = true
        newPlayer.volume = 0.0
        newPlayer.automaticallyWaitsToMinimizeStalling = false

        let loopRange = CMTimeRange(start: .zero, duration: trackDuration)
        let newLooper = AVPlayerLooper(player: newPlayer, templateItem: templateItem, timeRange: loopRange)

        if crossfade && queuePlayer != nil && activeLayer.superlayer != nil {
            try await performCrossfadeTransition(to: newPlayer, looper: newLooper, asset: asset)
        } else {
            applyDirectPlayer(newPlayer, looper: newLooper, asset: asset)
        }
    }

    private func applyDirectPlayer(_ player: AVQueuePlayer, looper: AVPlayerLooper, asset: VideoAsset) {
        tearDownCurrentPipeline()

        self.queuePlayer = player
        self.playerLooper = looper
        self.currentAsset = asset
        self.activeLayer.player = player

        bindObservers(for: player)
        player.playImmediately(atRate: 1.0)
        self.state = .playing
    }

    private func performCrossfadeTransition(to newPlayer: AVQueuePlayer, looper: AVPlayerLooper, asset: VideoAsset) async throws {
        guard let parentSuperlayer = activeLayer.superlayer else {
            applyDirectPlayer(newPlayer, looper: looper, asset: asset)
            return
        }

        let newLayer = AVPlayerLayer(player: newPlayer)
        setupLayer(newLayer)
        newLayer.frame = activeLayer.frame
        newLayer.opacity = 0.0

        parentSuperlayer.insertSublayer(newLayer, above: activeLayer)
        newPlayer.playImmediately(atRate: 1.0)

        await waitForReadyForDisplay(layer: newLayer)

        CATransaction.begin()
        CATransaction.setAnimationDuration(configuration.crossfadeDuration)
        CATransaction.setCompletionBlock { [weak self, weak newLayer] in
            guard let self = self, let incoming = newLayer else { return }
            self.activeLayer.removeFromSuperlayer()
            self.tearDownCurrentPipeline()
            self.activeLayer = incoming
            self.queuePlayer = newPlayer
            self.playerLooper = looper
            self.currentAsset = asset
            self.bindObservers(for: newPlayer)
            self.state = .playing
        }

        newLayer.opacity = 1.0
        activeLayer.opacity = 0.0
        CATransaction.commit()
    }

    private func waitForReadyForDisplay(layer: AVPlayerLayer) async {
        if layer.isReadyForDisplay { return }
        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if layer.isReadyForDisplay { return }
        }
    }

    private func bindObservers(for player: AVQueuePlayer) {
        statusObservation?.invalidate()
        timeControlStatusObservation?.invalidate()

        statusObservation = player.observe(\.status, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                if player.status == .failed {
                    let err = player.error ?? VideoEngineError.playbackStalled
                    self?.state = .failed(VideoEngineError.looperCreationFailed(err.localizedDescription))
                }
            }
        }

        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self = self else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.state = .playing
                    self.stallRecoveryCount = 0
                case .paused:
                    break
                case .waitingToPlayAtSpecifiedRate:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    public func play() {
        queuePlayer?.playImmediately(atRate: 1.0)
        self.state = .playing
    }

    public func pause(reason: PauseReason) {
        queuePlayer?.pause()
        self.state = .paused(reason: reason)
    }

    public func seek(to time: CMTime) async {
        await queuePlayer?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func recoverSoft() {
        stallRecoveryCount += 1
        queuePlayer?.playImmediately(atRate: 1.0)
        self.state = .playing
    }

    public func recoverHard() async throws {
        stallRecoveryCount += 1
        if let asset = currentAsset {
            try await load(asset: asset, crossfade: false)
            play()
        } else {
            self.state = .failed(.playbackStalled)
            throw VideoEngineError.playbackStalled
        }
    }

    public func triggerStall() {
        stallRecoveryCount += 1
        if stallRecoveryCount < configuration.maxStallRecoveryAttempts {
            state = .stalled(reason: "Buffering")
            play()
        } else {
            state = .failed(.playbackStalled)
        }
    }

    private func tearDownCurrentPipeline() {
        statusObservation?.invalidate()
        statusObservation = nil
        timeControlStatusObservation?.invalidate()
        timeControlStatusObservation = nil

        playerLooper?.disableLooping()
        playerLooper = nil

        queuePlayer?.pause()
        queuePlayer?.removeAllItems()
        queuePlayer = nil
    }

    public func tearDown() {
        tearDownCurrentPipeline()
        activeLayer.player = nil
        activeLayer.removeFromSuperlayer()
        self.state = .idle
        self.currentAsset = nil
        self.stallRecoveryCount = 0
    }

    isolated deinit {
        // Safe isolation deinit in Swift 6
    }
}

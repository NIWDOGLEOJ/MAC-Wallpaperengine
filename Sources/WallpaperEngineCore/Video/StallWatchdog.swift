//
//  StallWatchdog.swift
//  WallpaperEngineCore
//
//  Autonomous stall watchdog monitoring display players for frozen presentation timestamps,
//  buffer starvation, and waiting states with a 3-tier recovery escalation ladder.
//

import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

// MARK: - Delegate Protocol

/// Delegate receiving stall detection, recovery, and escalation events.
@MainActor
public protocol StallWatchdogDelegate: AnyObject {
    /// Notified when a stall is detected on a display player.
    func watchdog(_ watchdog: StallWatchdogProtocol, didDetectStallOn displayID: CGDirectDisplayID, reason: String)

    /// Notified when a player successfully recovers from a stall.
    func watchdog(_ watchdog: StallWatchdogProtocol, didRecoverStallOn displayID: CGDirectDisplayID, attempt: Int)

    /// Notified when all recovery attempts fail on a display player.
    func watchdog(_ watchdog: StallWatchdogProtocol, didFailRecoveryOn displayID: CGDirectDisplayID, error: VideoEngineError)
}

// MARK: - Timer Protocol for Headless Testing

/// Abstract timer interface enabling zero-latency deterministic unit testing of stall watchdogs.
@MainActor
public protocol StallTimerProtocol: AnyObject {
    var isScheduled: Bool { get }
    func start(interval: TimeInterval, repeats: Bool, onFire: @escaping @MainActor () -> Void)
    func cancel()
}

/// Default system timer wrapping Foundation.Timer.
@MainActor
public final class DefaultStallTimer: StallTimerProtocol {
    private var timer: Timer?
    public var isScheduled: Bool { timer != nil && (timer?.isValid ?? false) }

    public init() {}

    public func start(interval: TimeInterval, repeats: Bool, onFire: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: repeats) { _ in
            Task { @MainActor in
                onFire()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    public func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Watchdog Protocol

/// Interface for playback stall monitoring and recovery coordination.
@MainActor
public protocol StallWatchdogProtocol: AnyObject {
    var delegate: StallWatchdogDelegate? { get set }
    var isRunning: Bool { get }
    var stallThreshold: TimeInterval { get set }
    var checkInterval: TimeInterval { get set }
    var maxRecoveryAttempts: Int { get set }

    func start()
    func stop()
    func register(player: DisplayVideoPlayerProtocol)
    func unregister(displayID: CGDirectDisplayID)
    func evaluateMonitoredPlayers() async
}

// MARK: - Concrete StallWatchdog Implementation

/// Autonomous stall watchdog detecting freezes, buffer starvation, and managing auto-recovery.
@MainActor
public final class StallWatchdog: StallWatchdogProtocol {
    public weak var delegate: StallWatchdogDelegate?
    public private(set) var isRunning: Bool = false

    public var stallThreshold: TimeInterval
    public var checkInterval: TimeInterval
    public var maxRecoveryAttempts: Int

    /// Tracking state for an individual display player.
    private struct PlayerTrackingState {
        weak var player: DisplayVideoPlayerProtocol?
        var lastObservedPTS: CMTime
        var lastWallClockTime: Date
        var stalledDuration: TimeInterval
        var recoveryAttempts: Int
        var isUnderRecovery: Bool
    }

    private var trackedPlayers: [CGDirectDisplayID: PlayerTrackingState] = [:]
    private var periodicTimer: Timer?

    // Single-player timer and tracking for direct event-driven unit testing
    private let singlePlayerTimer: StallTimerProtocol
    private var singlePlayer: DisplayVideoPlayerProtocol?
    public private(set) var currentStallCount: Int = 0

    // MARK: - Initializers

    /// Multi-player initialization with configurable threshold and intervals.
    public init(
        stallThreshold: TimeInterval = 3.0,
        checkInterval: TimeInterval = 1.0,
        maxRecoveryAttempts: Int = 3,
        timer: StallTimerProtocol = DefaultStallTimer()
    ) {
        self.stallThreshold = stallThreshold
        self.checkInterval = checkInterval
        self.maxRecoveryAttempts = maxRecoveryAttempts
        self.singlePlayerTimer = timer
    }

    /// Convenience initializer binding a single display player for event-driven testing.
    public convenience init(
        player: DisplayVideoPlayerProtocol,
        timer: StallTimerProtocol = DefaultStallTimer(),
        timeout: TimeInterval = 3.0
    ) {
        self.init(stallThreshold: timeout, checkInterval: 1.0, maxRecoveryAttempts: 3, timer: timer)
        self.singlePlayer = player
        register(player: player)
    }

    // MARK: - Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        schedulePeriodicTimer()
    }

    public func stop() {
        isRunning = false
        periodicTimer?.invalidate()
        periodicTimer = nil
        singlePlayerTimer.cancel()
        trackedPlayers.removeAll()
    }

    public func tearDown() {
        stop()
    }

    public func register(player: DisplayVideoPlayerProtocol) {
        trackedPlayers[player.displayID] = PlayerTrackingState(
            player: player,
            lastObservedPTS: player.currentTime,
            lastWallClockTime: Date(),
            stalledDuration: 0.0,
            recoveryAttempts: 0,
            isUnderRecovery: false
        )
    }

    public func unregister(displayID: CGDirectDisplayID) {
        trackedPlayers.removeValue(forKey: displayID)
    }

    private func schedulePeriodicTimer() {
        periodicTimer?.invalidate()
        let timer = Timer(timeInterval: checkInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.evaluateMonitoredPlayers()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        periodicTimer = timer
    }

    // MARK: - Event-Driven Status Handling (Unit Testing & Direct Notifications)

    public func handleTimeControlStatusChange(_ status: AVPlayer.TimeControlStatus, for displayID: CGDirectDisplayID? = nil) {
        let targetDisplayID = displayID ?? singlePlayer?.displayID ?? trackedPlayers.keys.first

        switch status {
        case .playing:
            singlePlayerTimer.cancel()
            currentStallCount = 0
            if let id = targetDisplayID {
                if let state = trackedPlayers[id], state.recoveryAttempts > 0 {
                    delegate?.watchdog(self, didRecoverStallOn: id, attempt: state.recoveryAttempts)
                }
                trackedPlayers[id]?.stalledDuration = 0.0
                trackedPlayers[id]?.recoveryAttempts = 0
                trackedPlayers[id]?.isUnderRecovery = false
            }

        case .paused:
            singlePlayerTimer.cancel()
            if let id = targetDisplayID {
                trackedPlayers[id]?.stalledDuration = 0.0
                trackedPlayers[id]?.isUnderRecovery = false
            }

        case .waitingToPlayAtSpecifiedRate:
            let player = (targetDisplayID != nil ? trackedPlayers[targetDisplayID!]?.player : nil) ?? singlePlayer
            guard let activePlayer = player else { return }

            singlePlayerTimer.start(interval: stallThreshold, repeats: false) { [weak self, weak activePlayer] in
                guard let self = self, let targetPlayer = activePlayer else { return }
                self.triggerSinglePlayerRecovery(targetPlayer)
            }

        @unknown default:
            break
        }
    }

    private func triggerSinglePlayerRecovery(_ player: DisplayVideoPlayerProtocol) {
        currentStallCount += 1
        let id = player.displayID

        if currentStallCount < maxRecoveryAttempts {
            player.recoverSoft()
            delegate?.watchdog(self, didDetectStallOn: id, reason: "Waiting to play at specified rate")
        } else {
            player.triggerStall()
            delegate?.watchdog(self, didFailRecoveryOn: id, error: .playbackStalled)
        }
    }

    // MARK: - Periodic Evaluation & Stall Detection Logic

    public func evaluateMonitoredPlayers() async {
        let now = Date()

        for (displayID, state) in trackedPlayers {
            guard let player = state.player else {
                trackedPlayers.removeValue(forKey: displayID)
                continue
            }

            guard player.isPlaying else {
                trackedPlayers[displayID]?.lastObservedPTS = player.currentTime
                trackedPlayers[displayID]?.lastWallClockTime = now
                trackedPlayers[displayID]?.stalledDuration = 0.0
                continue
            }

            let currentPTS = player.currentTime
            let elapsedWallClock = now.timeIntervalSince(state.lastWallClockTime)
            let ptsDelta = abs(CMTimeGetSeconds(currentPTS) - CMTimeGetSeconds(state.lastObservedPTS))

            var isStalled = false
            var stallReason = ""

            // Condition 1: Waiting to play
            if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                isStalled = true
                stallReason = "AVPlayer waitingToPlayAtSpecifiedRate (.toMinimizeStalls)"
            }
            // Condition 2: Playback buffer empty
            else if player.isPlaybackBufferEmpty {
                isStalled = true
                stallReason = "Playback buffer is empty"
            }
            // Condition 3: Presentation timestamp frozen
            else if ptsDelta < 0.005 && elapsedWallClock >= min(0.95, stallThreshold * 0.8) {
                isStalled = true
                stallReason = "Presentation timestamp frozen at \(String(format: "%.3f", CMTimeGetSeconds(currentPTS)))s"
            }

            if isStalled {
                let updatedStallDuration = state.stalledDuration + elapsedWallClock
                trackedPlayers[displayID]?.stalledDuration = updatedStallDuration
                trackedPlayers[displayID]?.lastWallClockTime = now

                if updatedStallDuration >= stallThreshold && !state.isUnderRecovery {
                    trackedPlayers[displayID]?.isUnderRecovery = true
                    delegate?.watchdog(self, didDetectStallOn: displayID, reason: stallReason)
                    await executeMultiTierRecovery(for: displayID, on: player)
                }
            } else {
                // Advancing normally
                if state.recoveryAttempts > 0 {
                    delegate?.watchdog(self, didRecoverStallOn: displayID, attempt: state.recoveryAttempts)
                }
                trackedPlayers[displayID]?.lastObservedPTS = currentPTS
                trackedPlayers[displayID]?.lastWallClockTime = now
                trackedPlayers[displayID]?.stalledDuration = 0.0
                trackedPlayers[displayID]?.recoveryAttempts = 0
                trackedPlayers[displayID]?.isUnderRecovery = false
            }
        }
    }

    private func executeMultiTierRecovery(for displayID: CGDirectDisplayID, on player: DisplayVideoPlayerProtocol) async {
        guard var state = trackedPlayers[displayID] else { return }
        state.recoveryAttempts += 1
        trackedPlayers[displayID] = state

        if state.recoveryAttempts <= 2 {
            // Tier 1 & 2: Soft Recovery (Re-preroll and play immediately)
            player.recoverSoft()
            trackedPlayers[displayID]?.isUnderRecovery = false
            trackedPlayers[displayID]?.stalledDuration = 0.0
            trackedPlayers[displayID]?.lastWallClockTime = Date()
        } else if state.recoveryAttempts <= maxRecoveryAttempts {
            // Tier 3: Hard Recovery (Recreate looper and player pipeline)
            do {
                try await player.recoverHard()
                trackedPlayers[displayID]?.isUnderRecovery = false
                trackedPlayers[displayID]?.stalledDuration = 0.0
                trackedPlayers[displayID]?.lastWallClockTime = Date()
            } catch {
                delegate?.watchdog(self, didFailRecoveryOn: displayID, error: .playbackStalled)
            }
        } else {
            // Escalation limit reached: declare failure
            trackedPlayers[displayID]?.isUnderRecovery = false
            delegate?.watchdog(self, didFailRecoveryOn: displayID, error: .playbackStalled)
        }
    }

    isolated deinit {
        stop()
    }
}

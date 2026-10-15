//
//  StallWatchdogTests.swift
//  WallpaperEngineCoreTests
//
//  Automated Unit and Stress Tests for Milestone 2 Video Stall Watchdog:
//  - Stall detection via timeControlStatus & waiting reasons
//  - 3.0s timeout threshold trigger
//  - Multi-tiered recovery escalation (soft rate retries -> hard recreation -> failed)
//  - Resumed playback counter reset & intentional pause immunity
//  - Periodic multi-player monitoring & frozen PTS detection
//

import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
@testable import WallpaperEngineCore

// MARK: - Test Doubles for Stall Watchdog Testing

/// Controllable timer for millisecond unit testing of stall watchdogs.
@MainActor
public final class ControllableStallTimer: StallTimerProtocol {
    public private(set) var isScheduled: Bool = false
    public private(set) var scheduledInterval: TimeInterval = 0.0
    private var fireHandler: (@MainActor () -> Void)?

    public init() {}

    public func start(interval: TimeInterval, repeats: Bool, onFire: @escaping @MainActor () -> Void) {
        self.isScheduled = true
        self.scheduledInterval = interval
        self.fireHandler = onFire
    }

    public func cancel() {
        self.isScheduled = false
        self.fireHandler = nil
    }

    /// Simulates the passage of time and triggers the watchdog fire callback immediately.
    public func simulateTimeout() {
        guard isScheduled else { return }
        fireHandler?()
    }
}

/// Mock display player capturing playback controls, stall recovery calls, and state transitions.
@MainActor
public final class MockDisplayVideoPlayer: DisplayVideoPlayerProtocol {
    public let displayID: CGDirectDisplayID
    public var state: PlaybackState = .idle
    public var currentAsset: VideoAsset?
    public var currentURL: URL? { currentAsset?.fileURL }
    public let playerLayer = AVPlayerLayer()

    // 4-Tier Audio Inspection Properties
    public var isMuted: Bool = true
    public var volume: Float = 0.0
    public var audioTracksEnabled: Bool = false
    public var isAudioMixNulled: Bool = true
    public var audioTimePitchAlgorithm: AVAudioTimePitchAlgorithm = .varispeed

    // Pipeline metrics
    public var currentTime: CMTime = .zero
    public var rate: Float = 0.0
    public var timeControlStatus: AVPlayer.TimeControlStatus = .paused
    public var reasonForWaitingToPlay: AVPlayer.WaitingReason?
    public var isPlaybackBufferEmpty: Bool = false
    public var isPlaying: Bool = false
    public var stallRecoveryCount: Int = 0

    // Invocation Trackers
    public var loadCallCount: Int = 0
    public var playCallCount: Int = 0
    public var pauseCallCount: Int = 0
    public var recoverSoftCallCount: Int = 0
    public var recoverHardCallCount: Int = 0
    public var tearDownCallCount: Int = 0
    public var lastPauseReason: PauseReason?

    public init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    public func attach(to window: DesktopWindowProtocol) {
        window.attachPlayerLayer(playerLayer)
    }

    public func load(url: URL, crossfade: Bool) async throws {
        loadCallCount += 1
        currentAsset = VideoAsset(fileURL: url, title: url.deletingPathExtension().lastPathComponent)
        state = .playing
    }

    public func load(asset: VideoAsset, crossfade: Bool) async throws {
        loadCallCount += 1
        currentAsset = asset
        state = .playing
    }

    public func play() {
        playCallCount += 1
        isPlaying = true
        rate = 1.0
        timeControlStatus = .playing
        state = .playing
    }

    public func pause(reason: PauseReason) {
        pauseCallCount += 1
        isPlaying = false
        rate = 0.0
        timeControlStatus = .paused
        lastPauseReason = reason
        state = .paused(reason: reason)
    }

    public func seek(to time: CMTime) async {
        currentTime = time
    }

    public func recoverSoft() {
        recoverSoftCallCount += 1
        stallRecoveryCount += 1
        state = .playing
        rate = 1.0
        timeControlStatus = .playing
    }

    public func recoverHard() async throws {
        recoverHardCallCount += 1
        stallRecoveryCount += 1
        if stallRecoveryCount >= 3 {
            state = .failed(.playbackStalled)
            throw VideoEngineError.playbackStalled
        } else {
            state = .playing
        }
    }

    public func triggerStall() {
        state = .stalled(reason: "Buffering")
        stallRecoveryCount += 1
        if stallRecoveryCount >= 3 {
            state = .failed(.playbackStalled)
        } else {
            state = .playing
        }
    }

    public func tearDown() {
        tearDownCallCount += 1
        state = .idle
        currentAsset = nil
    }
}

// MARK: - StallWatchdogTests Execution Suite

@MainActor
public struct StallWatchdogTests {

    public static func runAllTests() async {
        let runner = TestRunner.shared

        // =====================================================================
        // SUITE 5: StallWatchdog Detection & Escalation Policy
        // =====================================================================
        await runner.runSuite("Suite 5: StallWatchdog Detection & Escalation Policy") {

            runner.test("SW.1: Watchdog Timeout Threshold Defaults to 3.0 Seconds") {
                let config = VideoEngineConfiguration.default
                try assertEqual(config.stallTimeoutThreshold, 3.0, "stallTimeoutThreshold must default to exactly 3.0s")
                try assertEqual(config.maxStallRecoveryAttempts, 3, "maxStallRecoveryAttempts must default to 3")
            }

            runner.test("SW.2: Sub-Threshold Stall Cancellation") {
                let mockTimer = ControllableStallTimer()
                let player = MockDisplayVideoPlayer(displayID: 1)
                let watchdog = StallWatchdog(player: player, timer: mockTimer, timeout: 3.0)

                watchdog.handleTimeControlStatusChange(.waitingToPlayAtSpecifiedRate)
                try assertTrue(mockTimer.isScheduled, "Timer must be scheduled on stall entry")

                // Stall clears before timeout
                watchdog.handleTimeControlStatusChange(.playing)
                try assertFalse(mockTimer.isScheduled, "Timer must be cancelled when playback resumes before timeout")
                try assertEqual(player.stallRecoveryCount, 0, "No recovery attempt should have been triggered")

                watchdog.tearDown()
            }

            runner.test("SW.3: First Stall Triggers Soft Recovery (Play Rate Retry)") {
                let mockTimer = ControllableStallTimer()
                let player = MockDisplayVideoPlayer(displayID: 1)
                let watchdog = StallWatchdog(player: player, timer: mockTimer, timeout: 3.0)

                watchdog.handleTimeControlStatusChange(.waitingToPlayAtSpecifiedRate)
                mockTimer.simulateTimeout()

                try assertEqual(player.stallRecoveryCount, 1, "Recovery count must increment to 1")
                try assertEqual(player.state, .playing, "Player must remain in .playing after soft recovery")

                watchdog.tearDown()
            }

            runner.test("SW.4: Second Consecutive Stall Escalates Soft Recovery (Attempt 2)") {
                let mockTimer = ControllableStallTimer()
                let player = MockDisplayVideoPlayer(displayID: 1)
                let watchdog = StallWatchdog(player: player, timer: mockTimer, timeout: 3.0)

                // First stall
                watchdog.handleTimeControlStatusChange(.waitingToPlayAtSpecifiedRate)
                mockTimer.simulateTimeout()

                // Second stall
                watchdog.handleTimeControlStatusChange(.waitingToPlayAtSpecifiedRate)
                mockTimer.simulateTimeout()

                try assertEqual(player.stallRecoveryCount, 2, "Recovery count must increment to 2")
                try assertEqual(player.state, .playing, "Player must remain in .playing after second soft recovery")

                watchdog.tearDown()
            }

            runner.test("SW.5: Third Consecutive Stall Triggers Hard Recovery / Failure") {
                let mockTimer = ControllableStallTimer()
                let player = MockDisplayVideoPlayer(displayID: 1)
                let watchdog = StallWatchdog(player: player, timer: mockTimer, timeout: 3.0)

                // Simulate 3 consecutive stalls exceeding timeout
                for _ in 0..<3 {
                    watchdog.handleTimeControlStatusChange(.waitingToPlayAtSpecifiedRate)
                    mockTimer.simulateTimeout()
                }

                try assertEqual(player.stallRecoveryCount, 3, "Recovery count must reach 3")
                try assertEqual(player.state, .failed(.playbackStalled), "Player must transition to .failed(.playbackStalled)")

                watchdog.tearDown()
            }

            runner.test("SW.6: Resumed Playback Resets Stall Recovery Counter") {
                let mockTimer = ControllableStallTimer()
                let player = MockDisplayVideoPlayer(displayID: 1)
                let watchdog = StallWatchdog(player: player, timer: mockTimer, timeout: 3.0)

                // Single stall
                watchdog.handleTimeControlStatusChange(.waitingToPlayAtSpecifiedRate)
                mockTimer.simulateTimeout()
                try assertEqual(player.stallRecoveryCount, 1, "Count should be 1")

                // Playback normalizes
                watchdog.handleTimeControlStatusChange(.playing)
                try assertEqual(watchdog.currentStallCount, 0, "Watchdog stall counter must reset to 0 on normal play")

                watchdog.tearDown()
            }

            runner.test("SW.7: Watchdog Suppressed During Intentional Pause") {
                let mockTimer = ControllableStallTimer()
                let player = MockDisplayVideoPlayer(displayID: 1)
                let watchdog = StallWatchdog(player: player, timer: mockTimer, timeout: 3.0)

                // Player paused intentionally
                player.pause(reason: .userRequested)
                watchdog.handleTimeControlStatusChange(.paused)

                try assertFalse(mockTimer.isScheduled, "Watchdog timer must not be scheduled during pause")
                try assertEqual(player.stallRecoveryCount, 0, "No recovery should occur during intentional pause")

                watchdog.tearDown()
            }

            runner.test("SW.8: Teardown Cancels Pending Watchdog Timers and Discards Callbacks") {
                let mockTimer = ControllableStallTimer()
                let player = MockDisplayVideoPlayer(displayID: 1)
                let watchdog = StallWatchdog(player: player, timer: mockTimer, timeout: 3.0)

                watchdog.handleTimeControlStatusChange(.waitingToPlayAtSpecifiedRate)
                try assertTrue(mockTimer.isScheduled, "Timer should be active")

                watchdog.tearDown()
                try assertFalse(mockTimer.isScheduled, "Teardown must cancel timer")

                mockTimer.simulateTimeout()
                try assertEqual(player.stallRecoveryCount, 0, "Late callback must not affect destroyed player")
            }

            await runner.testAsync("SW.9: Periodic Monitoring Evaluates Frozen PTS and Buffering") {
                let watchdog = StallWatchdog(stallThreshold: 0.1, checkInterval: 0.1, maxRecoveryAttempts: 3)
                let player = MockDisplayVideoPlayer(displayID: 10)
                watchdog.register(player: player)

                player.play()
                player.currentTime = CMTime(seconds: 5.0, preferredTimescale: 600)

                // First evaluation: records initial PTS
                await watchdog.evaluateMonitoredPlayers()
                try assertEqual(player.recoverSoftCallCount, 0, "Should not recover on initial tick")

                // Wait 120ms with frozen PTS
                try? await Task.sleep(nanoseconds: 120_000_000)

                // Second evaluation: detects frozen PTS
                await watchdog.evaluateMonitoredPlayers()
                try assertEqual(player.recoverSoftCallCount, 1, "Should trigger soft recovery when PTS is frozen")

                watchdog.stop()
            }
        }
    }
}

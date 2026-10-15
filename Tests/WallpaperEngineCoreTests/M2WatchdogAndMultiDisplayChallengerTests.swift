//
//  M2WatchdogAndMultiDisplayChallengerTests.swift
//  WallpaperEngineCoreTests
//
//  Milestone 2 Adversarial Stress Probes & Empirical Verification:
//  - Invariant 1: Watchdog strictly detects frozen PTS / buffering at >= 3.0s
//                 and triggers soft recovery (Attempt 1-2) -> hard recovery (Attempt 3) -> failure escalation.
//  - Invariant 2: Intentional pause does not trigger watchdog stall false positives.
//  - Invariant 3: Multi-display chaos: rapid display addition/removal and resolution changes
//                 update player frames while strictly preserving pointer identity (===)
//                 and producing 0 leaked player instances.
//

import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import QuartzCore
@testable import WallpaperEngineCore

// MARK: - Weak Pointer Box for Leak Auditing

@MainActor
public final class WeakPlayerBox {
    public weak var player: (any DisplayVideoPlayerProtocol)?
    public init(_ player: any DisplayVideoPlayerProtocol) {
        self.player = player
    }
}

// MARK: - Controllable Mock Player for Millisecond-Precision Challenger Probes

@MainActor
public final class ChallengerMockPlayer: DisplayVideoPlayerProtocol {
    public let displayID: CGDirectDisplayID
    public var state: PlaybackState = .idle
    public var currentAsset: VideoAsset?
    public var currentURL: URL? { currentAsset?.fileURL }
    public let playerLayer = AVPlayerLayer()

    public var isMuted: Bool = true
    public var volume: Float = 0.0
    public var audioTracksEnabled: Bool = false
    public var isAudioMixNulled: Bool = true
    public var audioTimePitchAlgorithm: AVAudioTimePitchAlgorithm = .varispeed

    public var currentTime: CMTime = .zero
    public var rate: Float = 1.0
    public var timeControlStatus: AVPlayer.TimeControlStatus = .playing
    public var reasonForWaitingToPlay: AVPlayer.WaitingReason?
    public var isPlaybackBufferEmpty: Bool = false
    public var isPlaying: Bool = true
    public var stallRecoveryCount: Int = 0

    // Call Trackers
    public var recoverSoftCount: Int = 0
    public var recoverHardCount: Int = 0
    public var triggerStallCount: Int = 0
    public var shouldThrowOnHardRecovery: Bool = false
    public var tearDownCount: Int = 0

    public init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    public func load(asset: VideoAsset, crossfade: Bool) async throws {
        self.currentAsset = asset
        self.state = .playing
        self.isPlaying = true
    }

    public func load(url: URL, crossfade: Bool) async throws {
        let title = url.deletingPathExtension().lastPathComponent
        self.currentAsset = VideoAsset(fileURL: url, title: title)
        self.state = .playing
        self.isPlaying = true
    }

    public func attach(to window: DesktopWindowProtocol) {
        window.attachPlayerLayer(playerLayer)
    }

    public func play() {
        isPlaying = true
        rate = 1.0
        timeControlStatus = .playing
        state = .playing
    }

    public func pause(reason: PauseReason) {
        isPlaying = false
        rate = 0.0
        timeControlStatus = .paused
        state = .paused(reason: reason)
    }

    public func seek(to time: CMTime) async {
        currentTime = time
    }

    public func recoverSoft() {
        recoverSoftCount += 1
        stallRecoveryCount += 1
        state = .playing
        isPlaying = true
        rate = 1.0
        timeControlStatus = .playing
    }

    public func recoverHard() async throws {
        recoverHardCount += 1
        stallRecoveryCount += 1
        if shouldThrowOnHardRecovery {
            state = .failed(.playbackStalled)
            throw VideoEngineError.playbackStalled
        }
        state = .playing
        isPlaying = true
        rate = 1.0
        timeControlStatus = .playing
    }

    public func triggerStall() {
        triggerStallCount += 1
        stallRecoveryCount += 1
        state = .failed(.playbackStalled)
    }

    public func tearDown() {
        tearDownCount += 1
        isPlaying = false
        state = .idle
        currentAsset = nil
    }
}

// MARK: - Spy Delegate for Watchdog Callback Inspection

@MainActor
public final class SpyWatchdogDelegate: StallWatchdogDelegate {
    public var detectedStalls: [(displayID: CGDirectDisplayID, reason: String)] = []
    public var recoveredStalls: [(displayID: CGDirectDisplayID, attempt: Int)] = []
    public var failedRecoveries: [(displayID: CGDirectDisplayID, error: VideoEngineError)] = []

    public init() {}

    public func watchdog(_ watchdog: StallWatchdogProtocol, didDetectStallOn displayID: CGDirectDisplayID, reason: String) {
        detectedStalls.append((displayID, reason))
    }

    public func watchdog(_ watchdog: StallWatchdogProtocol, didRecoverStallOn displayID: CGDirectDisplayID, attempt: Int) {
        recoveredStalls.append((displayID, attempt))
    }

    public func watchdog(_ watchdog: StallWatchdogProtocol, didFailRecoveryOn displayID: CGDirectDisplayID, error: VideoEngineError) {
        failedRecoveries.append((displayID, error))
    }
}

// MARK: - Challenger Test Suite

@MainActor
public struct M2WatchdogAndMultiDisplayChallengerTests {

    public static func runAllTests() async {
        let runner = TestRunner.shared

        await runner.runSuite("Milestone 2 Challenger Suite: StallWatchdog & Multi-Display Chaos") {

            // =================================================================
            // INVARIANT 1: StallWatchdog Timing & Escalation Ladder
            // =================================================================

            await runner.testAsync("CHALLENGE 1.1: Sub-3.0s Frozen PTS Does Not Trigger Stall Recovery (Threshold Guard)") {
                // Set threshold to 0.20s (simulating 3.0s in micro-scale)
                let watchdog = StallWatchdog(stallThreshold: 0.20, checkInterval: 0.05, maxRecoveryAttempts: 3)
                let spy = SpyWatchdogDelegate()
                watchdog.delegate = spy

                let player = ChallengerMockPlayer(displayID: 101)
                player.play()
                player.currentTime = CMTime(seconds: 42.0, preferredTimescale: 600)
                watchdog.register(player: player)

                // Tick 0: establish baseline PTS
                await watchdog.evaluateMonitoredPlayers()
                try assertEqual(player.recoverSoftCount, 0, "No recovery on tick 0")

                // Freeze for 100ms (50% of 200ms threshold)
                try await Task.sleep(nanoseconds: 100_000_000)
                await watchdog.evaluateMonitoredPlayers()
                try assertEqual(player.recoverSoftCount, 0, "Sub-threshold stall must NOT trigger recovery")
                try assertEqual(spy.detectedStalls.count, 0, "Delegate must NOT receive stall notification yet")

                // Advance PTS before threshold expires (glitch recovery)
                player.currentTime = CMTime(seconds: 42.5, preferredTimescale: 600)
                await watchdog.evaluateMonitoredPlayers()
                try assertEqual(player.recoverSoftCount, 0, "Advancing PTS must clear stall accumulation")

                // Sleep another 100ms with new PTS: still sub-threshold from reset point
                try await Task.sleep(nanoseconds: 100_000_000)
                await watchdog.evaluateMonitoredPlayers()
                try assertEqual(player.recoverSoftCount, 0, "Stall counter must have reset; no recovery triggered")

                watchdog.stop()
            }

            await runner.testAsync("CHALLENGE 1.2: Frozen PTS Sustained >= 3.0s Threshold Triggers Soft Recovery (Attempt 1)") {
                let watchdog = StallWatchdog(stallThreshold: 0.15, checkInterval: 0.05, maxRecoveryAttempts: 3)
                let spy = SpyWatchdogDelegate()
                watchdog.delegate = spy

                let player = ChallengerMockPlayer(displayID: 102)
                player.play()
                player.currentTime = CMTime(seconds: 15.0, preferredTimescale: 600)
                watchdog.register(player: player)

                // Tick 0: record baseline
                await watchdog.evaluateMonitoredPlayers()

                // Sleep 180ms (> 150ms threshold) with frozen PTS
                try await Task.sleep(nanoseconds: 180_000_000)
                await watchdog.evaluateMonitoredPlayers()

                try assertEqual(spy.detectedStalls.count, 1, "Watchdog must detect stall when duration >= threshold")
                try assertEqual(player.recoverSoftCount, 1, "Attempt 1 must trigger player.recoverSoft()")
                try assertEqual(player.recoverHardCount, 0, "Attempt 1 must NOT trigger hard recovery")
                try assertEqual(spy.failedRecoveries.count, 0, "Attempt 1 must NOT fail")

                watchdog.stop()
            }

            await runner.testAsync("CHALLENGE 1.3: 4-Tier Recovery Escalation Ladder (Soft 1 -> Soft 2 -> Hard 3 -> Failure)") {
                let watchdog = StallWatchdog(stallThreshold: 0.10, checkInterval: 0.05, maxRecoveryAttempts: 3)
                let spy = SpyWatchdogDelegate()
                watchdog.delegate = spy

                let player = ChallengerMockPlayer(displayID: 103)
                player.play()
                player.currentTime = CMTime(seconds: 1.0, preferredTimescale: 600)
                watchdog.register(player: player)

                // Baseline
                await watchdog.evaluateMonitoredPlayers()

                // --- STALL 1: triggers Attempt 1 (Soft) ---
                try await Task.sleep(nanoseconds: 120_000_000)
                await watchdog.evaluateMonitoredPlayers()
                try assertEqual(player.recoverSoftCount, 1, "Escalation Step 1: soft recovery attempt 1")
                try assertEqual(player.recoverHardCount, 0, "No hard recovery yet")

                // --- STALL 2: triggers Attempt 2 (Soft) ---
                try await Task.sleep(nanoseconds: 120_000_000)
                await watchdog.evaluateMonitoredPlayers()
                try assertEqual(player.recoverSoftCount, 2, "Escalation Step 2: soft recovery attempt 2")
                try assertEqual(player.recoverHardCount, 0, "No hard recovery yet")

                // --- STALL 3: triggers Attempt 3 (Hard) ---
                try await Task.sleep(nanoseconds: 120_000_000)
                await watchdog.evaluateMonitoredPlayers()
                try assertEqual(player.recoverSoftCount, 2, "Soft recovery count must remain 2")
                try assertEqual(player.recoverHardCount, 1, "Escalation Step 3: hard recovery attempt 3 must be invoked")
                try assertEqual(spy.failedRecoveries.count, 0, "Attempt 3 has not failed yet")

                // --- STALL 4: Escalation Limit Exceeded -> Failure ---
                try await Task.sleep(nanoseconds: 120_000_000)
                await watchdog.evaluateMonitoredPlayers()
                try assertEqual(spy.failedRecoveries.count, 1, "Escalation Step 4: must declare unrecoverable failure")
                try assertEqual(spy.failedRecoveries.first?.error, .playbackStalled, "Error must be .playbackStalled")

                watchdog.stop()
            }

            await runner.testAsync("CHALLENGE 1.4: Hard Recovery Throw Escalates Immediately to Failure") {
                let watchdog = StallWatchdog(stallThreshold: 0.10, checkInterval: 0.05, maxRecoveryAttempts: 3)
                let spy = SpyWatchdogDelegate()
                watchdog.delegate = spy

                let player = ChallengerMockPlayer(displayID: 104)
                player.play()
                player.currentTime = CMTime(seconds: 1.0, preferredTimescale: 600)
                player.shouldThrowOnHardRecovery = true
                watchdog.register(player: player)

                // Baseline
                await watchdog.evaluateMonitoredPlayers()

                // Attempt 1: soft
                try await Task.sleep(nanoseconds: 120_000_000)
                await watchdog.evaluateMonitoredPlayers()

                // Attempt 2: soft
                try await Task.sleep(nanoseconds: 120_000_000)
                await watchdog.evaluateMonitoredPlayers()

                // Attempt 3: hard recovery throws -> catch block must immediately fail
                try await Task.sleep(nanoseconds: 120_000_000)
                await watchdog.evaluateMonitoredPlayers()

                try assertEqual(player.recoverHardCount, 1, "Hard recovery must have been attempted")
                try assertEqual(spy.failedRecoveries.count, 1, "Failed hard recovery must escalate immediately to failure")
                try assertEqual(spy.failedRecoveries.first?.error, .playbackStalled, "Error must be .playbackStalled")

                watchdog.stop()
            }

            await runner.testAsync("CHALLENGE 1.5: Resumed Playback Resets Escalation Counter Back to Step 1") {
                let watchdog = StallWatchdog(stallThreshold: 0.10, checkInterval: 0.05, maxRecoveryAttempts: 3)
                let spy = SpyWatchdogDelegate()
                watchdog.delegate = spy

                let player = ChallengerMockPlayer(displayID: 105)
                player.play()
                player.currentTime = CMTime(seconds: 10.0, preferredTimescale: 600)
                watchdog.register(player: player)

                await watchdog.evaluateMonitoredPlayers()

                // Cause 2 soft stalls
                try await Task.sleep(nanoseconds: 120_000_000)
                await watchdog.evaluateMonitoredPlayers()
                try await Task.sleep(nanoseconds: 120_000_000)
                await watchdog.evaluateMonitoredPlayers()
                try assertEqual(player.recoverSoftCount, 2, "2 soft stalls incurred")

                // Playback resumes normally: PTS advances
                player.currentTime = CMTime(seconds: 12.0, preferredTimescale: 600)
                await watchdog.evaluateMonitoredPlayers()

                try assertEqual(spy.recoveredStalls.count, 1, "Watchdog must report didRecoverStallOn")
                try assertEqual(spy.recoveredStalls.first?.attempt, 2, "Recovery reported for attempt 2")

                // New stall occurs: must start at Attempt 1 again (soft), NOT Attempt 3
                try await Task.sleep(nanoseconds: 120_000_000)
                await watchdog.evaluateMonitoredPlayers()

                try assertEqual(player.recoverSoftCount, 3, "New stall after recovery must invoke soft recovery (Attempt 1 of new cycle)")
                try assertEqual(player.recoverHardCount, 0, "Must NOT jump to hard recovery because counter was reset")

                watchdog.stop()
            }

            await runner.testAsync("CHALLENGE 1.6: Buffer Starvation (isPlaybackBufferEmpty) Triggers Escalation Ladder") {
                let watchdog = StallWatchdog(stallThreshold: 0.10, checkInterval: 0.05, maxRecoveryAttempts: 3)
                let spy = SpyWatchdogDelegate()
                watchdog.delegate = spy

                let player = ChallengerMockPlayer(displayID: 106)
                player.play()
                player.isPlaybackBufferEmpty = true
                watchdog.register(player: player)

                await watchdog.evaluateMonitoredPlayers()

                try await Task.sleep(nanoseconds: 120_000_000)
                await watchdog.evaluateMonitoredPlayers()

                try assertEqual(spy.detectedStalls.count, 1, "Buffer starvation must trigger stall detection")
                try assertTrue(spy.detectedStalls.first?.reason.contains("buffer") ?? false, "Reason must identify buffer starvation")
                try assertEqual(player.recoverSoftCount, 1, "Must trigger soft recovery")

                watchdog.stop()
            }

            // =================================================================
            // INVARIANT 2: Intentional Pause Immunity
            // =================================================================

            await runner.testAsync("CHALLENGE 2.1: Extended Intentional User Pause Produces Zero Stall False Positives") {
                let watchdog = StallWatchdog(stallThreshold: 0.10, checkInterval: 0.05, maxRecoveryAttempts: 3)
                let spy = SpyWatchdogDelegate()
                watchdog.delegate = spy

                let player = ChallengerMockPlayer(displayID: 201)
                player.pause(reason: .userRequested)
                watchdog.register(player: player)

                // Run 10 evaluation ticks over 500ms while paused
                for _ in 0..<10 {
                    try await Task.sleep(nanoseconds: 50_000_000)
                    await watchdog.evaluateMonitoredPlayers()
                }

                try assertEqual(spy.detectedStalls.count, 0, "Paused player must produce ZERO detected stalls")
                try assertEqual(player.recoverSoftCount, 0, "Paused player must produce ZERO soft recoveries")
                try assertEqual(player.recoverHardCount, 0, "Paused player must produce ZERO hard recoveries")
                try assertEqual(player.triggerStallCount, 0, "Paused player must produce ZERO stall triggers")
                try assertEqual(player.state, .paused(reason: .userRequested), "Player state must remain paused")

                watchdog.stop()
            }

            await runner.testAsync("CHALLENGE 2.2: All System Pause Reasons (Sleep, Lock, Battery, Occlusion) Immune from Watchdog") {
                let reasons: [PauseReason] = [
                    .systemSleeping,
                    .screensSleeping,
                    .screenLocked,
                    .lowPowerMode,
                    .onBattery,
                    .displayOccluded,
                    .thermalPressure
                ]

                let watchdog = StallWatchdog(stallThreshold: 0.05, checkInterval: 0.02, maxRecoveryAttempts: 3)
                let spy = SpyWatchdogDelegate()
                watchdog.delegate = spy

                for (idx, reason) in reasons.enumerated() {
                    let displayID = CGDirectDisplayID(210 + idx)
                    let player = ChallengerMockPlayer(displayID: displayID)
                    player.pause(reason: reason)
                    watchdog.register(player: player)

                    try await Task.sleep(nanoseconds: 70_000_000)
                    await watchdog.evaluateMonitoredPlayers()

                    try assertEqual(player.recoverSoftCount, 0, "Reason '\(reason.rawValue)' must not trigger recovery")
                    try assertEqual(player.state, .paused(reason: reason), "State must preserve pause reason")
                    watchdog.unregister(displayID: displayID)
                }

                try assertEqual(spy.detectedStalls.count, 0, "Zero stall false positives across all system pause reasons")
                watchdog.stop()
            }

            await runner.testAsync("CHALLENGE 2.3: Pause Mid-Stall Wipes Accumulated Duration (No False Positive on Unpause)") {
                let watchdog = StallWatchdog(stallThreshold: 0.20, checkInterval: 0.05, maxRecoveryAttempts: 3)
                let spy = SpyWatchdogDelegate()
                watchdog.delegate = spy

                let player = ChallengerMockPlayer(displayID: 203)
                player.play()
                player.currentTime = CMTime(seconds: 5.0, preferredTimescale: 600)
                watchdog.register(player: player)

                // Baseline
                await watchdog.evaluateMonitoredPlayers()

                // Freeze for 120ms (accumulating stall duration, but under 200ms)
                try await Task.sleep(nanoseconds: 120_000_000)
                await watchdog.evaluateMonitoredPlayers()
                try assertEqual(player.recoverSoftCount, 0, "Sub-threshold stall")

                // User pauses: watchdog should clear stalled duration
                player.pause(reason: .userRequested)
                watchdog.handleTimeControlStatusChange(.paused, for: 203)
                await watchdog.evaluateMonitoredPlayers()

                // Stay paused for 250ms (> threshold)
                try await Task.sleep(nanoseconds: 250_000_000)
                await watchdog.evaluateMonitoredPlayers()
                try assertEqual(player.recoverSoftCount, 0, "No stall while paused")

                // Unpause and immediately evaluate: should NOT fire stall from previous accumulation
                player.play()
                player.currentTime = CMTime(seconds: 6.0, preferredTimescale: 600)
                watchdog.handleTimeControlStatusChange(.playing, for: 203)
                await watchdog.evaluateMonitoredPlayers()

                try assertEqual(player.recoverSoftCount, 0, "Unpaused player must not falsely trigger stall from wiped accumulation")
                watchdog.stop()
            }

            // =================================================================
            // INVARIANT 3: Multi-Display Chaos & Pointer Identity Invariants
            // =================================================================

            runner.test("CHALLENGE 3.1: Resolution Ladder Update Strictly Preserves Pointer Identity (===)") {
                let windowManager = MockDesktopWindowManager()
                let engine = VideoEngine(
                    windowManager: windowManager,
                    playerFactory: { id, _ in ChallengerMockPlayer(displayID: id) }
                )
                engine.registerDisplay(1)

                let originalPlayer = engine.player(for: 1)
                try assertNotNil(originalPlayer, "Display 1 player must exist")

                let resolutions: [CGSize] = [
                    CGSize(width: 2560, height: 1440),
                    CGSize(width: 3840, height: 2160),
                    CGSize(width: 5120, height: 2880),
                    CGSize(width: 1440, height: 900),
                    CGSize(width: 1728, height: 1117),
                    CGSize(width: 3024, height: 1964),
                    CGSize(width: 1920, height: 1080)
                ]

                for (idx, size) in resolutions.enumerated() {
                    let newFrame = CGRect(origin: .zero, size: size)
                    let window = windowManager.window(for: 1) as? MockDesktopWindow
                    window?.updateFrame(newFrame)

                    // Notify engine of resolution update
                    engine.displayConfigurationDidChange(added: [], removed: [], updated: [1])

                    let currentPlayer = engine.player(for: 1)
                    try assertTrue(
                        currentPlayer === originalPlayer,
                        "Resolution step \(idx) (\(Int(size.width))x\(Int(size.height))) must strictly preserve player pointer identity"
                    )
                }

                engine.stop()
            }

            runner.test("CHALLENGE 3.2: DesktopWindow updateFrame Resizes Attached Player Layer In-Place") {
                let window = DesktopWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                let playerLayer = AVPlayerLayer()
                window.attachPlayerLayer(playerLayer)

                try assertEqual(playerLayer.frame.size, CGSize(width: 1920, height: 1080), "Initial layer size must match window frame")

                // Resize window to 4K
                let newFrame4K = CGRect(x: 0, y: 0, width: 3840, height: 2160)
                window.updateFrame(newFrame4K)

                try assertEqual(window.frame.size, CGSize(width: 3840, height: 2160), "Window frame must be 4K")
                try assertEqual(playerLayer.frame.size, CGSize(width: 3840, height: 2160), "Player layer must resize in-place without replacing instance")
                try assertTrue(window.currentActiveLayer === playerLayer, "Layer pointer identity must be preserved")

                window.closeAndRelease()
            }

            await runner.testAsync("CHALLENGE 3.3: 100-Cycle Display Hot-Plug & Removal Storm Produces Exactly Zero Leaked Players") {
                let windowManager = MockDesktopWindowManager()
                let engine = VideoEngine(
                    windowManager: windowManager,
                    playerFactory: { id, _ in ChallengerMockPlayer(displayID: id) }
                )

                var allTrackedPlayers: [WeakPlayerBox] = []

                // 100 cycles of random churn across 5 display slots
                for cycle in 0..<100 {
                    let targetID = CGDirectDisplayID((cycle % 5) + 1)
                    let exists = engine.player(for: targetID) != nil

                    if exists {
                        // Disconnect display
                        engine.displayConfigurationDidChange(added: [], removed: [targetID], updated: [])
                        try assertNil(engine.player(for: targetID), "Player for display \(targetID) must be removed")
                    } else {
                        // Connect display
                        engine.displayConfigurationDidChange(added: [targetID], removed: [], updated: [])
                        if let newPlayer = engine.player(for: targetID) {
                            allTrackedPlayers.append(WeakPlayerBox(newPlayer))
                        }
                    }
                }

                // Final clean shutdown
                engine.stop()

                // Allow micro-turn for ARC sweeps
                try await Task.sleep(nanoseconds: 10_000_000)

                // Audit: ALL players ever spawned must now be deallocated
                var leakedCount = 0
                for box in allTrackedPlayers {
                    if box.player != nil {
                        leakedCount += 1
                    }
                }

                try assertEqual(leakedCount, 0, "100-cycle display storm must result in 0 leaked player instances (found \(leakedCount) leaks)")
            }

            await runner.testAsync("CHALLENGE 3.4: Real DisplayVideoPlayer & Real DesktopWindow Deallocation Audit") {
                let videoURL = try await SyntheticVideoGenerator.createValidVideoFile()

                var weakPlayerBox: WeakPlayerBox?
                do {
                    let realWindow = DesktopWindow(frame: CGRect(x: 0, y: 0, width: 640, height: 480), displayID: 99)
                    let realPlayer = DisplayVideoPlayer(displayID: 99)
                    weakPlayerBox = WeakPlayerBox(realPlayer)

                    realPlayer.attach(to: realWindow)
                    try await realPlayer.load(url: videoURL, crossfade: false)
                    realPlayer.play()

                    try assertNotNil(weakPlayerBox?.player, "Real player must be retained while in scope")

                    realPlayer.tearDown()
                    realWindow.closeAndRelease()
                }

                try await Task.sleep(nanoseconds: 20_000_000)

                try assertNil(weakPlayerBox?.player, "Real DisplayVideoPlayer must be fully deallocated with 0 ARC leaks")
                try? FileManager.default.removeItem(at: videoURL)
            }

            runner.test("CHALLENGE 3.5: Multi-Display Isolation: Detaching Display 2 Leaves Display 1 and 3 Untouched") {
                let windowManager = MockDesktopWindowManager()
                let engine = VideoEngine(
                    windowManager: windowManager,
                    playerFactory: { id, _ in ChallengerMockPlayer(displayID: id) }
                )

                engine.registerDisplay(1)
                engine.registerDisplay(2)
                engine.registerDisplay(3)

                let p1 = engine.player(for: 1)
                let p2 = engine.player(for: 2)
                let p3 = engine.player(for: 3)

                try assertNotNil(p1)
                try assertNotNil(p2)
                try assertNotNil(p3)

                // Remove display 2
                engine.displayConfigurationDidChange(added: [], removed: [2], updated: [])

                try assertNil(engine.player(for: 2), "Display 2 must be detached")
                try assertTrue(engine.player(for: 1) === p1, "Display 1 player pointer must remain identical")
                try assertTrue(engine.player(for: 3) === p3, "Display 3 player pointer must remain identical")
                try assertEqual(engine.activeDisplays, [1, 3], "Active displays must be [1, 3]")

                engine.stop()
            }
        }
    }
}

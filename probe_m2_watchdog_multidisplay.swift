//
//  probe_m2_watchdog_multidisplay.swift
//  WallpaperEngineCore
//
//  Empirical Challenger Probes for Milestone 2:
//  - StallWatchdog Detection, Timing & Escalation Ladder
//  - Intentional Pause Immunity & Zero False Positive Invariants
//  - Multi-Display VideoEngine Coordination, Pointer Identity (===) & Zero Leak Teardown
//

import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import QuartzCore
@testable import WallpaperEngineCore

// MARK: - Assertion Helpers

enum ProbeError: Error, CustomStringConvertible {
    case assertionFailed(String)
    var description: String {
        switch self {
        case .assertionFailed(let msg): return msg
        }
    }
}

func probeAssert(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) throws {
    guard condition else {
        throw ProbeError.assertionFailed("FAIL [\(file):\(line)]: \(message)")
    }
}

func probeAssertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, file: StaticString = #file, line: UInt = #line) throws {
    guard a == b else {
        throw ProbeError.assertionFailed("FAIL [\(file):\(line)]: Expected [\(b)], got [\(a)] — \(message)")
    }
}

func probeAssertNil<T>(_ value: T?, _ message: String, file: StaticString = #file, line: UInt = #line) throws {
    guard value == nil else {
        throw ProbeError.assertionFailed("FAIL [\(file):\(line)]: Expected nil, got [\(String(describing: value))] — \(message)")
    }
}

// MARK: - Test Doubles for Empirical Stress

@MainActor
final class WeakPlayerReferenceBox {
    weak var player: (any DisplayVideoPlayerProtocol)?
    init(_ player: any DisplayVideoPlayerProtocol) {
        self.player = player
    }
}

@MainActor
final class ProbeMockDesktopWindow: DesktopWindowProtocol {
    let displayID: CGDirectDisplayID
    var underlyingWindow: NSWindow { mockWindow }
    var rootHostingLayer: CALayer? = CALayer()
    var contentLayer: CALayer?
    var currentActiveLayer: CALayer?
    var isVisible: Bool = false
    var windowLevel: Int { mockWindow.level.rawValue }
    var collectionBehaviorFlags: NSWindow.CollectionBehavior { mockWindow.collectionBehavior }
    var ignoresMouseEventsFlag: Bool { mockWindow.ignoresMouseEvents }
    var canBecomeKey: Bool { false }
    var canBecomeMain: Bool { false }
    var frame: CGRect
    var attachedLayers: [CALayer] = []

    private let mockWindow: NSWindow

    init(frame: CGRect, displayID: CGDirectDisplayID) {
        self.frame = frame
        self.displayID = displayID
        self.mockWindow = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    }

    func attachPlayerLayer(_ playerLayer: CALayer) {
        attachedLayers.append(playerLayer)
        currentActiveLayer = playerLayer
        contentLayer = playerLayer
    }

    func removePlayerLayer() {
        currentActiveLayer = nil
        contentLayer = nil
    }

    func transitionToPlayerLayer(_ newLayer: CALayer, duration: TimeInterval) {
        attachedLayers.append(newLayer)
        currentActiveLayer = newLayer
        contentLayer = newLayer
    }

    func updateFrame(_ newFrame: CGRect) {
        self.frame = newFrame
        self.mockWindow.setFrame(newFrame, display: false)
    }

    func orderToDesktopLevel() { isVisible = true }
    func closeAndRelease() { isVisible = false }
}

@MainActor
final class ProbeMockDesktopWindowManager: DesktopWindowManagerProtocol {
    var managedWindows: [CGDirectDisplayID: DesktopWindowProtocol] = [:]
    weak var delegate: DesktopWindowManagerDelegate?
    var screenManager: ScreenManagerProtocol = ScreenManager()
    var isRunning: Bool = false

    init() {}
    func start() { isRunning = true }
    func stop() { isRunning = false; managedWindows.removeAll() }
    func window(for displayID: CGDirectDisplayID) -> DesktopWindowProtocol? { managedWindows[displayID] }
    func reconcileWindows(with screens: [ScreenDescriptor]) {}
}

@MainActor
final class ChallengerProbePlayer: DisplayVideoPlayerProtocol {
    let displayID: CGDirectDisplayID
    var state: PlaybackState = .idle
    var currentAsset: VideoAsset?
    var currentURL: URL? { currentAsset?.fileURL }
    let playerLayer = AVPlayerLayer()

    var isMuted: Bool = true
    var volume: Float = 0.0
    var audioTracksEnabled: Bool = false
    var isAudioMixNulled: Bool = true
    var audioTimePitchAlgorithm: AVAudioTimePitchAlgorithm = .varispeed

    var currentTime: CMTime = .zero
    var rate: Float = 1.0
    var timeControlStatus: AVPlayer.TimeControlStatus = .playing
    var reasonForWaitingToPlay: AVPlayer.WaitingReason?
    var isPlaybackBufferEmpty: Bool = false
    var isPlaying: Bool = true
    var stallRecoveryCount: Int = 0

    // Instrumentation
    var recoverSoftCalls: Int = 0
    var recoverHardCalls: Int = 0
    var triggerStallCalls: Int = 0
    var tearDownCalls: Int = 0
    var shouldThrowOnHardRecovery: Bool = false

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    func load(asset: VideoAsset, crossfade: Bool) async throws {
        self.currentAsset = asset
        self.state = .playing
        self.isPlaying = true
    }

    func load(url: URL, crossfade: Bool) async throws {
        self.currentAsset = VideoAsset(fileURL: url, title: url.deletingPathExtension().lastPathComponent)
        self.state = .playing
        self.isPlaying = true
    }

    func attach(to window: DesktopWindowProtocol) {
        window.attachPlayerLayer(playerLayer)
    }

    func play() {
        isPlaying = true
        rate = 1.0
        timeControlStatus = .playing
        state = .playing
    }

    func pause(reason: PauseReason) {
        isPlaying = false
        rate = 0.0
        timeControlStatus = .paused
        state = .paused(reason: reason)
    }

    func seek(to time: CMTime) async {
        currentTime = time
    }

    func recoverSoft() {
        recoverSoftCalls += 1
        stallRecoveryCount += 1
        state = .playing
        isPlaying = true
        rate = 1.0
        timeControlStatus = .playing
    }

    func recoverHard() async throws {
        recoverHardCalls += 1
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

    func triggerStall() {
        triggerStallCalls += 1
        stallRecoveryCount += 1
        state = .failed(.playbackStalled)
    }

    func tearDown() {
        tearDownCalls += 1
        isPlaying = false
        state = .idle
        currentAsset = nil
    }
}

@MainActor
final class ProbeWatchdogSpy: StallWatchdogDelegate {
    var detectedStalls: [(displayID: CGDirectDisplayID, reason: String)] = []
    var recoveredStalls: [(displayID: CGDirectDisplayID, attempt: Int)] = []
    var failedRecoveries: [(displayID: CGDirectDisplayID, error: VideoEngineError)] = []

    func watchdog(_ watchdog: StallWatchdogProtocol, didDetectStallOn displayID: CGDirectDisplayID, reason: String) {
        detectedStalls.append((displayID, reason))
    }

    func watchdog(_ watchdog: StallWatchdogProtocol, didRecoverStallOn displayID: CGDirectDisplayID, attempt: Int) {
        recoveredStalls.append((displayID, attempt))
    }

    func watchdog(_ watchdog: StallWatchdogProtocol, didFailRecoveryOn displayID: CGDirectDisplayID, error: VideoEngineError) {
        failedRecoveries.append((displayID, error))
    }
}

// MARK: - Standalone Synthetic Video Generator

enum ProbeVideoGenerator {
    static func generateValidMP4() async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("probe_sample_\(UUID().uuidString).mp4")
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 240
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: 320,
            kCVPixelBufferHeightKey as String: 240
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, 320, 240,
            kCVPixelFormatType_32ARGB, nil,
            &pixelBuffer
        )

        if let buffer = pixelBuffer {
            CVPixelBufferLockBaseAddress(buffer, [])
            if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
                memset(baseAddress, 128, 320 * 240 * 4)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: .zero)
            adaptor.append(buffer, withPresentationTime: CMTime(value: 30, timescale: 30))
        }

        writerInput.markAsFinished()
        await writer.finishWriting()
        return tempURL
    }
}

// MARK: - Main Probe Execution Runner

@main
struct EmpiricalChallengerMain {
    static var totalPassed = 0
    static var totalFailed = 0

    @MainActor
    static func runProbe(_ name: String, _ body: () async throws -> Void) async {
        print("  - [PROBE] \(name)...", terminator: " ")
        fflush(stdout)
        let start = DispatchTime.now()
        do {
            try await body()
            let end = DispatchTime.now()
            let elapsedMs = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            print("[\u{001B}[32mPASS\u{001B}[0m] (\(String(format: "%.2f", elapsedMs))ms)")
            totalPassed += 1
        } catch {
            print("[\u{001B}[31mFAIL\u{001B}[0m]")
            print("    Error: \(error)")
            totalFailed += 1
        }
    }

    static func main() async {
        print("\n╔════════════════════════════════════════════════════════════════════╗")
        print("║   Milestone 2 Empirical Challenger Verification Suite              ║")
        print("║   StallWatchdog Escalation & Multi-Display Coordination Invariants ║")
        print("╚════════════════════════════════════════════════════════════════════╝\n")

        // =====================================================================
        // SECTION 1: Stall Detection & Escalation Ladder Invariants
        // =====================================================================
        print("=== SECTION 1: StallWatchdog Detection & Escalation Policy ===")

        await runProbe("1.1 Sub-threshold frozen PTS (< 3.0s equivalent) does not trigger stall recovery") {
            // Threshold = 200ms; check interval = 40ms
            let watchdog = StallWatchdog(stallThreshold: 0.20, checkInterval: 0.04, maxRecoveryAttempts: 3)
            let spy = ProbeWatchdogSpy()
            watchdog.delegate = spy

            let player = ChallengerProbePlayer(displayID: 101)
            player.play()
            player.currentTime = CMTime(seconds: 10.0, preferredTimescale: 600)
            watchdog.register(player: player)

            // Tick 0: establish baseline PTS
            await watchdog.evaluateMonitoredPlayers()
            try probeAssertEqual(player.recoverSoftCalls, 0, "No recovery on tick 0")

            // Wait 100ms with frozen PTS (50% of threshold)
            try await Task.sleep(nanoseconds: 100_000_000)
            await watchdog.evaluateMonitoredPlayers()
            try probeAssertEqual(player.recoverSoftCalls, 0, "Sub-threshold stall must NOT trigger recovery")
            try probeAssertEqual(spy.detectedStalls.count, 0, "No stall delegate notification before threshold")

            // Playback advances normally
            player.currentTime = CMTime(seconds: 10.5, preferredTimescale: 600)
            await watchdog.evaluateMonitoredPlayers()

            // Another 100ms pause from new PTS
            try await Task.sleep(nanoseconds: 100_000_000)
            await watchdog.evaluateMonitoredPlayers()
            try probeAssertEqual(player.recoverSoftCalls, 0, "Reset stall duration must NOT trigger recovery")
            try probeAssertEqual(spy.detectedStalls.count, 0, "Zero stalls reported")

            watchdog.stop()
        }

        await runProbe("1.2 Frozen PTS sustained >= threshold triggers Soft Recovery 1 (Attempt 1)") {
            let watchdog = StallWatchdog(stallThreshold: 0.15, checkInterval: 0.04, maxRecoveryAttempts: 3)
            let spy = ProbeWatchdogSpy()
            watchdog.delegate = spy

            let player = ChallengerProbePlayer(displayID: 102)
            player.play()
            player.currentTime = CMTime(seconds: 5.0, preferredTimescale: 600)
            watchdog.register(player: player)

            // Baseline
            await watchdog.evaluateMonitoredPlayers()

            // Freeze for 180ms (> 150ms threshold)
            try await Task.sleep(nanoseconds: 180_000_000)
            await watchdog.evaluateMonitoredPlayers()

            try probeAssertEqual(spy.detectedStalls.count, 1, "Must detect exactly 1 stall")
            try probeAssertEqual(player.recoverSoftCalls, 1, "Attempt 1 must invoke recoverSoft()")
            try probeAssertEqual(player.recoverHardCalls, 0, "Attempt 1 must NOT invoke recoverHard()")
            try probeAssertEqual(spy.failedRecoveries.count, 0, "Attempt 1 must not fail")

            watchdog.stop()
        }

        await runProbe("1.3 4-Tier Recovery Escalation Ladder (Soft 1 -> Soft 2 -> Hard 3 -> Failure)") {
            let watchdog = StallWatchdog(stallThreshold: 0.10, checkInterval: 0.03, maxRecoveryAttempts: 3)
            let spy = ProbeWatchdogSpy()
            watchdog.delegate = spy

            let player = ChallengerProbePlayer(displayID: 103)
            player.play()
            player.currentTime = CMTime(seconds: 1.0, preferredTimescale: 600)
            watchdog.register(player: player)

            // Baseline
            await watchdog.evaluateMonitoredPlayers()

            // --- STALL 1 -> Soft Recovery 1 ---
            try await Task.sleep(nanoseconds: 120_000_000)
            await watchdog.evaluateMonitoredPlayers()
            try probeAssertEqual(player.recoverSoftCalls, 1, "Step 1: recoverSoft() attempt 1")
            try probeAssertEqual(player.recoverHardCalls, 0, "Step 1: no hard recovery")

            // --- STALL 2 -> Soft Recovery 2 ---
            try await Task.sleep(nanoseconds: 120_000_000)
            await watchdog.evaluateMonitoredPlayers()
            try probeAssertEqual(player.recoverSoftCalls, 2, "Step 2: recoverSoft() attempt 2")
            try probeAssertEqual(player.recoverHardCalls, 0, "Step 2: no hard recovery")

            // --- STALL 3 -> Hard Recovery 3 ---
            try await Task.sleep(nanoseconds: 120_000_000)
            await watchdog.evaluateMonitoredPlayers()
            try probeAssertEqual(player.recoverSoftCalls, 2, "Step 3: recoverSoft() stays at 2")
            try probeAssertEqual(player.recoverHardCalls, 1, "Step 3: recoverHard() attempt 3 invoked")
            try probeAssertEqual(spy.failedRecoveries.count, 0, "Step 3: not marked failed yet")

            // --- STALL 4 -> Escalation limit exceeded: Unrecoverable Failure ---
            try await Task.sleep(nanoseconds: 120_000_000)
            await watchdog.evaluateMonitoredPlayers()
            try probeAssertEqual(spy.failedRecoveries.count, 1, "Step 4: must report unrecoverable failure")
            try probeAssertEqual(spy.failedRecoveries.first?.error, .playbackStalled, "Step 4: error is .playbackStalled")

            watchdog.stop()
        }

        await runProbe("1.4 Throwing Hard Recovery immediately declares unrecoverable failure") {
            let watchdog = StallWatchdog(stallThreshold: 0.10, checkInterval: 0.03, maxRecoveryAttempts: 3)
            let spy = ProbeWatchdogSpy()
            watchdog.delegate = spy

            let player = ChallengerProbePlayer(displayID: 104)
            player.play()
            player.currentTime = CMTime(seconds: 1.0, preferredTimescale: 600)
            player.shouldThrowOnHardRecovery = true
            watchdog.register(player: player)

            await watchdog.evaluateMonitoredPlayers()

            // Soft 1
            try await Task.sleep(nanoseconds: 120_000_000)
            await watchdog.evaluateMonitoredPlayers()

            // Soft 2
            try await Task.sleep(nanoseconds: 120_000_000)
            await watchdog.evaluateMonitoredPlayers()

            // Hard 3: throws
            try await Task.sleep(nanoseconds: 120_000_000)
            await watchdog.evaluateMonitoredPlayers()

            try probeAssertEqual(player.recoverHardCalls, 1, "recoverHard() must be attempted")
            try probeAssertEqual(spy.failedRecoveries.count, 1, "Thrown hard recovery must immediately escalate to failure")
            try probeAssertEqual(spy.failedRecoveries.first?.error, .playbackStalled, "Error must be .playbackStalled")

            watchdog.stop()
        }

        await runProbe("1.5 Resumed normal playback resets consecutive stall count to 0") {
            let watchdog = StallWatchdog(stallThreshold: 0.10, checkInterval: 0.03, maxRecoveryAttempts: 3)
            let spy = ProbeWatchdogSpy()
            watchdog.delegate = spy

            let player = ChallengerProbePlayer(displayID: 105)
            player.play()
            player.currentTime = CMTime(seconds: 20.0, preferredTimescale: 600)
            watchdog.register(player: player)

            await watchdog.evaluateMonitoredPlayers()

            // Accumulate 2 soft stalls
            try await Task.sleep(nanoseconds: 120_000_000)
            await watchdog.evaluateMonitoredPlayers()
            try await Task.sleep(nanoseconds: 120_000_000)
            await watchdog.evaluateMonitoredPlayers()
            try probeAssertEqual(player.recoverSoftCalls, 2, "2 soft stalls reached")

            // Playback advances normally
            player.currentTime = CMTime(seconds: 21.5, preferredTimescale: 600)
            await watchdog.evaluateMonitoredPlayers()

            try probeAssertEqual(spy.recoveredStalls.count, 1, "Delegate notified of recovery")
            try probeAssertEqual(spy.recoveredStalls.first?.attempt, 2, "Reported recovered after attempt 2")

            // Next stall occurs: must start at Step 1 (Soft 1), NOT Step 3 (Hard)
            try await Task.sleep(nanoseconds: 120_000_000)
            await watchdog.evaluateMonitoredPlayers()

            try probeAssertEqual(player.recoverSoftCalls, 3, "New stall must execute Soft Recovery (Step 1 of new cycle)")
            try probeAssertEqual(player.recoverHardCalls, 0, "Must NOT jump to Hard Recovery")

            watchdog.stop()
        }

        await runProbe("1.6 Buffer Starvation (isPlaybackBufferEmpty) activates stall recovery") {
            let watchdog = StallWatchdog(stallThreshold: 0.10, checkInterval: 0.03, maxRecoveryAttempts: 3)
            let spy = ProbeWatchdogSpy()
            watchdog.delegate = spy

            let player = ChallengerProbePlayer(displayID: 106)
            player.play()
            player.isPlaybackBufferEmpty = true
            watchdog.register(player: player)

            await watchdog.evaluateMonitoredPlayers()
            try await Task.sleep(nanoseconds: 120_000_000)
            await watchdog.evaluateMonitoredPlayers()

            try probeAssertEqual(spy.detectedStalls.count, 1, "Buffer empty must trigger stall detection")
            try probeAssert(spy.detectedStalls.first?.reason.contains("buffer") ?? false, "Reason mentions buffer")
            try probeAssertEqual(player.recoverSoftCalls, 1, "Triggers soft recovery")

            watchdog.stop()
        }

        // =====================================================================
        // SECTION 2: Intentional Pause Immunity & Zero False Positive Invariants
        // =====================================================================
        print("\n=== SECTION 2: Intentional Pause Immunity ===")

        await runProbe("2.1 Extended user pause produces zero stall false positives") {
            let watchdog = StallWatchdog(stallThreshold: 0.08, checkInterval: 0.03, maxRecoveryAttempts: 3)
            let spy = ProbeWatchdogSpy()
            watchdog.delegate = spy

            let player = ChallengerProbePlayer(displayID: 201)
            player.pause(reason: .userRequested)
            watchdog.register(player: player)

            // Run 10 evaluation ticks over 300ms while paused
            for _ in 0..<10 {
                try await Task.sleep(nanoseconds: 30_000_000)
                await watchdog.evaluateMonitoredPlayers()
            }

            try probeAssertEqual(spy.detectedStalls.count, 0, "Zero detected stalls while paused")
            try probeAssertEqual(player.recoverSoftCalls, 0, "Zero soft recoveries")
            try probeAssertEqual(player.recoverHardCalls, 0, "Zero hard recoveries")
            try probeAssertEqual(player.state, .paused(reason: .userRequested), "State unchanged")

            watchdog.stop()
        }

        await runProbe("2.2 All system pause states (sleep, lock, low power, battery, occlusion) immune from watchdog") {
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
            let spy = ProbeWatchdogSpy()
            watchdog.delegate = spy

            for (idx, reason) in reasons.enumerated() {
                let id = CGDirectDisplayID(300 + idx)
                let player = ChallengerProbePlayer(displayID: id)
                player.pause(reason: reason)
                watchdog.register(player: player)

                try await Task.sleep(nanoseconds: 60_000_000)
                await watchdog.evaluateMonitoredPlayers()

                try probeAssertEqual(player.recoverSoftCalls, 0, "Reason '\(reason.rawValue)' must not trigger recovery")
                try probeAssertEqual(player.state, .paused(reason: reason), "State preserved")
                watchdog.unregister(displayID: id)
            }

            try probeAssertEqual(spy.detectedStalls.count, 0, "Zero stalls across all pause reasons")
            watchdog.stop()
        }

        await runProbe("2.3 Mid-stall pause wipes accumulated stall duration with no false positive on unpause") {
            let watchdog = StallWatchdog(stallThreshold: 0.20, checkInterval: 0.04, maxRecoveryAttempts: 3)
            let spy = ProbeWatchdogSpy()
            watchdog.delegate = spy

            let player = ChallengerProbePlayer(displayID: 203)
            player.play()
            player.currentTime = CMTime(seconds: 50.0, preferredTimescale: 600)
            watchdog.register(player: player)

            // Baseline
            await watchdog.evaluateMonitoredPlayers()

            // Freeze for 100ms (50% of 200ms threshold)
            try await Task.sleep(nanoseconds: 100_000_000)
            await watchdog.evaluateMonitoredPlayers()
            try probeAssertEqual(player.recoverSoftCalls, 0, "Sub-threshold accumulation")

            // User pauses: watchdog should clear stalled duration
            player.pause(reason: .userRequested)
            watchdog.handleTimeControlStatusChange(.paused, for: 203)
            await watchdog.evaluateMonitoredPlayers()

            // Stay paused for 250ms (> threshold)
            try await Task.sleep(nanoseconds: 250_000_000)
            await watchdog.evaluateMonitoredPlayers()
            try probeAssertEqual(player.recoverSoftCalls, 0, "No stall while paused")

            // Unpause and immediately evaluate: should NOT fire stall from previous accumulation
            player.play()
            player.currentTime = CMTime(seconds: 51.0, preferredTimescale: 600)
            watchdog.handleTimeControlStatusChange(.playing, for: 203)
            await watchdog.evaluateMonitoredPlayers()

            try probeAssertEqual(player.recoverSoftCalls, 0, "Unpaused player must not falsely trigger stall")
            watchdog.stop()
        }

        // =====================================================================
        // SECTION 3: Multi-Display VideoEngine Coordination & Pointer Identity
        // =====================================================================
        print("\n=== SECTION 3: Multi-Display Coordination & Pointer Identity ===")

        await runProbe("3.1 Multi-display initialization assigns distinct isolated player instances") {
            let windowManager = ProbeMockDesktopWindowManager()
            let engine = VideoEngine(
                windowManager: windowManager,
                playerFactory: { id, _ in ChallengerProbePlayer(displayID: id) }
            )

            engine.registerDisplay(1)
            engine.registerDisplay(2)
            engine.registerDisplay(3)

            try probeAssertEqual(engine.activeDisplays, [1, 2, 3], "Active displays must be [1, 2, 3]")
            guard let p1 = engine.player(for: 1),
                  let p2 = engine.player(for: 2),
                  let p3 = engine.player(for: 3) else {
                throw ProbeError.assertionFailed("All 3 display players must exist")
            }

            try probeAssert(p1 !== p2, "Player 1 and Player 2 must have distinct pointer identity")
            try probeAssert(p2 !== p3, "Player 2 and Player 3 must have distinct pointer identity")
            try probeAssert(p1 !== p3, "Player 1 and Player 3 must have distinct pointer identity")

            engine.stop()
        }

        await runProbe("3.2 8-Step display resolution ladder strictly preserves player pointer identity (===)") {
            let windowManager = ProbeMockDesktopWindowManager()
            let window = ProbeMockDesktopWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
            windowManager.managedWindows[1] = window

            let engine = VideoEngine(
                windowManager: windowManager,
                playerFactory: { id, _ in ChallengerProbePlayer(displayID: id) }
            )
            engine.registerDisplay(1)

            guard let originalPlayer = engine.player(for: 1) else {
                throw ProbeError.assertionFailed("Original player for display 1 must exist")
            }

            let resolutions: [CGSize] = [
                CGSize(width: 1920, height: 1080),
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
                window.updateFrame(newFrame)

                // Inform engine of resolution change
                engine.displayConfigurationDidChange(added: [], removed: [], updated: [1])

                let currentPlayer = engine.player(for: 1)
                try probeAssert(
                    currentPlayer === originalPlayer,
                    "Step \(idx) (\(Int(size.width))x\(Int(size.height))): Player pointer identity must be strictly preserved"
                )
            }

            engine.stop()
        }

        await runProbe("3.3 DesktopWindow updateFrame resizes CALayer in-place without instance recreation") {
            let window = DesktopWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
            let playerLayer = AVPlayerLayer()
            window.attachPlayerLayer(playerLayer)

            try probeAssertEqual(playerLayer.frame.size, CGSize(width: 1920, height: 1080), "Initial layer size 1080p")

            let frame4K = CGRect(x: 0, y: 0, width: 3840, height: 2160)
            window.updateFrame(frame4K)

            try probeAssertEqual(window.frame.size, CGSize(width: 3840, height: 2160), "Window frame 4K")
            try probeAssertEqual(playerLayer.frame.size, CGSize(width: 3840, height: 2160), "CALayer resized in-place to 4K")
            try probeAssert(window.currentActiveLayer === playerLayer, "Layer pointer identity strictly preserved")

            window.closeAndRelease()
        }

        await runProbe("3.4 Disconnecting screen invokes tearDown() and detaches player layer cleanly") {
            let windowManager = ProbeMockDesktopWindowManager()
            let window = ProbeMockDesktopWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
            windowManager.managedWindows[1] = window

            let engine = VideoEngine(
                windowManager: windowManager,
                playerFactory: { id, _ in ChallengerProbePlayer(displayID: id) }
            )
            engine.registerDisplay(1)

            guard let player = engine.player(for: 1) as? ChallengerProbePlayer else {
                throw ProbeError.assertionFailed("Player must be ChallengerProbePlayer")
            }

            try probeAssertEqual(player.tearDownCalls, 0, "No tearDown initially")

            // Disconnect display
            engine.displayConfigurationDidChange(added: [], removed: [1], updated: [])

            try probeAssertNil(engine.player(for: 1), "Player removed from engine")
            try probeAssertEqual(player.tearDownCalls, 1, "tearDown() must be called on disconnected player")

            engine.stop()
        }

        await runProbe("3.5 Multi-display isolation: disconnecting display 2 leaves display 1 and 3 undisturbed") {
            let windowManager = ProbeMockDesktopWindowManager()
            let engine = VideoEngine(
                windowManager: windowManager,
                playerFactory: { id, _ in ChallengerProbePlayer(displayID: id) }
            )

            engine.registerDisplay(1)
            engine.registerDisplay(2)
            engine.registerDisplay(3)

            let p1 = engine.player(for: 1)
            let p2 = engine.player(for: 2)
            let p3 = engine.player(for: 3)
            try probeAssert(p2 != nil, "Display 2 player must exist prior to removal")

            // Remove display 2
            engine.displayConfigurationDidChange(added: [], removed: [2], updated: [])

            try probeAssertNil(engine.player(for: 2), "Display 2 removed")
            try probeAssert(engine.player(for: 1) === p1, "Display 1 player unchanged")
            try probeAssert(engine.player(for: 3) === p3, "Display 3 player unchanged")
            try probeAssertEqual(engine.activeDisplays, [1, 3], "Active displays are [1, 3]")

            engine.stop()
        }

        await runProbe("3.6 200-cycle display connect/disconnect chaos storm produces zero leaked player instances") {
            let windowManager = ProbeMockDesktopWindowManager()
            let engine = VideoEngine(
                windowManager: windowManager,
                playerFactory: { id, _ in ChallengerProbePlayer(displayID: id) }
            )

            var trackedPlayerBoxes: [WeakPlayerReferenceBox] = []

            for cycle in 0..<200 {
                let targetID = CGDirectDisplayID((cycle % 5) + 1)
                if engine.player(for: targetID) != nil {
                    engine.displayConfigurationDidChange(added: [], removed: [targetID], updated: [])
                } else {
                    engine.displayConfigurationDidChange(added: [targetID], removed: [], updated: [])
                    if let player = engine.player(for: targetID) {
                        trackedPlayerBoxes.append(WeakPlayerReferenceBox(player))
                    }
                }
            }

            engine.stop()
            try await Task.sleep(nanoseconds: 10_000_000)

            var leaks = 0
            for box in trackedPlayerBoxes {
                if box.player != nil {
                    leaks += 1
                }
            }

            try probeAssertEqual(leaks, 0, "200-cycle storm must leave 0 leaked players in memory")
        }

        await runProbe("3.7 Real DisplayVideoPlayer & Real DesktopWindow AVFoundation deallocation audit") {
            let videoURL = try await ProbeVideoGenerator.generateValidMP4()

            var weakBox: WeakPlayerReferenceBox?
            do {
                let realWindow = DesktopWindow(frame: CGRect(x: 0, y: 0, width: 640, height: 480), displayID: 99)
                let realPlayer = DisplayVideoPlayer(displayID: 99)
                weakBox = WeakPlayerReferenceBox(realPlayer)

                realPlayer.attach(to: realWindow)
                try await realPlayer.load(url: videoURL, crossfade: false)
                realPlayer.play()

                try probeAssert(weakBox?.player != nil, "Real player active while held in scope")

                realPlayer.tearDown()
                realWindow.closeAndRelease()
            }

            try await Task.sleep(nanoseconds: 20_000_000)
            try probeAssert(weakBox?.player == nil, "Real DisplayVideoPlayer fully deallocated (0 ARC leaks)")
            try? FileManager.default.removeItem(at: videoURL)
        }

        print("\n==================================================")
        print("EMPIRICAL CHALLENGER PROBE SUMMARY:")
        print("  Total Probes: \(totalPassed + totalFailed)")
        print("  Passed:       \u{001B}[32m\(totalPassed)\u{001B}[0m")
        print("  Failed:       \(totalFailed > 0 ? "\u{001B}[31m\(totalFailed)\u{001B}[0m" : "0")")
        print("==================================================")

        if totalFailed > 0 {
            print("\n\u{001B}[31mEMPIRICAL CHALLENGER PROBES FAILED!\u{001B}[0m\n")
            exit(1)
        } else {
            print("\n\u{001B}[32mALL Milestone 2 Empirical Challenger Probes PASSED!\u{001B}[0m\n")
            exit(0)
        }
    }
}

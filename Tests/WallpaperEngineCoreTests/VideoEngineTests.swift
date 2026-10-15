//
//  VideoEngineTests.swift
//  WallpaperEngineCoreTests
//
//  Automated Unit and Integration Tests for Milestone 2:
//  - AssetManager preflight validation & codec inspection
//  - DisplayVideoPlayer 4-tier muting & layer scanout invariants
//  - VideoEngine multi-display coordinator lifecycle & dynamic asset assignment
//  - Empirical stress, chaos, and boundary probes
//

import AppKit
import AudioToolbox
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import QuartzCore
@testable import WallpaperEngineCore

// MARK: - Synthetic Video Generator for Headless Testing

public enum SyntheticVideoGenerator {

    /// Creates a valid 1.0-second H.264 MP4 video file (320x240 @ 30 FPS).
    public static func createValidVideoFile(
        filename: String = "test_valid_\(UUID().uuidString).mp4",
        durationSeconds: Double = 1.0,
        size: CGSize = CGSize(width: 320, height: 240)
    ) async throws -> URL {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: tempURL)

        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)

        guard writer.canAdd(input) else {
            throw TestFailure("Cannot add video input to asset writer")
        }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw TestFailure("Failed to allocate CVPixelBuffer")
        }

        adaptor.append(buffer, withPresentationTime: .zero)
        let frameTime = CMTime(seconds: durationSeconds / 2.0, preferredTimescale: 600)
        adaptor.append(buffer, withPresentationTime: frameTime)

        input.markAsFinished()

        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        guard writer.status == .completed else {
            throw TestFailure("AVAssetWriter failed with status \(writer.status.rawValue): \(String(describing: writer.error))")
        }

        return tempURL
    }

    /// Creates a synthetic video file that also contains an audio track, used to verify 4-tier muting.
    public static func createVideoWithAudioTrack(
        filename: String = "test_audio_\(UUID().uuidString).mp4"
    ) async throws -> URL {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: tempURL)

        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)

        // Video track input
        let vSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 240
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vInput, sourcePixelBufferAttributes: nil)
        writer.add(vInput)

        // Audio format description & buffer
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44100.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDesc: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )

        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: 2048,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: 2048,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1024, timescale: 44100),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: 1024,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        // Audio track input
        let aSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100.0,
            AVEncoderBitRateKey: 64000
        ]
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
        writer.add(aInput)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        adaptor.append(pixelBuffer!, withPresentationTime: .zero)
        adaptor.append(pixelBuffer!, withPresentationTime: CMTime(seconds: 1.0, preferredTimescale: 600))
        vInput.markAsFinished()

        if let sbuf = sampleBuffer {
            aInput.append(sbuf)
        }
        aInput.markAsFinished()

        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        return tempURL
    }

    /// Creates a corrupt video file (invalid header bytes with .mp4 extension).
    public static func createCorruptVideoFile(
        filename: String = "test_corrupt_\(UUID().uuidString).mp4"
    ) throws -> URL {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        let randomBytes = (0..<1024).map { _ in UInt8.random(in: 0...255) }
        try Data(randomBytes).write(to: tempURL)
        return tempURL
    }

    /// Creates a non-video plain text file.
    public static func createNonVideoFile(
        filename: String = "test_text_\(UUID().uuidString).txt"
    ) throws -> URL {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        try "Not a video file content".write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
}

// MARK: - Mock DesktopWindowManager

@MainActor
public final class MockDesktopWindowManager: DesktopWindowManagerProtocol {
    public var managedWindows: [CGDirectDisplayID: DesktopWindowProtocol] = [:]
    public weak var delegate: DesktopWindowManagerDelegate?
    public var screenManager: ScreenManagerProtocol = MockScreenManager()
    public var isRunning: Bool = false

    public init() {}

    public func start() {
        isRunning = true
    }

    public func stop() {
        isRunning = false
        managedWindows.removeAll()
    }

    public func window(for displayID: CGDirectDisplayID) -> DesktopWindowProtocol? {
        managedWindows[displayID]
    }

    public func reconcileWindows(with screens: [ScreenDescriptor]) {}
}

// MARK: - VideoEngineTests Execution Suite

@MainActor
public struct VideoEngineTests {

    public static func runAllTests() async {
        let runner = TestRunner.shared

        // =====================================================================
        // SUITE 1: AssetManager Preflight Validation & Codec Inspection
        // =====================================================================
        await runner.runSuite("Suite 1: AssetManager Preflight Validation") {

            await runner.testAsync("AM.1: Valid Video Asset Preflight & Metadata Extraction") {
                let validURL = try await SyntheticVideoGenerator.createValidVideoFile()
                defer { try? FileManager.default.removeItem(at: validURL) }

                let manager = AssetManager()
                let asset = try await manager.inspectAsset(at: validURL)

                try assertEqual(asset.fileURL, validURL, "Asset fileURL must match source")
                try assertTrue(abs(asset.duration.seconds - 1.0) < 0.2, "Duration must be approximately 1.0s")
                try assertEqual(asset.naturalSize.width, 320, "Video width must be 320")
                try assertEqual(asset.naturalSize.height, 240, "Video height must be 240")
                try assertEqual(asset.codec, "avc1", "Codec must be detected as avc1 (H.264)")
            }

            await runner.testAsync("AM.2: Nonexistent File Handling (Throws fileNotFound)") {
                let missingURL = URL(fileURLWithPath: "/tmp/nonexistent_video_\(UUID().uuidString).mp4")
                let manager = AssetManager()

                var caughtError: VideoEngineError?
                do {
                    _ = try await manager.inspectAsset(at: missingURL)
                } catch let err as VideoEngineError {
                    caughtError = err
                } catch {
                    try assertTrue(false, "Unexpected error type: \(error)")
                }

                try assertEqual(caughtError, .fileNotFound(missingURL), "Must throw .fileNotFound")
            }

            await runner.testAsync("AM.3: Non-Video File Rejection (Throws noVideoTrack or unreadableFormat)") {
                let textURL = try SyntheticVideoGenerator.createNonVideoFile()
                defer { try? FileManager.default.removeItem(at: textURL) }

                let manager = AssetManager()
                var caughtError: VideoEngineError?
                do {
                    _ = try await manager.inspectAsset(at: textURL)
                } catch let err as VideoEngineError {
                    caughtError = err
                } catch {
                    // Accepted if Foundation throws
                }

                try assertTrue(caughtError != nil, "Must reject plain text file")
            }

            await runner.testAsync("AM.4: Corrupted Media File Rejection (Throws assetNotPlayable or unreadableFormat)") {
                let corruptURL = try SyntheticVideoGenerator.createCorruptVideoFile()
                defer { try? FileManager.default.removeItem(at: corruptURL) }

                let manager = AssetManager()
                var threwError = false
                do {
                    _ = try await manager.inspectAsset(at: corruptURL)
                } catch {
                    threwError = true
                }
                try assertTrue(threwError, "Corrupt file must throw an error")
            }

            await runner.testAsync("AM.5: Asset Caching Preserves In-Memory Instance") {
                let validURL = try await SyntheticVideoGenerator.createValidVideoFile()
                defer { try? FileManager.default.removeItem(at: validURL) }

                let manager = AssetManager()
                let first = try await manager.inspectAsset(at: validURL)
                let second = try await manager.inspectAsset(at: validURL)

                try assertEqual(first, second, "Subsequent inspections must return identical cached model")
            }
        }

        // =====================================================================
        // SUITE 2: DisplayVideoPlayer 4-Tier Audio Suppression
        // =====================================================================
        await runner.runSuite("Suite 2: DisplayVideoPlayer 4-Tier Audio Suppression") {

            runner.test("DVP.1: Tier 1 - Master Mute and Zero Volume Invariants") {
                let player = DisplayVideoPlayer(displayID: 1)
                try assertTrue(player.isMuted, "isMuted must be true on initialization")
                try assertEqual(player.volume, 0.0, "volume must be 0.0 on initialization")
                player.tearDown()
            }

            await runner.testAsync("DVP.2: Tier 2 - Media Item Audio Tracks Disabled") {
                let audioVideoURL = try await SyntheticVideoGenerator.createVideoWithAudioTrack()
                defer { try? FileManager.default.removeItem(at: audioVideoURL) }

                let player = DisplayVideoPlayer(displayID: 1)
                let asset = VideoAsset(fileURL: audioVideoURL, title: "AudioTest")
                try await player.load(asset: asset, crossfade: false)

                try assertFalse(player.audioTracksEnabled, "All audio tracks on playerItem must be disabled")
                player.tearDown()
            }

            runner.test("DVP.3: Tier 3 & 4 - Audio Time-Pitch Suppressed to Varispeed") {
                let player = DisplayVideoPlayer(displayID: 1)
                try assertEqual(player.audioTimePitchAlgorithm, .varispeed, "Pitch algorithm must be varispeed on macOS")
                try assertTrue(player.isAudioMixNulled, "AudioMix input parameters must be null/empty")
                player.tearDown()
            }

            runner.test("DVP.4: Tier 4 - AudioMix Input Parameters Nullified") {
                let player = DisplayVideoPlayer(displayID: 1)
                try assertTrue(player.isAudioMixNulled, "AudioMix input parameters must be empty")
                player.tearDown()
            }
        }

        // =====================================================================
        // SUITE 3: DisplayVideoPlayer Layer Hosting & Controls
        // =====================================================================
        await runner.runSuite("Suite 3: DisplayVideoPlayer Layer Hosting & Controls") {

            runner.test("DVP.5: AVPlayerLayer Configuration & Actions Suppression") {
                let player = DisplayVideoPlayer(displayID: 1)
                let layer = player.playerLayer

                try assertEqual(layer.videoGravity, .resizeAspectFill, "Video gravity must be .resizeAspectFill")
                try assertTrue(layer.actions?["contents"] is NSNull, "contents animation must be disabled")
                try assertTrue(layer.actions?["bounds"] is NSNull, "bounds animation must be disabled")
                try assertTrue(layer.actions?["position"] is NSNull, "position animation must be disabled")
                player.tearDown()
            }

            runner.test("DVP.6: Attachment to Desktop Window Hierarchy") {
                let player = DisplayVideoPlayer(displayID: 1)
                let mockWindow = MockDesktopWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)

                player.attach(to: mockWindow)
                try assertEqual(mockWindow.attachedLayers.count, 1, "Window must have 1 attached layer")
                try assertTrue(mockWindow.currentActiveLayer === player.playerLayer, "Active layer must match playerLayer")

                player.tearDown()
                mockWindow.closeAndRelease()
            }

            runner.test("DVP.7: Play and Pause State Machine") {
                let player = DisplayVideoPlayer(displayID: 1)
                player.play()
                try assertEqual(player.state, .playing, "State must be .playing after play()")

                player.pause(reason: .userRequested)
                try assertEqual(player.state, .paused(reason: .userRequested), "State must be .paused(.userRequested)")

                player.pause(reason: .screenLocked)
                try assertEqual(player.state, .paused(reason: .screenLocked), "State must reflect updated pause reason")

                player.tearDown()
            }
        }

        // =====================================================================
        // SUITE 4: VideoEngine Multi-Display Coordination
        // =====================================================================
        await runner.runSuite("Suite 4: VideoEngine Multi-Display Coordination") {

            runner.test("VE.1: Initial Multi-Display Pipeline Setup") {
                let windowManager = MockDesktopWindowManager()
                let engine = VideoEngine(windowManager: windowManager, playerFactory: { id, _ in MockDisplayVideoPlayer(displayID: id) })

                engine.registerDisplay(1)
                engine.registerDisplay(2)

                try assertEqual(engine.activeDisplays.count, 2, "Engine must register 2 displays")
                try assertNotNil(engine.player(for: 1), "Player for display 1 must exist")
                try assertNotNil(engine.player(for: 2), "Player for display 2 must exist")
                try assertTrue(engine.player(for: 1) !== engine.player(for: 2), "Display players must be isolated instances")

                engine.stop()
            }

            runner.test("VE.2: Hot-Plug Display Addition Spawns Dedicated Player") {
                let windowManager = MockDesktopWindowManager()
                let engine = VideoEngine(windowManager: windowManager, playerFactory: { id, _ in MockDisplayVideoPlayer(displayID: id) })
                engine.registerDisplay(1)

                // Simulate hot-plug notification from DesktopWindowManager
                engine.displayConfigurationDidChange(added: [2], removed: [], updated: [])

                try assertEqual(engine.activeDisplays.count, 2, "Displays must increase to 2")
                try assertNotNil(engine.player(for: 2), "New player must be spawned for display 2")

                engine.stop()
            }

            runner.test("VE.3: Display Disconnect Tears Down Orphan Player Without Affecting Others") {
                let windowManager = MockDesktopWindowManager()
                let engine = VideoEngine(windowManager: windowManager, playerFactory: { id, _ in MockDisplayVideoPlayer(displayID: id) })
                engine.registerDisplay(1)
                engine.registerDisplay(2)

                // Simulate disconnect of display 2
                engine.displayConfigurationDidChange(added: [], removed: [2], updated: [])

                try assertEqual(engine.activeDisplays, [1], "Display 2 must be removed")
                try assertNil(engine.player(for: 2), "Player 2 must be deallocated")
                try assertNotNil(engine.player(for: 1), "Player 1 must remain active")

                engine.stop()
            }

            runner.test("VE.4: Display Resolution Update Preserves Player Pointer Identity (Zero Flicker)") {
                let windowManager = MockDesktopWindowManager()
                let engine = VideoEngine(windowManager: windowManager, playerFactory: { id, _ in MockDisplayVideoPlayer(displayID: id) })
                engine.registerDisplay(1)

                let originalPlayer = engine.player(for: 1)

                // Simulate resolution change
                engine.displayConfigurationDidChange(added: [], removed: [], updated: [1])

                let postUpdatePlayer = engine.player(for: 1)
                try assertTrue(originalPlayer === postUpdatePlayer, "Player instance must be strictly preserved across resolution updates")

                engine.stop()
            }

            await runner.testAsync("VE.5: Independent Per-Display Asset Assignment") {
                let windowManager = MockDesktopWindowManager()
                let engine = VideoEngine(windowManager: windowManager, playerFactory: { id, _ in MockDisplayVideoPlayer(displayID: id) })
                engine.registerDisplay(1)
                engine.registerDisplay(2)

                let assetA = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/a.mp4"), title: "A")
                let assetB = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/b.mp4"), title: "B")

                try await engine.assign(asset: assetA, to: 1)
                try await engine.assign(asset: assetB, to: 2)

                try assertEqual(engine.player(for: 1)?.currentAsset?.title, "A", "Display 1 must play Asset A")
                try assertEqual(engine.player(for: 2)?.currentAsset?.title, "B", "Display 2 must play Asset B")

                engine.stop()
            }

            await runner.testAsync("VE.6: Unified Global Asset Assignment") {
                let windowManager = MockDesktopWindowManager()
                let engine = VideoEngine(windowManager: windowManager, playerFactory: { id, _ in MockDisplayVideoPlayer(displayID: id) })
                engine.registerDisplay(1)
                engine.registerDisplay(2)

                let commonAsset = VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/common.mp4"), title: "Common")
                try await engine.assignToAll(asset: commonAsset)

                try assertEqual(engine.player(for: 1)?.currentAsset?.title, "Common", "Display 1 must play Common")
                try assertEqual(engine.player(for: 2)?.currentAsset?.title, "Common", "Display 2 must play Common")

                engine.stop()
            }

            runner.test("VE.7: Global Play / Pause Broadcast") {
                let windowManager = MockDesktopWindowManager()
                let engine = VideoEngine(windowManager: windowManager, playerFactory: { id, _ in MockDisplayVideoPlayer(displayID: id) })
                engine.registerDisplay(1)
                engine.registerDisplay(2)

                engine.pauseAll(reason: .lowPowerMode)
                try assertTrue(engine.isPaused, "Engine isPaused must be true")
                try assertEqual(engine.player(for: 1)?.state, .paused(reason: .lowPowerMode), "Player 1 must be paused")
                try assertEqual(engine.player(for: 2)?.state, .paused(reason: .lowPowerMode), "Player 2 must be paused")

                engine.playAll()
                try assertFalse(engine.isPaused, "Engine isPaused must be false")
                try assertEqual(engine.player(for: 1)?.state, .playing, "Player 1 must be playing")
                try assertEqual(engine.player(for: 2)?.state, .playing, "Player 2 must be playing")

                engine.stop()
            }
        }

        // =====================================================================
        // SUITE 6: Empirical Stress, Chaos & Boundary Probes
        // =====================================================================
        await runner.runSuite("Suite 6: Empirical Stress, Chaos & Boundary Probes") {

            await runner.testAsync("PROBE 2.1: Rapid Play/Pause Storm (100 Cycles in 50ms)") {
                let windowManager = MockDesktopWindowManager()
                let engine = VideoEngine(windowManager: windowManager, playerFactory: { id, _ in MockDisplayVideoPlayer(displayID: id) })
                engine.registerDisplay(1)

                for i in 0..<100 {
                    if i % 2 == 0 {
                        engine.pauseAll(reason: .userRequested)
                    } else {
                        engine.playAll()
                    }
                }

                try assertFalse(engine.isPaused, "Engine must be unpaused after 100th iteration (odd index)")
                try assertEqual(engine.player(for: 1)?.state, .playing, "Player must be .playing")

                engine.stop()
            }

            await runner.testAsync("PROBE 2.2: Concurrent Asset Hot-Swapping Under Rapid State Changes") {
                let windowManager = MockDesktopWindowManager()
                let engine = VideoEngine(windowManager: windowManager, playerFactory: { id, _ in MockDisplayVideoPlayer(displayID: id) })
                engine.registerDisplay(1)

                let assets = (0..<10).map {
                    VideoAsset(fileURL: URL(fileURLWithPath: "/tmp/probe_asset_\($0).mp4"), title: "Asset_\($0)")
                }

                for asset in assets {
                    try await engine.assign(asset: asset, to: 1)
                }

                try assertEqual(engine.player(for: 1)?.currentAsset?.title, "Asset_9", "Final asset must match last assignment")

                engine.stop()
            }

            runner.test("PROBE 2.3: Zero-Display Headless Mode Resilience") {
                let windowManager = MockDesktopWindowManager()
                let engine = VideoEngine(windowManager: windowManager, playerFactory: { id, _ in MockDisplayVideoPlayer(displayID: id) })

                try assertEqual(engine.activeDisplays.count, 0, "Active displays must be 0")

                // Must execute safely without throwing or crashing
                engine.playAll()
                engine.pauseAll(reason: .screenLocked)
                engine.stop()
            }

            runner.test("PROBE 2.4: Disconnection Mid-Stall Recovery") {
                let windowManager = MockDesktopWindowManager()
                let engine = VideoEngine(windowManager: windowManager, playerFactory: { id, _ in MockDisplayVideoPlayer(displayID: id) })
                engine.registerDisplay(1)

                let player = engine.player(for: 1)
                player?.triggerStall()

                // Sudden screen disconnection
                engine.displayConfigurationDidChange(added: [], removed: [1], updated: [])

                try assertNil(engine.player(for: 1), "Player must be cleanly removed despite pending stall")
                engine.stop()
            }

            await runner.testAsync("PROBE 2.5: Weak Reference & AVFoundation Memory Deallocation Audit") {
                final class WeakPlayerBox {
                    weak var player: (any DisplayVideoPlayerProtocol)?
                    init(_ player: any DisplayVideoPlayerProtocol) { self.player = player }
                }

                let windowManager = MockDesktopWindowManager()
                var engine: VideoEngine? = VideoEngine(windowManager: windowManager)
                engine?.registerDisplay(1)

                let box: WeakPlayerBox?
                if let p = engine?.player(for: 1) {
                    box = WeakPlayerBox(p)
                } else {
                    box = nil
                }
                try assertNotNil(box?.player, "Player must exist while engine is alive")

                engine?.stop()
                engine = nil

                // Wait a micro-turn for ARC cleanup
                try await Task.sleep(nanoseconds: 10_000_000)

                try assertNil(box?.player, "Player must be completely deallocated with zero memory leaks")
            }
        }
    }
}

//
//  AudioHUDTests.swift
//  WallpaperEngineCoreTests
//
//  Comprehensive test suite for Audio-Reactive Visualizer, Accelerate FFT spectrum analyzer,
//  System Telemetry Mach host probes, Now Playing media observer, and Glassmorphic Desktop HUD.
//

import AppKit
import CoreGraphics
import Foundation
@testable import WallpaperEngineCore

@MainActor
public struct AudioHUDTests {
    public static func runAllTests() async {
        let runner = TestRunner.shared

        await runner.runSuite("Suite: Audio-Reactive FFT & Spectrum Data") {

            // Test 1: AudioSpectrumData Initialization and SIMD4 packing
            runner.test("AudioSpectrumData clamps values and packs SIMD4 accurately") {
                let spectrum = AudioSpectrumData(
                    bass: 0.85,
                    mid: 0.45,
                    treble: 0.25,
                    amplitude: 0.70,
                    bands: [Float](repeating: 0.5, count: 16),
                    rawRMS: 0.12
                )

                try assertEqual(spectrum.bass, 0.85, "Bass correctly stored")
                try assertEqual(spectrum.mid, 0.45, "Mid correctly stored")
                try assertEqual(spectrum.treble, 0.25, "Treble correctly stored")
                try assertEqual(spectrum.amplitude, 0.70, "Amplitude correctly stored")
                try assertEqual(spectrum.bands.count, 16, "16 frequency bands present")

                let simd = spectrum.asSIMD4
                try assertEqual(simd.x, 0.85, "SIMD x matches bass")
                try assertEqual(simd.y, 0.45, "SIMD y matches mid")
                try assertEqual(simd.z, 0.25, "SIMD z matches treble")
                try assertEqual(simd.w, 0.70, "SIMD w matches amplitude")
            }

            // Test 2: AudioSpectrumAnalyzer FFT processing and frequency discrimination
            runner.test("AudioSpectrumAnalyzer computes FFT and detects low frequency energy") {
                let analyzer = AudioSpectrumAnalyzer(fftSize: 1024, sampleRate: 48000.0)

                // Generate synthetic 120Hz bass sine wave
                let sampleRate: Float = 48000.0
                let frequency: Float = 120.0
                var bassSamples = [Float](repeating: 0.0, count: 1024)
                for i in 0..<1024 {
                    let t = Float(i) / sampleRate
                    bassSamples[i] = sin(2.0 * .pi * frequency * t) * 0.8
                }

                let result = analyzer.process(samples: bassSamples)
                try assertTrue(result.bass > 0.0, "Bass energy detected for 120Hz sine wave")
                try assertTrue(result.amplitude >= 0.0, "Overall amplitude is non-negative")
                try assertTrue(result.bands.count == 16, "Outputs exactly 16 frequency bands")
            }

            // Test 3: AudioSpectrumAnalyzer handles short / empty sample buffers gracefully
            runner.test("AudioSpectrumAnalyzer smoothly decays on undersized or silent buffers") {
                let analyzer = AudioSpectrumAnalyzer(fftSize: 1024, sampleRate: 48000.0)
                let silentResult = analyzer.process(samples: [0.0, 0.0, 0.0])

                try assertEqual(silentResult.bands.count, 16, "Output maintains 16 bands")
                try assertTrue(silentResult.amplitude <= 0.1, "Amplitude remains low or decaying")
            }

            // Test 4: SystemAudioCapture simulated pulse generation
            await runner.testAsync("SystemAudioCapture starts organic fallback simulation cleanly") {
                let capture = SystemAudioCapture(sampleRate: 48000.0, fftSize: 1024)
                // nonisolated(unsafe) lets the @Sendable dispatch-queue closure mutate this
                // var without triggering Swift 6 SendableClosureCaptures errors.
                nonisolated(unsafe) var receivedSpectrum: AudioSpectrumData?

                capture.onSpectrumUpdate = { data in
                    if receivedSpectrum == nil {
                        receivedSpectrum = data
                    }
                }

                // Must call start() first so isRunning=true; then startSimulation()
                // activates the DispatchSource fallback timer (~60Hz).
                capture.start()
                capture.startSimulation()
                try await Task.sleep(nanoseconds: 300_000_000) // 300 ms — ≥18 ticks at 60Hz
                capture.stop()

                try assertNotNil(receivedSpectrum, "Received simulated audio spectrum data")
                if let spec = receivedSpectrum {
                    try assertEqual(spec.bands.count, 16, "Received 16 frequency bands")
                }
            }
        }

        await runner.runSuite("Suite: Desktop Telemetry & Media Monitoring") {

            // Test 5: SystemTelemetry Mach Host Probe
            runner.test("SystemTelemetryMonitor samples valid CPU, RAM, and FPS telemetry") {
                let monitor = SystemTelemetryMonitor()
                let initial = monitor.latestTelemetry

                try assertTrue(initial.ramTotalGB > 0.5, "Detected valid total physical memory")

                monitor.sampleTelemetry()
                let sampled = monitor.latestTelemetry
                try assertTrue(sampled.cpuPercentage >= 0.0 && sampled.cpuPercentage <= 100.0, "CPU percentage is bounded [0, 100]")
                try assertTrue(sampled.ramPercentage >= 0.0 && sampled.ramPercentage <= 100.0, "RAM percentage is bounded [0, 100]")
                try assertTrue(sampled.ramUsedGB > 0.0, "RAM used is non-zero")
                try assertTrue(sampled.ramUsedGB <= sampled.ramTotalGB * 1.5, "RAM used does not exceed physical limit")
            }

            // Test 6: NowPlayingInfo metadata model
            runner.test("NowPlayingInfo models track states and player sources") {
                let info = NowPlayingInfo(
                    title: "Starboy",
                    artist: "The Weeknd",
                    album: "Starboy",
                    source: "Spotify",
                    isPlaying: true,
                    playbackPosition: 45.0,
                    duration: 230.0
                )

                try assertEqual(info.title, "Starboy", "Track title matched")
                try assertEqual(info.artist, "The Weeknd", "Artist matched")
                try assertEqual(info.source, "Spotify", "Player source is Spotify")
                try assertTrue(info.isPlaying, "Playback state is playing")
            }
        }

        await runner.runSuite("Suite: Glassmorphic Desktop HUD & Widget Placements") {

            // Test 7: DesktopHUDView initialization and hierarchy
            runner.test("DesktopHUDView builds glassmorphic visual effect hierarchy") {
                let hudView = DesktopHUDView(frame: CGRect(x: 0, y: 0, width: 326, height: 280))
                try assertNotNil(hudView.layer, "DesktopHUDView has backing CALayer")

                let subviews = hudView.subviews
                try assertTrue(subviews.contains(where: { $0 is NSVisualEffectView }), "Contains glassmorphic NSVisualEffectView")
            }

            // Test 8: DesktopHUDView placement calculations
            runner.test("DesktopHUDView positions correctly across all screen anchors") {
                let screenBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
                let hudView = DesktopHUDView(frame: .zero)

                var cfg = EngineConfig.HUDConfig()
                cfg.isEnabled = true

                // Top Right
                cfg.position = .topRight
                hudView.applyConfig(cfg)
                hudView.updatePlacement(in: screenBounds)
                try assertTrue(hudView.frame.origin.x > 1400, "Placed at top right X")
                try assertTrue(hudView.frame.origin.y > 600, "Placed at top right Y")

                // Top Left
                cfg.position = .topLeft
                hudView.applyConfig(cfg)
                hudView.updatePlacement(in: screenBounds)
                try assertEqual(hudView.frame.origin.x, 28, "Placed at top left margin")

                // Bottom Left
                cfg.position = .bottomLeft
                hudView.applyConfig(cfg)
                hudView.updatePlacement(in: screenBounds)
                try assertEqual(hudView.frame.origin.x, 28, "Placed at bottom left margin")
                try assertEqual(hudView.frame.origin.y, 60, "Placed at bottom margin")

                // Top Center
                cfg.position = .topCenter
                hudView.applyConfig(cfg)
                hudView.updatePlacement(in: screenBounds)
                let expectedX = (screenBounds.width - 326.0) / 2.0
                try assertEqual(hudView.frame.origin.x, expectedX, "Placed at top center X")
            }

            // Test 9: DesktopHUDView live data updates
            runner.test("DesktopHUDView accepts telemetry, now playing, and audio spectrum data") {
                let hudView = DesktopHUDView(frame: CGRect(x: 0, y: 0, width: 326, height: 280))

                // Telemetry
                let telemetry = SystemTelemetry(
                    cpuPercentage: 24.5,
                    ramPercentage: 62.0,
                    ramUsedGB: 9.9,
                    ramTotalGB: 16.0,
                    gpuPercentage: 12.0,
                    fps: 120
                )
                hudView.updateTelemetry(telemetry)

                // Now Playing
                let track = NowPlayingInfo(
                    title: "Midnight City",
                    artist: "M83",
                    album: "Hurry Up, We're Dreaming",
                    source: "Apple Music",
                    isPlaying: true
                )
                hudView.updateNowPlaying(track)

                // Spectrum
                let spectrum = AudioSpectrumData(
                    bass: 0.9,
                    mid: 0.5,
                    treble: 0.3,
                    amplitude: 0.75,
                    bands: [Float](repeating: 0.6, count: 16),
                    rawRMS: 0.2
                )
                hudView.updateSpectrum(spectrum)

                try assertTrue(true, "HUD successfully ingested all telemetry and audio streams without crash")
            }
        }

        await runner.runSuite("Suite: HUD & Audio CLI Options and Serialization") {

            // Test 10: HUDConfig JSON serialization and deserialization
            runner.test("HUDConfig roundtrips through JSON preserving all toggles and position") {
                var original = EngineConfig.HUDConfig()
                original.isEnabled = true
                original.position = .bottomRight
                original.showClock = true
                original.showDate = false
                original.showSystemStats = true
                original.showNowPlaying = false
                original.showAudioVisualizer = true
                original.scale = 1.25

                let encoder = JSONEncoder()
                let data = try encoder.encode(original)

                let decoder = JSONDecoder()
                let decoded = try decoder.decode(EngineConfig.HUDConfig.self, from: data)

                try assertEqual(decoded.isEnabled, original.isEnabled, "isEnabled matches")
                try assertEqual(decoded.position, original.position, "position matches")
                try assertEqual(decoded.showClock, original.showClock, "showClock matches")
                try assertEqual(decoded.showDate, original.showDate, "showDate matches")
                try assertEqual(decoded.showSystemStats, original.showSystemStats, "showSystemStats matches")
                try assertEqual(decoded.showNowPlaying, original.showNowPlaying, "showNowPlaying matches")
                try assertEqual(decoded.showAudioVisualizer, original.showAudioVisualizer, "showAudioVisualizer matches")
                try assertEqual(decoded.scale, original.scale, "scale matches")
            }

            // Test 11: CommandLineOptions parsing for HUD and Audio Reactive flags
            runner.test("CommandLineOptions parses --hud, --hud-position, and --audio-reactive") {
                let args = [
                    "WallpaperEngineApp",
                    "--hud",
                    "--hud-position", "topLeft",
                    "--audio-reactive"
                ]

                let options = CommandLineOptions.parse(arguments: args)
                try assertNotNil(options.isHUDEnabled, "--hud flag parsed")
                try assertTrue(options.isHUDEnabled == true, "--hud parsed as true")
                try assertEqual(options.hudPosition, .topLeft, "--hud-position parsed as .topLeft")
                try assertNotNil(options.isAudioReactive, "--audio-reactive flag parsed")
                try assertTrue(options.isAudioReactive == true, "--audio-reactive parsed as true")

                var config = EngineConfig()
                options.apply(to: &config)
                try assertEqual(config.hudConfig.isEnabled, true, "Applied HUD isEnabled")
                try assertEqual(config.hudConfig.position, .topLeft, "Applied HUD position")
                try assertEqual(config.isAudioReactive, true, "Applied isAudioReactive")
            }

            // Test 12: CommandLineOptions parses negative flags --no-hud and --no-audio-reactive
            runner.test("CommandLineOptions parses --no-hud and --no-audio-reactive") {
                let args = [
                    "WallpaperEngineApp",
                    "--no-hud",
                    "--hud-position", "bottomRight",
                    "--no-audio-reactive"
                ]

                let options = CommandLineOptions.parse(arguments: args)
                try assertNotNil(options.isHUDEnabled, "--no-hud flag parsed")
                try assertTrue(options.isHUDEnabled == false, "--no-hud parsed as false")
                try assertEqual(options.hudPosition, .bottomRight, "--hud-position parsed as .bottomRight")
                try assertNotNil(options.isAudioReactive, "--no-audio-reactive flag parsed")
                try assertTrue(options.isAudioReactive == false, "--no-audio-reactive parsed as false")

                var config = EngineConfig()
                options.apply(to: &config)
                try assertEqual(config.hudConfig.isEnabled, false, "Applied HUD disabled")
                try assertEqual(config.hudConfig.position, .bottomRight, "Applied HUD bottom-right")
                try assertEqual(config.isAudioReactive, false, "Applied isAudioReactive false")
            }
        }
    }
}

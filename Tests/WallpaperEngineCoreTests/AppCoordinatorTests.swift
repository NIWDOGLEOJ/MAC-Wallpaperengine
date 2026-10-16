//
//  AppCoordinatorTests.swift
//  WallpaperEngineCoreTests
//
//  Comprehensive test suite for AppCoordinator lifecycle, state synchronization, and orchestration.
//

import AppKit
import CoreGraphics
import Foundation
@testable import WallpaperEngineCore

@MainActor
public struct AppCoordinatorTests {
    public static func runAllTests() async {
        let runner = TestRunner.shared

        await runner.runSuite("Suite: AppCoordinator Lifecycle & Orchestration") {

            // Test 1: Lifecycle Startup & Teardown
            runner.test("start() coordinates all subsystems; stop() halts cleanly") {
                let storage = MockConfigStorage()
                let windowManager = DesktopWindowManager(screenManager: MockScreenManager())
                let videoEngine = VideoEngine(windowManager: nil)
                let powerObserver = PowerObserver(provider: MockPowerSourceProvider())
                let sleepLockObserver = SleepLockObserver(sessionProvider: MockSessionStateProvider())
                let occlusionManager = OcclusionManager()
                let provider = MockStatusItemProvider()
                let menuBar = MenuBarController(isHeadless: false, statusItemProvider: provider)

                let coordinator = AppCoordinator(
                    configStorage: storage,
                    windowManager: windowManager,
                    videoEngine: videoEngine,
                    powerObserver: powerObserver,
                    sleepLockObserver: sleepLockObserver,
                    occlusionManager: occlusionManager,
                    menuBarController: menuBar
                )

                try assertFalse(coordinator.isRunning, "Initially not running")
                coordinator.start()
                try assertTrue(coordinator.isRunning, "Running after start")
                try assertTrue(windowManager.isRunning, "WindowManager running")
                try assertTrue(powerObserver.isObserving, "PowerObserver observing")
                try assertTrue(sleepLockObserver.isRunning, "SleepLockObserver running")
                try assertTrue(menuBar.isRunning, "MenuBarController running")

                coordinator.stop()
                try assertFalse(coordinator.isRunning, "Not running after stop")
                try assertFalse(powerObserver.isObserving, "PowerObserver halted")
                try assertFalse(sleepLockObserver.isRunning, "SleepLockObserver halted")
                try assertFalse(menuBar.isRunning, "MenuBarController halted")
            }

            // Test 2: CLI Options Merged into Active Config on Startup
            runner.test("CLI options override saved configuration on coordinator startup") {
                var savedConfig = EngineConfig()
                savedConfig.targetFrameRate = 60
                savedConfig.pauseOnBattery = false
                let storage = MockConfigStorage(initialConfig: savedConfig)

                let cli = CommandLineOptions(
                    videoPath: "/wallpapers/cyberpunk.mp4",
                    targetFPS: 144,
                    throttledFPS: 30,
                    pauseOnBattery: true
                )

                let coordinator = AppCoordinator(
                    configStorage: storage,
                    cliOptions: cli
                )

                try assertEqual(coordinator.config.targetFrameRate, 144, "CLI targetFrameRate applied")
                try assertEqual(coordinator.config.throttledFrameRate, 30, "CLI throttledFrameRate applied")
                try assertTrue(coordinator.config.pauseOnBattery, "CLI pauseOnBattery applied")
                try assertEqual(coordinator.config.defaultAssetPath, "/wallpapers/cyberpunk.mp4", "CLI defaultAssetPath applied")
            }

            // Test 3: Multi-Display Window Addition and Removal Coordination
            runner.test("DesktopWindowManager delegate calls add and remove display pipelines") {
                let storage = MockConfigStorage()
                let videoEngine = VideoEngine(windowManager: nil)
                let occlusionManager = OcclusionManager()
                let coordinator = AppCoordinator(
                    configStorage: storage,
                    videoEngine: videoEngine,
                    occlusionManager: occlusionManager
                )
                coordinator.start()

                // Add Display 1
                let screen1 = ScreenDescriptor(displayID: 1, name: "Internal", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                let window1 = MockDesktopWindow(frame: screen1.frame, displayID: 1)
                coordinator.desktopWindowManager(coordinator.windowManager, didAddWindow: window1, for: 1)

                try assertTrue(videoEngine.activeDisplays.contains(1), "Display 1 registered in video engine")
                try assertTrue(occlusionManager.isDisplayVisible(1), "Display 1 registered in occlusion manager")
                try assertNotNil(coordinator.lastDecisions[1], "Decision evaluated for Display 1")

                // Add Display 2
                let screen2 = ScreenDescriptor(displayID: 2, name: "External", frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
                let window2 = MockDesktopWindow(frame: screen2.frame, displayID: 2)
                coordinator.desktopWindowManager(coordinator.windowManager, didAddWindow: window2, for: 2)

                try assertTrue(videoEngine.activeDisplays.contains(2), "Display 2 registered in video engine")
                try assertNotNil(coordinator.lastDecisions[2], "Decision evaluated for Display 2")

                // Remove Display 1
                coordinator.desktopWindowManager(coordinator.windowManager, didRemoveWindowFor: 1)
                try assertFalse(videoEngine.activeDisplays.contains(1), "Display 1 detached from video engine")
                try assertNil(coordinator.lastDecisions[1], "Decision purged for Display 1")
                try assertTrue(videoEngine.activeDisplays.contains(2), "Display 2 still active")

                coordinator.stop()
            }

            // Test 4: Power State Change Dispatches Throttling / Pause
            runner.test("Power state transitions evaluate and dispatch decisions to VideoEngine") {
                var config = EngineConfig()
                config.pauseOnBattery = false
                config.throttleOnBattery = true
                config.throttledFrameRate = 30
                let storage = MockConfigStorage(initialConfig: config)
                let videoEngine = VideoEngine(windowManager: nil)

                let coordinator = AppCoordinator(
                    configStorage: storage,
                    videoEngine: videoEngine
                )
                coordinator.start()

                // Add Display 1
                let window1 = MockDesktopWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                coordinator.desktopWindowManager(coordinator.windowManager, didAddWindow: window1, for: 1)

                // Transition to Battery Power
                coordinator.powerStateDidChange(MockPowerEventGenerator.battery())

                let decision = coordinator.lastDecisions[1]
                try assertEqual(decision, .throttle(fps: 30, reasons: [.onBattery]), "Battery power triggers throttle decision")

                // Transition back to AC Power
                coordinator.powerStateDidChange(MockPowerEventGenerator.ac())
                let acDecision = coordinator.lastDecisions[1]
                try assertEqual(acDecision, .play(fps: 60), "AC power restores .play(60)")

                coordinator.stop()
            }

            // Test 5: Sleep & Lock State Transitions Pause Video
            runner.test("Screen lock and system sleep transitions pause playback") {
                let storage = MockConfigStorage()
                let videoEngine = VideoEngine(windowManager: nil)

                let coordinator = AppCoordinator(
                    configStorage: storage,
                    videoEngine: videoEngine
                )
                coordinator.start()

                let window1 = MockDesktopWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                coordinator.desktopWindowManager(coordinator.windowManager, didAddWindow: window1, for: 1)

                // Simulate screen lock
                coordinator.sleepLockStateDidChange(MockSleepLockEventGenerator.locked())
                try assertEqual(coordinator.lastDecisions[1], .pause(reasons: [.screenLocked]), "Screen lock pauses player")

                // Simulate screen unlock
                coordinator.sleepLockStateDidChange(MockSleepLockEventGenerator.normalActive())
                try assertEqual(coordinator.lastDecisions[1], .play(fps: 60), "Screen unlock resumes player")

                // Simulate display sleep
                coordinator.sleepLockStateDidChange(MockSleepLockEventGenerator.screensSleeping())
                try assertEqual(coordinator.lastDecisions[1], .pause(reasons: [.screensSleeping]), "Display sleep pauses player")

                coordinator.stop()
            }

            // Test 6: Granular Per-Display Occlusion Independence
            runner.test("Per-display occlusion pauses occluded screen while visible screen continues playing") {
                let storage = MockConfigStorage()
                let videoEngine = VideoEngine(windowManager: nil)
                let occlusionManager = OcclusionManager()

                let coordinator = AppCoordinator(
                    configStorage: storage,
                    videoEngine: videoEngine,
                    occlusionManager: occlusionManager
                )
                coordinator.start()

                let w1 = MockDesktopWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                let w2 = MockDesktopWindow(frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), displayID: 2)
                coordinator.desktopWindowManager(coordinator.windowManager, didAddWindow: w1, for: 1)
                coordinator.desktopWindowManager(coordinator.windowManager, didAddWindow: w2, for: 2)

                // Occlude Display 2 only
                occlusionManager.setDisplayVisibility(2, isVisible: false)
                coordinator.occlusionDidChange(for: 2, isVisible: false)

                try assertEqual(coordinator.lastDecisions[1], .play(fps: 60), "Display 1 remains playing")
                try assertEqual(coordinator.lastDecisions[2], .pause(reasons: [.displayOccluded]), "Display 2 paused for occlusion")

                // Un-occlude Display 2
                occlusionManager.setDisplayVisibility(2, isVisible: true)
                coordinator.occlusionDidChange(for: 2, isVisible: true)

                try assertEqual(coordinator.lastDecisions[2], .play(fps: 60), "Display 2 resumes playing")

                coordinator.stop()
            }

            // Test 7: Manual Play/Pause Toggle
            runner.test("togglePlayback() toggles isPaused and updates players") {
                let storage = MockConfigStorage()
                let coordinator = AppCoordinator(configStorage: storage)
                coordinator.start()

                let w1 = MockDesktopWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                coordinator.desktopWindowManager(coordinator.windowManager, didAddWindow: w1, for: 1)

                try assertFalse(coordinator.config.isPaused, "Initially unpaused")
                coordinator.togglePlayback()
                try assertTrue(coordinator.config.isPaused, "Paused after toggle")
                try assertEqual(coordinator.lastDecisions[1], .pause(reasons: [.userRequested]), "Decision is userRequested pause")

                coordinator.togglePlayback()
                try assertFalse(coordinator.config.isPaused, "Unpaused after second toggle")
                try assertEqual(coordinator.lastDecisions[1], .play(fps: 60), "Decision is play")

                coordinator.stop()
            }

            // Test 8: Immediate Flush on Stop
            runner.test("flushConfigToDisk() and stop() immediately commit in-memory config to storage") {
                let storage = MockConfigStorage()
                let coordinator = AppCoordinator(configStorage: storage)
                coordinator.start()

                coordinator.updateConfig { cfg in
                    cfg.targetFrameRate = 120
                    cfg.pauseOnBattery = true
                }

                // Call flushConfigToDisk
                coordinator.flushConfigToDisk()
                try assertEqual(storage.saveCount, 1, "Storage save called on flush")
                try assertEqual(storage.storedConfig?.targetFrameRate, 120, "Target frame rate stored")
                try assertEqual(storage.storedConfig?.pauseOnBattery, true, "pauseOnBattery stored")

                coordinator.stop()
            }

            // Test 9: Mutual Exclusion Enforcement between Shaders, Videos, and Photos
            await runner.testAsync("Mutual exclusion: setting video clears shader and tears down shader view; setting shader clears video") {
                let storage = MockConfigStorage()
                var cfg = EngineConfig.default
                cfg.useCPUOnlyEngine = false
                let videoEngine = VideoEngine(windowManager: nil)
                let coordinator = AppCoordinator(config: cfg, configStorage: storage, videoEngine: videoEngine)
                coordinator.start()

                let window1 = MockDesktopWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                coordinator.desktopWindowManager(coordinator.windowManager, didAddWindow: window1, for: 1)

                // 1. Set shader
                coordinator.setShader(preset: .aurora, for: 1)
                try assertEqual(coordinator.config.displayConfigurations["1"]?.shaderName, "aurora", "Display 1 shader set to aurora")
                try assertNil(coordinator.config.displayConfigurations["1"]?.assetPath, "Display 1 assetPath is nil")
                try assertNotNil(coordinator.shaderViews[1], "Display 1 has shader view attached")

                // 2. Set video
                let dummyVideoURL = try await SyntheticVideoGenerator.createValidVideoFile()
                defer { try? FileManager.default.removeItem(at: dummyVideoURL) }
                try await coordinator.setVideo(url: dummyVideoURL, for: 1)

                try assertEqual(coordinator.config.displayConfigurations["1"]?.assetPath, dummyVideoURL.path, "Display 1 assetPath set to video")
                try assertNil(coordinator.config.displayConfigurations["1"]?.shaderName, "Display 1 shaderName cleared cleanly")
                try assertNil(coordinator.shaderViews[1], "Display 1 shader view cleanly torn down")

                // 3. Set another shader
                coordinator.setShader(preset: .cyberpunkGrid, for: 1)
                try assertEqual(coordinator.config.displayConfigurations["1"]?.shaderName, "cyberpunkGrid", "Shader switched to cyberpunkGrid")
                try assertNil(coordinator.config.displayConfigurations["1"]?.assetPath, "assetPath cleared cleanly on shader set")
                try assertNotNil(coordinator.shaderViews[1], "Shader view re-attached")

                coordinator.stop()
            }

            // Test 11: CPU-Only Engine Mode (0% GPU) and Seamless Dynamic Switching
            await runner.testAsync("CPU-Only Engine mode operates with CPULiveWallpaperView and toggles seamlessly") {
                let storage = MockConfigStorage()
                var cfg = EngineConfig.default
                cfg.useCPUOnlyEngine = true
                let videoEngine = VideoEngine(windowManager: nil)
                let coordinator = AppCoordinator(config: cfg, configStorage: storage, videoEngine: videoEngine)
                coordinator.start()

                let window1 = MockDesktopWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                coordinator.desktopWindowManager(coordinator.windowManager, didAddWindow: window1, for: 1)

                // 1. In CPU-only mode, setting a shader preset attaches CPULiveWallpaperView (strictly 0% GPU)
                coordinator.setShader(preset: .aurora, for: 1)
                try assertNotNil(coordinator.cpuWallpaperViews[1], "Display 1 has CPULiveWallpaperView attached")
                try assertNil(coordinator.shaderViews[1], "Display 1 has NO Metal shaderView attached (0% GPU)")
                try assertEqual(coordinator.telemetryMonitor.isCPUOnlyMode, true, "Telemetry monitor is in CPU-only mode (reports 0% GPU)")

                // 2. Switch to Metal GPU mode
                coordinator.setCPUOnlyEngine(false)
                try assertNil(coordinator.cpuWallpaperViews[1], "CPULiveWallpaperView torn down upon switching to GPU mode")
                try assertNotNil(coordinator.shaderViews[1], "Metal ShaderWallpaperView attached upon switching to GPU mode")
                try assertEqual(coordinator.telemetryMonitor.isCPUOnlyMode, false, "Telemetry monitor is in GPU mode")

                // 3. Switch back to CPU-only mode
                coordinator.setCPUOnlyEngine(true)
                try assertNotNil(coordinator.cpuWallpaperViews[1], "CPULiveWallpaperView re-attached upon switching to CPU-only mode")
                try assertNil(coordinator.shaderViews[1], "Metal ShaderWallpaperView torn down (0% GPU guaranteed)")
                try assertEqual(coordinator.telemetryMonitor.isCPUOnlyMode, true, "Telemetry monitor returns to 0% GPU")

                coordinator.stop()
            }

            // Test 10: AppState Active Wallpaper Detection & Discovery
            runner.test("AppState resolves active wallpaper type and discovers local videos") {
                var config = EngineConfig.default
                config.displayConfigurations["1"] = DisplayConfig(assetPath: "/wallpapers/samurai.mp4")
                let state = AppState(config: config)

                let active = state.activeWallpaper(for: 1)
                try assertEqual(active, .video(path: "/wallpapers/samurai.mp4"), "Display 1 active wallpaper detected as video")

                // Test shader detection
                config.displayConfigurations["1"] = DisplayConfig(shaderName: "starfield")
                state.config = config
                let activeShader = state.activeWallpaper(for: 1)
                try assertEqual(activeShader, .shader(.starfield), "Display 1 active wallpaper detected as starfield shader")
            }

            // Test 11: Coordinator setStaticImage Attachment & Mutual Exclusion
            await runner.testAsync("setStaticImage attaches StaticWallpaperView and enforces mutual exclusivity") {

                let storage = MockConfigStorage()
                let windowManager = DesktopWindowManager(screenManager: MockScreenManager())
                let videoEngine = VideoEngine(windowManager: nil)
                let coordinator = AppCoordinator(
                    configStorage: storage,
                    windowManager: windowManager,
                    videoEngine: videoEngine
                )
                coordinator.start()

                let window = MockDesktopWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                coordinator.desktopWindowManager(coordinator.windowManager, didAddWindow: window, for: 1)

                let imgURL = URL(fileURLWithPath: "/tmp/static_test.png")
                try await coordinator.setStaticImage(url: imgURL, for: 1, scalingMode: .aspectFill)

                try assertNotNil(coordinator.staticWallpaperViews[1], "StaticWallpaperView attached to display 1")
                try assertNil(coordinator.shaderViews[1], "Shader view nil")
                try assertNil(coordinator.cpuWallpaperViews[1], "CPU view nil")
                try assertNil(coordinator.parallaxViews[1], "Parallax view nil")
                try assertNil(coordinator.webWallpaperViews[1], "Web view nil")
                try assertNil(coordinator.particleViews[1], "Particle view nil")

                coordinator.stop()
            }

            // Test 12: Coordinator setWebWallpaper Attachment
            runner.test("setWebWallpaper attaches WebWallpaperView and records active wallpaper") {
                let storage = MockConfigStorage()
                let windowManager = DesktopWindowManager(screenManager: MockScreenManager())
                let videoEngine = VideoEngine(windowManager: nil)
                let coordinator = AppCoordinator(
                    configStorage: storage,
                    windowManager: windowManager,
                    videoEngine: videoEngine
                )
                coordinator.start()

                let window = MockDesktopWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                coordinator.desktopWindowManager(coordinator.windowManager, didAddWindow: window, for: 1)

                let webURL = URL(fileURLWithPath: "/tmp/wallpaper.html")
                coordinator.setWebWallpaper(url: webURL, for: 1)

                try assertNotNil(coordinator.webWallpaperViews[1], "WebWallpaperView attached to display 1")
                try assertNil(coordinator.staticWallpaperViews[1], "Static view nil")
                try assertNil(coordinator.shaderViews[1], "Shader view nil")

                coordinator.stop()
            }

            // Test 13: Coordinator setParticles Attachment
            runner.test("setParticles attaches InteractiveParticleWallpaperView") {
                let storage = MockConfigStorage()
                let windowManager = DesktopWindowManager(screenManager: MockScreenManager())
                let videoEngine = VideoEngine(windowManager: nil)
                let coordinator = AppCoordinator(
                    configStorage: storage,
                    windowManager: windowManager,
                    videoEngine: videoEngine
                )
                coordinator.start()

                let window = MockDesktopWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                coordinator.desktopWindowManager(coordinator.windowManager, didAddWindow: window, for: 1)

                coordinator.setParticles(scene: .rain, for: 1)

                try assertNotNil(coordinator.particleViews[1], "InteractiveParticleWallpaperView attached to display 1")
                try assertEqual(coordinator.particleViews[1]?.sceneType, .rain, "Particle scene type is rain")
                try assertNil(coordinator.staticWallpaperViews[1], "Static view nil")

                coordinator.stop()
            }

            // Test 14: Coordinator Multi-Monitor Spanning
            runner.test("setSpanned updates config and sets normalized slices across static views") {
                let storage = MockConfigStorage()
                let windowManager = DesktopWindowManager(screenManager: MockScreenManager())
                let videoEngine = VideoEngine(windowManager: nil)
                let coordinator = AppCoordinator(
                    configStorage: storage,
                    windowManager: windowManager,
                    videoEngine: videoEngine
                )
                coordinator.start()

                coordinator.setSpanned(true)
                try assertTrue(coordinator.config.isSpanned, "isSpanned is true in config")

                coordinator.setSpanned(false)
                try assertFalse(coordinator.config.isSpanned, "isSpanned is false in config")

                coordinator.stop()
            }

            // Test 15: MemoryPressureDelegate Clears Cache and Reconciles
            runner.test("MemoryPressureDelegate clears caches on warning and critical levels") {
                let storage = MockConfigStorage()
                let windowManager = DesktopWindowManager(screenManager: MockScreenManager())
                let videoEngine = VideoEngine(windowManager: nil)
                let coordinator = AppCoordinator(
                    configStorage: storage,
                    windowManager: windowManager,
                    videoEngine: videoEngine
                )
                coordinator.start()

                coordinator.memoryPressureDidChange(to: .warning)
                try assertTrue(coordinator.isRunning, "Coordinator continues running after memory pressure warning")

                coordinator.memoryPressureDidChange(to: .critical)
                try assertTrue(coordinator.isRunning, "Coordinator continues running after memory pressure critical")

                coordinator.stop()
            }

            // Test 16: Dynamic Multi-Monitor Topology Change during Spanning
            await runner.testAsync("Dynamic screen topology changes while spanned recompute contentsRect across monitors") {
                let storage = MockConfigStorage()
                let screen1 = ScreenDescriptor(displayID: 1, name: "Screen 1", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scaleFactor: 2.0, isMain: true, isBuiltin: true)
                let screen2 = ScreenDescriptor(displayID: 2, name: "Screen 2", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), scaleFactor: 2.0, isMain: false, isBuiltin: false)
                let mockScreenMgr = MockScreenManager(screens: [screen1, screen2])
                let windowManager = DesktopWindowManager(screenManager: mockScreenMgr)
                let videoEngine = VideoEngine(windowManager: nil)
                let coordinator = AppCoordinator(
                    configStorage: storage,
                    windowManager: windowManager,
                    videoEngine: videoEngine
                )
                coordinator.start()

                let window1 = MockDesktopWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                let window2 = MockDesktopWindow(frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), displayID: 2)
                coordinator.desktopWindowManager(coordinator.windowManager, didAddWindow: window1, for: 1)
                coordinator.desktopWindowManager(coordinator.windowManager, didAddWindow: window2, for: 2)

                // Attach static wallpaper to display 1 and display 2
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_span_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let imgURL = tempDir.appendingPathComponent("span_test.png")
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                if let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256, space: colorSpace, bitmapInfo: bitmapInfo.rawValue),
                   let image = context.makeImage(),
                   let destination = CGImageDestinationCreateWithURL(imgURL as CFURL, "public.png" as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, image, nil)
                    CGImageDestinationFinalize(destination)
                }

                try await coordinator.setStaticImage(url: imgURL, for: 1, scalingMode: .aspectFill)
                try await coordinator.setStaticImage(url: imgURL, for: 2, scalingMode: .aspectFill)

                // Enable spanning
                coordinator.setSpanned(true)

                // On dual side-by-side (1920+1920 = 3840 wide), display 1 occupies [0, 0, 0.5, 1], display 2 occupies [0.5, 0, 0.5, 1]
                let rect1Initial = coordinator.staticWallpaperViews[1]?.contentsRect
                let rect2Initial = coordinator.staticWallpaperViews[2]?.contentsRect
                try assertEqual(rect1Initial?.origin.x, 0.0, "Screen 1 starts at normalized x = 0.0")
                try assertEqual(rect1Initial?.width, 0.5, "Screen 1 has normalized width 0.5")
                try assertEqual(rect2Initial?.origin.x, 0.5, "Screen 2 starts at normalized x = 0.5")

                // Now simulate screen 3 addition: Screen 3 at x: 3840, width: 1920
                let screen3 = ScreenDescriptor(displayID: 3, name: "Screen 3", frame: CGRect(x: 3840, y: 0, width: 1920, height: 1080), scaleFactor: 2.0, isMain: false, isBuiltin: false)
                mockScreenMgr.activeScreens = [screen1, screen2, screen3]
                coordinator.displayConfigurationDidChange(added: [3], removed: [], updated: [])

                // Now across 3 equal monitors, width is 1/3 ~ 0.3333
                let rect1Updated = coordinator.staticWallpaperViews[1]?.contentsRect
                try assertTrue(abs((rect1Updated?.width ?? 0) - (1.0 / 3.0)) < 0.01, "Screen 1 normalized width dynamically updated to ~0.333")

                coordinator.stop()
            }

            // Test 17: applyProfile propagates rules to performanceRulesManager
            runner.test("applyProfile propagates pauseOnFullscreen and pauseOnGame to performanceRulesManager") {
                let storage = MockConfigStorage()
                let windowManager = DesktopWindowManager(screenManager: MockScreenManager())
                let videoEngine = VideoEngine(windowManager: nil)
                let coordinator = AppCoordinator(
                    configStorage: storage,
                    windowManager: windowManager,
                    videoEngine: videoEngine
                )
                coordinator.start()

                var profile = EngineProfile(
                    name: "Gaming Mode",
                    type: .custom,
                    targetFrameRate: 30,
                    pauseOnBattery: true,
                    pauseOnFullscreen: true,
                    pauseOnGame: true
                )

                coordinator.applyProfile(profile)

                try assertTrue(coordinator.performanceRulesManager.pauseOnFullscreen, "pauseOnFullscreen propagated")
                try assertTrue(coordinator.performanceRulesManager.pauseOnGame, "pauseOnGame propagated")

                profile.pauseOnFullscreen = false
                profile.pauseOnGame = false
                coordinator.applyProfile(profile)

                try assertFalse(coordinator.performanceRulesManager.pauseOnFullscreen, "pauseOnFullscreen turned off")
                try assertFalse(coordinator.performanceRulesManager.pauseOnGame, "pauseOnGame turned off")

                coordinator.stop()
            }

            // Test 18: nowPlayingMonitor.isPollingEnabled pauses when displays are paused
            runner.test("nowPlayingMonitor.isPollingEnabled automatically disables when all displays are paused") {
                let storage = MockConfigStorage()
                var cfg = EngineConfig.default
                cfg.hudConfig.isEnabled = true
                cfg.hudConfig.showNowPlaying = true
                let coordinator = AppCoordinator(
                    config: cfg,
                    configStorage: storage
                )
                coordinator.start()

                let window = MockDesktopWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 1)
                coordinator.desktopWindowManager(coordinator.windowManager, didAddWindow: window, for: 1)

                // Initially active
                try assertTrue(coordinator.nowPlayingMonitor.isPollingEnabled, "Now playing polling initially enabled")

                // Pause playback globally
                coordinator.pause()
                try assertFalse(coordinator.nowPlayingMonitor.isPollingEnabled, "Now playing polling disabled when paused")

                // Resume playback globally
                coordinator.resume()
                try assertTrue(coordinator.nowPlayingMonitor.isPollingEnabled, "Now playing polling resumed when playback resumes")

                coordinator.stop()
            }
        }
    }
}


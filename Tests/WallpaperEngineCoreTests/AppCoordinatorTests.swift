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
        }
    }
}

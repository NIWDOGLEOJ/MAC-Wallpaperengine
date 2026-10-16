//
//  main.swift
//  WallpaperEngineCoreTests
//
//  Executable Test Target Entrypoint for Wallpaper Engine Core Unit & Integration Tests.
//

import AppKit
import Foundation

print("╔════════════════════════════════════════════════════════════════════╗")
print("║   Wallpaper Engine Core: Milestone 1, 2 & 3 Verification Suite     ║")
print("║   Environment: Swift 6 Strict Concurrency / macOS 13+ SDK          ║")
print("╚════════════════════════════════════════════════════════════════════╝")

// --- Milestone 1 Suites ---
await WindowHierarchyTests.runAllTests()
await ScreenManagerTests.runAllTests()
await ReconciliationStressTests.runAllTests()

// --- Milestone 2 Suites ---
await VideoEngineTests.runAllTests()
await StallWatchdogTests.runAllTests()

// --- Milestone 3 Suites ---
await PowerObserverTests.runAllTests()
await SleepLockObserverTests.runAllTests()
await OcclusionManagerTests.runAllTests()
await StateEvaluatorTests.runAllTests()
await M3PowerAndStateChallengerTests.runAllTests()
await M3SleepLockAndOcclusionChallengerTests.runAllTests()

// --- Milestone 4 Suites ---
await CommandLineOptionsTests.runAllTests()
await ConfigPersistenceTests.runAllTests()
await MenuBarControllerTests.runAllTests()
await AppCoordinatorTests.runAllTests()

// --- AI 3D Parallax Suites ---
await ParallaxTests.runAllTests()

// --- Real-Time Metal Procedural Shader Suites ---
await ShaderTests.runAllTests()

// --- Audio-Reactive Visualizer & Desktop HUD Suites ---
await AudioHUDTests.runAllTests()

// --- Dynamic Wallpaper-Aware Theming Suite ---
await ThemeEngineTests.runAllTests()

// --- Native macOS Application UI & Studio Suites ---
await AppUITests.runAllTests()

// --- Static Wallpaper & Zero-Work CALayer Scanout Suites ---
await StaticWallpaperTests.runAllTests()

// --- Performance Rules & Advanced State Evaluator Suites ---
await PerformanceRulesTests.runAllTests()

// --- Wallpaper Library & Playlist Engine Suites ---
await LibraryAndPlaylistTests.runAllTests()

// --- Web Wallpaper & Interactive Particle Engine Suites ---
await WebAndParticleTests.runAllTests()

// --- Performance Profiles, Editor & Community Packaging Suites ---
await ProfileAndPackageTests.runAllTests()

// --- MotionBGs Online Discover & Integration Suites ---
await MotionBGsDiscoverTests.runAllTests()

// Conclude and return POSIX exit code (0 on success, 1 on failure)
let exitCode = TestRunner.shared.printSummary()
exit(exitCode)


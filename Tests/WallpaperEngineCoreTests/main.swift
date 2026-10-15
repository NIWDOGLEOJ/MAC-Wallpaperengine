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

// Conclude and return POSIX exit code (0 on success, 1 on failure)
let exitCode = TestRunner.shared.printSummary()
exit(exitCode)

//
//  CommandLineOptionsTests.swift
//  WallpaperEngineCoreTests
//
//  Comprehensive test suite for CLI options parsing, syntax styles, and config application.
//

import CoreGraphics
import Foundation
@testable import WallpaperEngineCore

@MainActor
public struct CommandLineOptionsTests {
    public static func runAllTests() async {
        let runner = TestRunner.shared

        await runner.runSuite("Suite: Command Line Options Parsing & Mapping") {

            // Test 1: Empty Arguments
            runner.test("Empty arguments returns clean default options") {
                let opts = CommandLineOptions.parse(arguments: [])
                try assertNil(opts.videoPath, "videoPath should be nil")
                try assertNil(opts.targetDisplayID, "targetDisplayID should be nil")
                try assertNil(opts.targetFPS, "targetFPS should be nil")
                try assertNil(opts.throttledFPS, "throttledFPS should be nil")
                try assertFalse(opts.isHeadless, "isHeadless should be false")
                try assertFalse(opts.isBenchmark, "isBenchmark should be false")
                try assertFalse(opts.pauseOnBattery, "pauseOnBattery should be false")
                try assertFalse(opts.isHelpRequested, "isHelpRequested should be false")
                try assertFalse(opts.isVersionRequested, "isVersionRequested should be false")
                try assertFalse(opts.dumpConfig, "dumpConfig should be false")
                try assertEqual(opts.unknownOptions.count, 0, "No unknown options")
            }

            // Test 2: Standard Space-Separated Flags
            runner.test("Space-separated flags parse all nominal values") {
                let args = [
                    "wallpaper_app",
                    "--video", "/Users/test/wallpaper.mp4",
                    "--display", "101",
                    "--fps", "120",
                    "--throttled-fps", "24",
                    "--config", "/tmp/custom_config.json",
                    "--headless",
                    "--benchmark",
                    "--pause-on-battery"
                ]
                let opts = CommandLineOptions.parse(arguments: args)
                try assertEqual(opts.videoPath, "/Users/test/wallpaper.mp4", "videoPath parsed")
                try assertEqual(opts.targetDisplayID, 101, "targetDisplayID parsed")
                try assertEqual(opts.targetFPS, 120, "targetFPS parsed")
                try assertEqual(opts.throttledFPS, 24, "throttledFPS parsed")
                try assertEqual(opts.configPath, "/tmp/custom_config.json", "configPath parsed")
                try assertTrue(opts.isHeadless, "isHeadless true")
                try assertTrue(opts.isBenchmark, "isBenchmark true")
                try assertTrue(opts.pauseOnBattery, "pauseOnBattery true")
            }

            // Test 3: Inline Equal Syntax
            runner.test("Inline equal syntax parses flags accurately") {
                let args = [
                    "--video=/Library/wallpapers/sky.mov",
                    "--display=2",
                    "--fps=60",
                    "--throttled-fps=30",
                    "--config=/etc/wallpaper.json"
                ]
                let opts = CommandLineOptions.parse(arguments: args)
                try assertEqual(opts.videoPath, "/Library/wallpapers/sky.mov", "videoPath parsed")
                try assertEqual(opts.targetDisplayID, 2, "targetDisplayID parsed")
                try assertEqual(opts.targetFPS, 60, "targetFPS parsed")
                try assertEqual(opts.throttledFPS, 30, "throttledFPS parsed")
                try assertEqual(opts.configPath, "/etc/wallpaper.json", "configPath parsed")
            }

            // Test 4: Mixed Syntax
            runner.test("Mixed equal and space syntax parses without collision") {
                let args = [
                    "--video=/path/a.mp4",
                    "--display", "5",
                    "--fps=90",
                    "--throttled-fps", "15"
                ]
                let opts = CommandLineOptions.parse(arguments: args)
                try assertEqual(opts.videoPath, "/path/a.mp4", "videoPath parsed")
                try assertEqual(opts.targetDisplayID, 5, "targetDisplayID parsed")
                try assertEqual(opts.targetFPS, 90, "targetFPS parsed")
                try assertEqual(opts.throttledFPS, 15, "throttledFPS parsed")
            }

            // Test 5: Help & Version Flags
            runner.test("Help and version flags set flags cleanly") {
                let helpOpts1 = CommandLineOptions.parse(arguments: ["app", "--help"])
                try assertTrue(helpOpts1.isHelpRequested, "--help flag")

                let helpOpts2 = CommandLineOptions.parse(arguments: ["app", "-h"])
                try assertTrue(helpOpts2.isHelpRequested, "-h flag")

                let versionOpts1 = CommandLineOptions.parse(arguments: ["app", "--version"])
                try assertTrue(versionOpts1.isVersionRequested, "--version flag")

                let versionOpts2 = CommandLineOptions.parse(arguments: ["app", "-v"])
                try assertTrue(versionOpts2.isVersionRequested, "-v flag")

                let dumpOpts = CommandLineOptions.parse(arguments: ["app", "--dump-config"])
                try assertTrue(dumpOpts.dumpConfig, "--dump-config flag")
            }

            // Test 6: Robustness on Missing Argument at End
            runner.test("Missing argument at argv end is handled gracefully") {
                let args = ["app", "--video"]
                let opts = CommandLineOptions.parse(arguments: args)
                try assertNil(opts.videoPath, "videoPath should be nil")
                try assertEqual(opts.unknownOptions.count, 1, "Recorded in unknown options")
                try assertEqual(opts.unknownOptions.first, "--video", "Flag recorded")
            }

            // Test 7: Robustness on Flag Followed Immediately by Flag
            runner.test("Flag followed immediately by another flag is handled safely") {
                let args = ["app", "--video", "--headless"]
                let opts = CommandLineOptions.parse(arguments: args)
                try assertNil(opts.videoPath, "videoPath should be nil")
                try assertTrue(opts.isHeadless, "isHeadless should be true")
            }

            // Test 8: Non-Numeric and Negative Numeric Arguments
            runner.test("Non-numeric and negative values handled with defaults") {
                let args = [
                    "app",
                    "--display", "invalid_display",
                    "--fps", "ultra",
                    "--throttled-fps", "-10"
                ]
                let opts = CommandLineOptions.parse(arguments: args)
                try assertNil(opts.targetDisplayID, "targetDisplayID should be nil")
                try assertNil(opts.targetFPS, "targetFPS should be nil")
                try assertNil(opts.throttledFPS, "throttledFPS should be nil")
                try assertEqual(opts.unknownOptions.count, 3, "3 invalid tokens recorded")
            }

            // Test 9: Unknown Flags
            runner.test("Unknown flags are collected in unknownOptions without crashing") {
                let args = ["app", "--unknown-flag", "--another-option=value", "-z"]
                let opts = CommandLineOptions.parse(arguments: args)
                try assertEqual(opts.unknownOptions.count, 3, "All 3 unknown options preserved")
            }

            // Test 10: Apply to EngineConfig (Global Video)
            runner.test("apply(to:) overlays global video and FPS on config") {
                var config = EngineConfig()
                config.targetFrameRate = 60
                config.pauseOnBattery = false
                config.defaultAssetPath = nil

                let opts = CommandLineOptions(
                    videoPath: "/wallpapers/beach.mp4",
                    targetFPS: 120,
                    throttledFPS: 30,
                    pauseOnBattery: true
                )
                opts.apply(to: &config)

                try assertEqual(config.defaultAssetPath, "/wallpapers/beach.mp4", "defaultAssetPath updated")
                try assertEqual(config.targetFrameRate, 120, "targetFrameRate updated")
                try assertEqual(config.throttledFrameRate, 30, "throttledFrameRate updated")
                try assertTrue(config.pauseOnBattery, "pauseOnBattery updated")
            }

            // Test 11: Apply to EngineConfig (Per-Display Video)
            runner.test("apply(to:) overlays per-display video on config") {
                var config = EngineConfig()
                let opts = CommandLineOptions(
                    videoPath: "/wallpapers/display2.mp4",
                    targetDisplayID: 2
                )
                opts.apply(to: &config)

                try assertNil(config.defaultAssetPath, "defaultAssetPath remains nil")
                try assertEqual(config.displayConfigurations["2"]?.assetPath, "/wallpapers/display2.mp4", "Display 2 asset updated")
            }
        }
    }
}

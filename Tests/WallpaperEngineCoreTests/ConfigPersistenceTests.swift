//
//  ConfigPersistenceTests.swift
//  WallpaperEngineCoreTests
//
//  Comprehensive test suite for EngineConfig serialization, atomic persistence, and resilience.
//

import Foundation
@testable import WallpaperEngineCore

@MainActor
public struct ConfigPersistenceTests {
    public static func runAllTests() async {
        let runner = TestRunner.shared

        await runner.runSuite("Suite: Configuration Persistence & Resilience") {

            // Helper to make unique temp directory
            func makeTempDirectory() throws -> URL {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("WE_ConfigTest_\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
                return tempURL
            }

            // Test 1: Default App Support Path Resolution
            runner.test("Default config directory resolves within Application Support") {
                let dir = ConfigPersistenceManager.defaultConfigDirectoryURL
                try assertTrue(dir.path.contains("Application Support/WallpaperEngineCore"), "Default path in App Support")
                let file = ConfigPersistenceManager.defaultConfigURL
                try assertTrue(file.path.hasSuffix("config.json"), "Ends with config.json")
            }

            // Test 2: Auto-Create Directory Tree on Save
            runner.test("Saving config auto-creates missing parent directories") {
                let tempDir = try makeTempDirectory()
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let nestedDir = tempDir.appendingPathComponent("nested/deep/directory", isDirectory: true)
                let targetFile = nestedDir.appendingPathComponent("config.json")
                let manager = ConfigPersistenceManager(configURL: targetFile)

                var config = EngineConfig()
                config.targetFrameRate = 144
                try manager.save(config)

                try assertTrue(FileManager.default.fileExists(atPath: targetFile.path), "File created")
                let loaded = manager.load()
                try assertEqual(loaded.targetFrameRate, 144, "Config correctly persisted")
            }

            // Test 3: Complete Codable Roundtrip
            runner.test("EngineConfig Codable serialization preserves all properties") {
                var original = EngineConfig()
                original.version = 2
                original.isPaused = true
                original.targetFrameRate = 120
                original.throttledFrameRate = 45
                original.pauseOnBattery = true
                original.throttleOnBattery = false
                original.pauseOnLowPowerMode = false
                original.pauseOnScreenLock = false
                original.pauseOnDisplaySleep = false
                original.pauseWhenOccluded = false
                original.isMuted = false
                original.hardwareDecodingEnabled = false
                original.defaultAssetPath = "/wallpapers/forest.mp4"
                original.displayConfigurations["1"] = DisplayConfig(assetPath: "/wallpapers/monitor1.mov", scalingMode: .aspectFit, isEnabled: true, isMuted: true)

                let encoder = JSONEncoder()
                let data = try encoder.encode(original)

                let decoder = JSONDecoder()
                let decoded = try decoder.decode(EngineConfig.self, from: data)

                try assertEqual(decoded, original, "Decoded config matches original")
                try assertEqual(decoded.displayConfigurations["1"]?.scalingMode, .aspectFit, "ScalingMode matches")
            }

            // Test 4: Missing File Fallback
            runner.test("Loading missing config file gracefully returns default config") {
                let tempDir = try makeTempDirectory()
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let nonExistentFile = tempDir.appendingPathComponent("non_existent.json")
                let manager = ConfigPersistenceManager(configURL: nonExistentFile)

                let loaded = manager.load()
                try assertEqual(loaded, EngineConfig.default, "Falls back to default config")
            }

            // Test 5: Empty (0-Byte) File Fallback
            runner.test("Loading empty 0-byte file gracefully falls back to default") {
                let tempDir = try makeTempDirectory()
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let emptyFile = tempDir.appendingPathComponent("empty_config.json")
                try Data().write(to: emptyFile)
                let manager = ConfigPersistenceManager(configURL: emptyFile)

                let loaded = manager.load()
                try assertEqual(loaded, EngineConfig.default, "Falls back to default config on empty file")
            }

            // Test 6: Malformed / Truncated JSON Fallback
            runner.test("Loading corrupt JSON gracefully falls back to default without crashing") {
                let tempDir = try makeTempDirectory()
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let corruptFile = tempDir.appendingPathComponent("corrupt.json")
                let badJSON = "{ \"version\": 1, \"isPaused\": true, \"targetFrameRate\": "
                try badJSON.data(using: .utf8)?.write(to: corruptFile)

                let manager = ConfigPersistenceManager(configURL: corruptFile)
                let loaded = manager.load()
                try assertEqual(loaded, EngineConfig.default, "Falls back to default on truncated JSON")
            }

            // Test 7: Atomic Overwrite Prevents Data Loss
            runner.test("Atomic save overwrites existing file cleanly") {
                let tempDir = try makeTempDirectory()
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let configFile = tempDir.appendingPathComponent("atomic_test.json")
                let manager = ConfigPersistenceManager(configURL: configFile)

                var cfg1 = EngineConfig()
                cfg1.targetFrameRate = 30
                try manager.save(cfg1)

                var cfg2 = EngineConfig()
                cfg2.targetFrameRate = 240
                try manager.save(cfg2)

                let loaded = manager.load()
                try assertEqual(loaded.targetFrameRate, 240, "Overwritten cleanly with new value")
            }

            // Test 8: FileConfigStorage Adapter Functionality
            runner.test("FileConfigStorage adapts persistence to ConfigStorageProtocol") {
                let tempDir = try makeTempDirectory()
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let storageFile = tempDir.appendingPathComponent("storage.json")
                let storage = FileConfigStorage(fileURL: storageFile)

                try assertNil(storage.load(), "load() returns nil when file is absent")

                var cfg = EngineConfig()
                cfg.pauseOnBattery = true
                try storage.save(cfg)

                let loaded = storage.load()
                try assertNotNil(loaded, "load() returns config after save")
                try assertEqual(loaded?.pauseOnBattery, true, "Persisted config retains values")
            }
        }
    }
}

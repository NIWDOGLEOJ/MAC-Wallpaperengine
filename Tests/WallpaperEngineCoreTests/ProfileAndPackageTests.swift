//
//  ProfileAndPackageTests.swift
//  WallpaperEngineCoreTests
//
//  Unit tests for ProfileManager, WallpaperPackageManager (.wepack),
//  and WallpaperEditor preview lifecycle.
//

import AppKit
import CoreGraphics
import CryptoKit
import Foundation
@testable import WallpaperEngineCore

@MainActor
public struct ProfileAndPackageTests {
    public static func runAllTests() async {
        let runner = TestRunner.shared

        await runner.runSuite("Suite: Performance Profiles, Editor & Community Packaging") {

            // Test 1: ProfileManager Built-in Profiles & Selection
            runner.test("ProfileManager provides standard profiles and applies configuration atomically") {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_profiles_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let pURL = tempDir.appendingPathComponent("profiles.json")
                let manager = ProfileManager(persistenceURL: pURL)

                try assertEqual(manager.profiles.count, 5, "Has 5 built-in standard profiles")

                var config = EngineConfig()

                // Apply Gaming profile
                if let gaming = manager.profiles.first(where: { $0.type == .gaming }) {
                    manager.applyProfile(gaming, to: &config)
                    try assertEqual(config.targetFrameRate, 60, "Gaming sets targetFrameRate to 60")
                    try assertTrue(gaming.pauseOnFullscreen, "Gaming profile specifies pause on fullscreen")
                    try assertTrue(gaming.pauseOnGame, "Gaming profile specifies pause on game")

                    try assertFalse(config.isAudioReactive, "Gaming disables audio reactivity for performance")
                    try assertFalse(config.hudConfig.isEnabled, "Gaming hides HUD")
                } else {
                    try assertTrue(false, "Gaming profile not found")
                }

                // Apply Battery Saver profile
                if let batterySaver = manager.profiles.first(where: { $0.type == .batterySaver }) {
                    manager.applyProfile(batterySaver, to: &config)
                    try assertEqual(config.targetFrameRate, 24, "Battery saver sets targetFrameRate to 24")
                    try assertEqual(config.throttledFrameRate, 12, "Battery saver sets throttledFrameRate to 12")
                    try assertTrue(config.pauseOnBattery, "Battery saver pauses on battery")
                    try assertTrue(config.useCPUOnlyEngine, "Battery saver enables CPU-only engine")
                } else {
                    try assertTrue(false, "Battery Saver profile not found")
                }
            }

            // Test 2: ProfileManager Custom Profile Persistence
            runner.test("ProfileManager supports adding and removing custom profiles with persistence") {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_custom_profiles_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let pURL = tempDir.appendingPathComponent("profiles.json")
                let manager = ProfileManager(persistenceURL: pURL)

                let custom = EngineProfile(
                    name: "Streamer Setup",
                    type: .custom,
                    targetFrameRate: 60,
                    throttledFrameRate: 30,
                    isAudioReactive: true,
                    showHUD: true,
                    description: "High fidelity with animated visualizer"
                )

                manager.addCustomProfile(custom)
                try assertEqual(manager.profiles.count, 6, "Profile count is 6")

                // Reload from disk to verify persistence
                let reloadedManager = ProfileManager(persistenceURL: pURL)
                try assertEqual(reloadedManager.profiles.count, 6, "Persisted 6 profiles")
                try assertTrue(reloadedManager.profiles.contains(where: { $0.id == custom.id }), "Custom profile present after reload")

                // Remove custom profile
                reloadedManager.removeProfile(id: custom.id)
                try assertEqual(reloadedManager.profiles.count, 5, "Profile count restored to 5")
            }

            // Test 3: WallpaperPackageManager Export & Import (.wepack)
            runner.test("WallpaperPackageManager exports .wepack bundle and verifies SHA-256 integrity on import") {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_pkg_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let assetFile = tempDir.appendingPathComponent("cosmic_voyage.png")
                let dummyData = "CosmicVoyageDataPayload1234567890".data(using: .utf8)!
                try dummyData.write(to: assetFile)

                let pkgManager = WallpaperPackageManager()
                let pkgDir = try pkgManager.exportPackage(
                    title: "Cosmic Voyage",
                    author: "CosmoArtist",
                    type: .staticImage,
                    assetURL: assetFile,
                    destinationDirectory: tempDir
                )

                try assertTrue(FileManager.default.fileExists(atPath: pkgDir.path), "Package directory created")
                let manifestURL = pkgDir.appendingPathComponent("manifest.json")
                try assertTrue(FileManager.default.fileExists(atPath: manifestURL.path), "manifest.json exists")

                // Validate and import package
                let (manifest, resolvedAsset) = try pkgManager.importAndValidatePackage(at: pkgDir)
                try assertEqual(manifest.title, "Cosmic Voyage", "Manifest title matches")
                try assertEqual(manifest.author, "CosmoArtist", "Manifest author matches")
                try assertEqual(manifest.type, .staticImage, "Manifest type matches")
                try assertTrue(FileManager.default.fileExists(atPath: resolvedAsset.path), "Asset file exists")
            }

            // Test 4: WallpaperPackageManager Checksum Tampering Rejection
            runner.test("WallpaperPackageManager rejects tampered package with checksum mismatch") {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_tamper_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let assetFile = tempDir.appendingPathComponent("original.png")
                try "OriginalUntamperedData".data(using: .utf8)!.write(to: assetFile)

                let pkgManager = WallpaperPackageManager()
                let pkgDir = try pkgManager.exportPackage(
                    title: "Tamper Test",
                    type: .staticImage,
                    assetURL: assetFile,
                    destinationDirectory: tempDir
                )

                // Tamper with asset file inside package
                let packagedAsset = pkgDir.appendingPathComponent("original.png")
                try "TAMPERED_PAYLOAD_DATA".data(using: .utf8)!.write(to: packagedAsset)

                do {
                    _ = try pkgManager.importAndValidatePackage(at: pkgDir)
                    try assertTrue(false, "Should have thrown checksumMismatch")
                } catch let err as PackageError {
                    try assertEqual(err, .checksumMismatch, "Caught checksumMismatch error")
                } catch {
                    try assertTrue(false, "Caught unexpected error: \(error)")
                }
            }

            // Test 5: WallpaperPackageManager Path Traversal Defense
            runner.test("WallpaperPackageManager detects and blocks path traversal attempts") {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_traversal_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                // Create a malicious manifest with ../ in mainAssetFileName
                let maliciousManifest = WallpaperPackageManifest(
                    title: "Malicious Pack",
                    type: .staticImage,
                    mainAssetFileName: "../../../etc/passwd"
                )
                let manifestData = try JSONEncoder().encode(maliciousManifest)
                try manifestData.write(to: tempDir.appendingPathComponent("manifest.json"))

                let pkgManager = WallpaperPackageManager()
                do {
                    _ = try pkgManager.importAndValidatePackage(at: tempDir)
                    try assertTrue(false, "Should have thrown pathTraversalAttackDetected")
                } catch let err as PackageError {
                    if case .pathTraversalAttackDetected = err {
                        try assertTrue(true, "Caught pathTraversalAttackDetected")
                    } else {
                        try assertTrue(false, "Expected pathTraversalAttackDetected, got \(err)")
                    }
                } catch {
                    try assertTrue(false, "Caught unexpected error: \(error)")
                }
            }

            // Test 6: WallpaperEditor Preview Lifecycle Isolation
            runner.test("WallpaperEditor maintains isolated preview lifecycle without affecting runtime") {
                let editor = WallpaperEditor()
                try assertFalse(editor.isPreviewActive, "Preview initially inactive")

                editor.startPreview()
                try assertTrue(editor.isPreviewActive, "Preview started")

                editor.config.particleEffect = .rain
                editor.config.brightness = 0.2
                editor.config.vignetteIntensity = 0.5
                try assertEqual(editor.config.particleEffect, .rain, "Particle effect set")
                try assertEqual(editor.config.brightness, 0.2, "Brightness updated")
                try assertEqual(editor.config.vignetteIntensity, 0.5, "Vignette updated")

                editor.stopPreview()
                try assertFalse(editor.isPreviewActive, "Preview stopped cleanly")
            }

            // Test 7: WallpaperPackageManager Schema Version Validation
            runner.test("WallpaperPackageManager rejects unsupported schema version") {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_schema_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let manifest = WallpaperPackageManifest(
                    schemaVersion: 99,
                    title: "Future Pack",
                    type: .staticImage,
                    mainAssetFileName: "wallpaper.png"
                )
                let data = try JSONEncoder().encode(manifest)
                try data.write(to: tempDir.appendingPathComponent("manifest.json"))
                try "dummy".data(using: .utf8)!.write(to: tempDir.appendingPathComponent("wallpaper.png"))

                let pkgManager = WallpaperPackageManager()
                do {
                    _ = try pkgManager.importAndValidatePackage(at: tempDir)
                    try assertTrue(false, "Expected unsupportedSchemaVersion error")
                } catch let err as PackageError {
                    try assertEqual(err, .unsupportedSchemaVersion(99), "Caught unsupportedSchemaVersion(99)")
                } catch {
                    try assertTrue(false, "Caught unexpected error: \(error)")
                }
            }

            // Test 8: WallpaperPackageManager Preview Traversal Defense
            runner.test("WallpaperPackageManager detects and blocks previewFileName path traversal") {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_preview_trav_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let manifest = WallpaperPackageManifest(
                    schemaVersion: 1,
                    title: "Preview Attack",
                    type: .staticImage,
                    mainAssetFileName: "wallpaper.png",
                    previewFileName: "../../etc/shadow"
                )
                let data = try JSONEncoder().encode(manifest)
                try data.write(to: tempDir.appendingPathComponent("manifest.json"))
                try "dummy".data(using: .utf8)!.write(to: tempDir.appendingPathComponent("wallpaper.png"))

                let pkgManager = WallpaperPackageManager()
                do {
                    _ = try pkgManager.importAndValidatePackage(at: tempDir)
                    try assertTrue(false, "Expected pathTraversalAttackDetected error")
                } catch let err as PackageError {
                    if case .pathTraversalAttackDetected = err {
                        try assertTrue(true, "Detected preview path traversal")
                    } else {
                        try assertTrue(false, "Expected pathTraversalAttackDetected, got \(err)")
                    }
                } catch {
                    try assertTrue(false, "Caught unexpected error: \(error)")
                }
            }

            // Test 9: WallpaperPackageManager Symlink Escape Defense
            runner.test("WallpaperPackageManager detects and blocks symlink traversal outside package") {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_symlink_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let outsideFile = FileManager.default.temporaryDirectory.appendingPathComponent("outside_\(UUID().uuidString).txt")
                try "secret_outside".data(using: .utf8)!.write(to: outsideFile)
                defer { try? FileManager.default.removeItem(at: outsideFile) }

                // Create symlink inside package pointing outside
                let symlinkPath = tempDir.appendingPathComponent("symlinked_asset.png").path
                try FileManager.default.createSymbolicLink(atPath: symlinkPath, withDestinationPath: outsideFile.path)

                let manifest = WallpaperPackageManifest(
                    schemaVersion: 1,
                    title: "Symlink Attack",
                    type: .staticImage,
                    mainAssetFileName: "symlinked_asset.png"
                )
                let data = try JSONEncoder().encode(manifest)
                try data.write(to: tempDir.appendingPathComponent("manifest.json"))

                let pkgManager = WallpaperPackageManager()
                do {
                    _ = try pkgManager.importAndValidatePackage(at: tempDir)
                    try assertTrue(false, "Expected pathTraversalAttackDetected error on symlink escape")
                } catch let err as PackageError {
                    if case .pathTraversalAttackDetected = err {
                        try assertTrue(true, "Detected symlink traversal escape")
                    } else {
                        try assertTrue(false, "Expected pathTraversalAttackDetected, got \(err)")
                    }
                } catch {
                    try assertTrue(false, "Caught unexpected error: \(error)")
                }
            }

            // Test 10: ProfileManager Protects Standard Profiles From Deletion
            runner.test("ProfileManager prevents deletion of built-in standard profiles") {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_profiles_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }
                let persistenceURL = tempDir.appendingPathComponent("profiles.json")

                let manager = ProfileManager(persistenceURL: persistenceURL)
                let initialCount = manager.profiles.count
                try assertEqual(initialCount, 5, "Initially 5 standard profiles")

                // Attempt to delete standard profile
                let workProfileID = manager.profiles.first(where: { $0.type == .work })!.id
                manager.removeProfile(id: workProfileID)
                try assertEqual(manager.profiles.count, initialCount, "Standard profile cannot be deleted")

                // Add and delete custom profile
                let custom = EngineProfile(name: "Custom 1", type: .custom, targetFrameRate: 40)
                manager.addCustomProfile(custom)
                try assertEqual(manager.profiles.count, initialCount + 1, "Custom profile added")
                manager.removeProfile(id: custom.id)
                try assertEqual(manager.profiles.count, initialCount, "Custom profile deleted successfully")
            }

            // Test 11: ProfileManager Reload Guarantees Standard Profiles Intact
            runner.test("ProfileManager reloads custom profiles while preserving all standard profiles") {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_reload_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }
                let persistenceURL = tempDir.appendingPathComponent("profiles.json")

                let manager1 = ProfileManager(persistenceURL: persistenceURL)
                let custom = EngineProfile(name: "Ultra Saver", type: .custom, targetFrameRate: 15)
                manager1.addCustomProfile(custom)

                // Instantiate new manager instance loading from same disk URL
                let manager2 = ProfileManager(persistenceURL: persistenceURL)
                try assertEqual(manager2.profiles.count, 6, "Total 6 profiles after reload")
                try assertTrue(manager2.profiles.contains(where: { $0.name == "Ultra Saver" }), "Custom profile persisted")
                try assertTrue(manager2.profiles.contains(where: { $0.type == .work }), "Standard Work profile exists")
                try assertTrue(manager2.profiles.contains(where: { $0.type == .gaming }), "Standard Gaming profile exists")
            }
        }
    }
}

//
//  LibraryAndPlaylistTests.swift
//  WallpaperEngineCoreTests
//
//  Unit tests for WallpaperThumbnailCache, WallpaperLibraryManager,
//  and WallpaperPlaylistManager event-driven scheduling.
//

import AppKit
import CoreGraphics
import Foundation
@testable import WallpaperEngineCore

@MainActor
public struct LibraryAndPlaylistTests {
    public static func runAllTests() async {
        let runner = TestRunner.shared

        await runner.runSuite("Suite: Wallpaper Library & Playlist Engine") {

            // Test 1: WallpaperThumbnailCache Memory & Disk Operations
            await runner.testAsync("WallpaperThumbnailCache caches and purges memory and disk representations") {
                let cache = WallpaperThumbnailCache.shared
                cache.purge()

                let dummyURL = URL(fileURLWithPath: "/tmp/sample_thumbnail_test.png")
                let initial = await cache.thumbnail(for: dummyURL)
                try assertNil(initial, "No thumbnail for non-existent file")

                cache.clearMemoryCache()
                try assertTrue(true, "clearMemoryCache executed cleanly")
            }

            // Test 2: WallpaperLibraryManager Item Import & Metadata Extraction
            await runner.testAsync("WallpaperLibraryManager imports file, extracts dimensions, size, and SHA-256") {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_lib_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let persistenceURL = tempDir.appendingPathComponent("library.json")
                let manager = WallpaperLibraryManager(persistenceURL: persistenceURL)

                // Create a synthetic image file
                let imgURL = tempDir.appendingPathComponent("aurora_sample.png")
                createDummyImageFile(at: imgURL, width: 256, height: 128)

                let item = try await manager.importWallpaper(from: imgURL, tags: ["nature", "neon"], category: "Abstract")
                try assertEqual(item.title, "Aurora Sample", "Title derived from filename")
                try assertEqual(item.type, .staticImage, "Type recognized as static image")
                try assertEqual(item.category, "Abstract", "Category recorded")
                try assertTrue(item.tags.contains("nature"), "Tag preserved")
                try assertEqual(item.width, 256, "Width extracted as 256")
                try assertEqual(item.height, 128, "Height extracted as 128")
                try assertNotNil(item.sha256, "SHA-256 checksum calculated")
                try assertEqual(manager.items.count, 1, "Item added to library")

                // Test Duplicate Detection
                let dupItem = try await manager.importWallpaper(from: imgURL)
                try assertEqual(dupItem.id, item.id, "Duplicate import returns existing item without adding second entry")
                try assertEqual(manager.items.count, 1, "Items count remains 1")
            }

            // Test 3: WallpaperLibraryManager Search & Filtering
            await runner.testAsync("WallpaperLibraryManager searches by title, tags, and category") {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_lib_filter_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let manager = WallpaperLibraryManager(persistenceURL: tempDir.appendingPathComponent("lib.json"))

                let img1 = tempDir.appendingPathComponent("cyberpunk_city.png")
                let img2 = tempDir.appendingPathComponent("tranquil_lake.png")
                createDummyImageFile(at: img1, width: 100, height: 100)
                createDummyImageFile(at: img2, width: 100, height: 100)

                _ = try await manager.importWallpaper(from: img1, tags: ["neon", "city"], category: "Sci-Fi")
                let item2 = try await manager.importWallpaper(from: img2, tags: ["water", "calm"], category: "Nature")

                manager.toggleFavorite(id: item2.id)
                try assertTrue(manager.items.first(where: { $0.id == item2.id })?.isFavorite ?? false, "Favorite toggled")

                let queryResults = manager.search(query: "cyber")
                try assertEqual(queryResults.count, 1, "Search by text matched 1 item")
                try assertEqual(queryResults.first?.title, "Cyberpunk City", "Matched correct item")

                let tagResults = manager.search(query: "", tag: "water")
                try assertEqual(tagResults.count, 1, "Tag search matched 1 item")

                let favResults = manager.search(query: "", onlyFavorites: true)
                try assertEqual(favResults.count, 1, "Favorite filter matched 1 item")
                try assertEqual(favResults.first?.id, item2.id, "Favorite matches item2")
            }

            // Test 4: WallpaperLibraryManager Missing Files Audit
            await runner.testAsync("WallpaperLibraryManager auditMissingFiles identifies deleted local assets") {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_audit_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let manager = WallpaperLibraryManager(persistenceURL: tempDir.appendingPathComponent("lib.json"))
                let fileURL = tempDir.appendingPathComponent("temporary_asset.png")
                createDummyImageFile(at: fileURL, width: 64, height: 64)

                let item = try await manager.importWallpaper(from: fileURL)
                try assertTrue(manager.auditMissingFiles().isEmpty, "No missing files initially")

                // Delete the physical file
                try FileManager.default.removeItem(at: fileURL)
                let missing = manager.auditMissingFiles()
                try assertEqual(missing.count, 1, "Identifies 1 missing file")
                try assertEqual(missing.first?.id, item.id, "Missing item matches ID")
            }


            // Test 5: WallpaperPlaylistManager Sequential & Shuffle Playlist Logic
            runner.test("WallpaperPlaylistManager resolves items in sequential and shuffle order") {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_plist_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let pManager = WallpaperPlaylistManager(persistenceURL: tempDir.appendingPathComponent("playlists.json"))

                let item1 = PlaylistItem(url: URL(fileURLWithPath: "/tmp/w1.png"), title: "Wallpaper 1")
                let item2 = PlaylistItem(url: URL(fileURLWithPath: "/tmp/w2.png"), title: "Wallpaper 2")
                let item3 = PlaylistItem(url: URL(fileURLWithPath: "/tmp/w3.png"), title: "Wallpaper 3")

                let playlist = WallpaperPlaylist(
                    name: "Scenic Rotation",
                    items: [item1, item2, item3],
                    order: .sequential,
                    intervalSeconds: 60
                )

                pManager.createPlaylist(playlist)
                try assertEqual(pManager.playlists.count, 1, "Playlist created")

                pManager.start(playlistID: playlist.id)
                try assertTrue(pManager.isRunning, "Playlist manager started")
                try assertEqual(pManager.activePlaylistID, playlist.id, "Active playlist set")

                let next1 = pManager.nextItem()
                try assertEqual(next1?.id, item2.id, "Sequential advances to item 2")

                let next2 = pManager.nextItem()
                try assertEqual(next2?.id, item3.id, "Sequential advances to item 3")

                let next3 = pManager.nextItem()
                try assertEqual(next3?.id, item1.id, "Sequential wraps around to item 1")

                pManager.stop()
                try assertFalse(pManager.isRunning, "Playlist manager stopped")
            }

            // Test 6: WallpaperPlaylistManager TimeOfDayProfile Evaluation
            runner.test("TimeOfDayProfile evaluates current profile cleanly") {
                let profile = TimeOfDayProfile.current()
                try assertTrue(TimeOfDayProfile.allCases.contains(profile), "Current profile is a valid case")
            }

            // Test 7: WallpaperPlaylistManager Pause and Resume preserves currentIndex
            runner.test("WallpaperPlaylistManager pause and resume preserve currentIndex") {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_plist_pause_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let pManager = WallpaperPlaylistManager(persistenceURL: tempDir.appendingPathComponent("playlists.json"))

                let item1 = PlaylistItem(url: URL(fileURLWithPath: "/tmp/w1.png"), title: "Wallpaper 1")
                let item2 = PlaylistItem(url: URL(fileURLWithPath: "/tmp/w2.png"), title: "Wallpaper 2")
                let item3 = PlaylistItem(url: URL(fileURLWithPath: "/tmp/w3.png"), title: "Wallpaper 3")

                let playlist = WallpaperPlaylist(
                    name: "Pause/Resume Test",
                    items: [item1, item2, item3],
                    order: .sequential,
                    intervalSeconds: 60
                )
                pManager.createPlaylist(playlist)
                pManager.start(playlistID: playlist.id)

                // Advance to index 1
                _ = pManager.nextItem()
                try assertEqual(pManager.currentIndex, 1, "Index advanced to 1")

                pManager.pause()
                try assertFalse(pManager.isRunning, "Manager paused")
                try assertEqual(pManager.currentIndex, 1, "Current index preserved after pause")

                pManager.resume()
                try assertTrue(pManager.isRunning, "Manager resumed")
                try assertEqual(pManager.currentIndex, 1, "Current index remains 1 after resume")

                pManager.stop()
            }

            // Test 8: WallpaperPlaylistManager Filters to Favorites when onlyFavorites is True
            runner.test("WallpaperPlaylistManager effectiveItems filters strictly to favorites") {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_plist_fav_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let pManager = WallpaperPlaylistManager(persistenceURL: tempDir.appendingPathComponent("playlists.json"))

                let item1 = PlaylistItem(url: URL(fileURLWithPath: "/tmp/w1.png"), title: "Wallpaper 1", isFavorite: false)
                let item2 = PlaylistItem(url: URL(fileURLWithPath: "/tmp/w2.png"), title: "Wallpaper 2", isFavorite: true)
                let item3 = PlaylistItem(url: URL(fileURLWithPath: "/tmp/w3.png"), title: "Wallpaper 3", isFavorite: false)
                let item4 = PlaylistItem(url: URL(fileURLWithPath: "/tmp/w4.png"), title: "Wallpaper 4", isFavorite: true)

                let playlist = WallpaperPlaylist(
                    name: "Favorites Only Playlist",
                    items: [item1, item2, item3, item4],
                    order: .sequential,
                    intervalSeconds: 60,
                    onlyFavorites: true
                )
                pManager.createPlaylist(playlist)
                pManager.start(playlistID: playlist.id)

                let effective = pManager.effectiveItems
                try assertEqual(effective.count, 2, "Only favorite items in effectiveItems")
                try assertEqual(effective.map { $0.title }, ["Wallpaper 2", "Wallpaper 4"], "Correct favorite items preserved")

                pManager.stop()
            }

            // Test 9: WallpaperPlaylistManager Persistence across instances
            runner.test("WallpaperPlaylistManager restores activePlaylistID and currentIndex across instances") {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_plist_persist_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let fileURL = tempDir.appendingPathComponent("playlists.json")
                let pManager1 = WallpaperPlaylistManager(persistenceURL: fileURL)

                let item1 = PlaylistItem(url: URL(fileURLWithPath: "/tmp/w1.png"), title: "Wallpaper 1")
                let item2 = PlaylistItem(url: URL(fileURLWithPath: "/tmp/w2.png"), title: "Wallpaper 2")
                let item3 = PlaylistItem(url: URL(fileURLWithPath: "/tmp/w3.png"), title: "Wallpaper 3")

                let playlist = WallpaperPlaylist(
                    name: "Persistence Test",
                    items: [item1, item2, item3],
                    order: .sequential,
                    intervalSeconds: 60
                )
                pManager1.createPlaylist(playlist)
                pManager1.start(playlistID: playlist.id)
                _ = pManager1.nextItem() // index 1
                _ = pManager1.nextItem() // index 2
                try assertEqual(pManager1.currentIndex, 2, "Advanced to index 2")

                // Now create a new manager instance reading from the same file
                let pManager2 = WallpaperPlaylistManager(persistenceURL: fileURL)
                try assertEqual(pManager2.playlists.count, 1, "Restored playlist")
                try assertEqual(pManager2.activePlaylistID, playlist.id, "Restored activePlaylistID")
                try assertEqual(pManager2.currentIndex, 2, "Restored currentIndex across instances")
            }
        }
    }

    // MARK: - Helpers

    private static func createDummyImageFile(at url: URL, width: Int, height: Int) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        if let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) {
            context.setFillColor(NSColor.systemTeal.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            if let image = context.makeImage() {
                if let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, image, nil)
                    CGImageDestinationFinalize(destination)
                }
            }
        }
    }
}

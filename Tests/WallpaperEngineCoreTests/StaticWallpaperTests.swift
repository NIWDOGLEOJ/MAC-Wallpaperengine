//
//  StaticWallpaperTests.swift
//  WallpaperEngineCoreTests
//
//  Unit tests for StaticWallpaperCache, StaticWallpaperView CALayer scanout,
//  0% sustained CPU guarantee, and DisplaySpanManager multi-monitor slicing.
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import QuartzCore
@testable import WallpaperEngineCore

@MainActor
public struct StaticWallpaperTests {
    public static func runAllTests() async {
        let runner = TestRunner.shared

        await runner.runSuite("Suite: Static Wallpaper Cache & CALayer Scanout Engine") {

            // Test 1: StaticWallpaperCache Caching, Retrieval & Purge
            runner.test("StaticWallpaperCache caches CGImages, retrieves correctly, and purges on demand") {
                let cache = StaticWallpaperCache(countLimit: 3, totalCostLimitMB: 50)
                guard let image1 = createSyntheticCGImage(width: 50, height: 50),
                      let image2 = createSyntheticCGImage(width: 60, height: 60) else {
                    try assertTrue(false, "Failed to create synthetic images")
                    return
                }

                let url1 = URL(fileURLWithPath: "/tmp/fake_image1.png")
                let url2 = URL(fileURLWithPath: "/tmp/fake_image2.png")

                try assertNil(cache.image(for: url1), "Initially empty")
                cache.setImage(image1, for: url1)
                try assertNotNil(cache.image(for: url1), "Cached image1 retrieved")

                cache.setImage(image2, for: url2)
                try assertNotNil(cache.image(for: url2), "Cached image2 retrieved")

                cache.removeImage(for: url1)
                try assertNil(cache.image(for: url1), "Image1 removed")
                try assertNotNil(cache.image(for: url2), "Image2 still cached")

                cache.clear()
                try assertNil(cache.image(for: url2), "All images purged after clear")
            }

            // Test 2: StaticWallpaperView Layer Configuration & Redraw Policy
            runner.test("StaticWallpaperView enforces 0% CPU with layerContentsRedrawPolicy .never") {
                let frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
                let view = StaticWallpaperView(frame: frame)

                try assertTrue(view.wantsLayer, "View is layer-backed")
                try assertEqual(view.layerContentsRedrawPolicy, .never, "Redraw policy strictly .never to guarantee 0% redraws")
                try assertNotNil(view.layer, "CALayer present")
            }

            // Test 3: StaticWallpaperView Scaling Modes & ContentsGravity Mapping
            runner.test("StaticWallpaperView scaling modes map accurately to CALayerContentsGravity") {
                let view = StaticWallpaperView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

                view.scalingMode = .aspectFill
                try assertEqual(view.scalingMode.contentsGravity, .resizeAspectFill, "Aspect fill maps to resizeAspectFill")
                try assertEqual(view.layer?.contentsGravity, .resizeAspectFill, "Layer contentsGravity updated")

                view.scalingMode = .aspectFit
                try assertEqual(view.scalingMode.contentsGravity, .resizeAspect, "Aspect fit maps to resizeAspect")
                try assertEqual(view.layer?.contentsGravity, .resizeAspect, "Layer contentsGravity updated")

                view.scalingMode = .stretch
                try assertEqual(view.scalingMode.contentsGravity, .resize, "Stretch maps to resize")
                try assertEqual(view.layer?.contentsGravity, .resize, "Layer contentsGravity updated")

                view.scalingMode = .center
                try assertEqual(view.scalingMode.contentsGravity, .center, "Center maps to center")
                try assertEqual(view.layer?.contentsGravity, .center, "Layer contentsGravity updated")
            }

            // Test 4: StaticWallpaperView Image Loading, Direct Application & Clear
            runner.test("StaticWallpaperView applies CGImage directly and clears cleanly") {
                let view = StaticWallpaperView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
                guard let testImage = createSyntheticCGImage(width: 200, height: 200) else {
                    try assertTrue(false, "Failed to create test CGImage")
                    return
                }

                view.applyImage(testImage)
                try assertNotNil(view.currentCGImage, "currentCGImage set")
                try assertNotNil(view.layer?.contents, "Layer contents assigned")

                view.clear()
                try assertNil(view.currentCGImage, "currentCGImage cleared")
                try assertNil(view.layer?.contents, "Layer contents nil after clear")
            }

            // Test 5: StaticWallpaperView File Loading via ImageIO
            await runner.testAsync("StaticWallpaperView asynchronously decodes image from disk URL") {

                guard let cgImg = createSyntheticCGImage(width: 100, height: 100) else {
                    try assertTrue(false, "Failed to create synthetic CGImage")
                    return
                }
                let fileURL = saveCGImageToTempFile(cgImg)
                defer { try? FileManager.default.removeItem(at: fileURL) }

                let view = StaticWallpaperView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
                let customCache = StaticWallpaperCache(countLimit: 5, totalCostLimitMB: 10)

                let loadedImage = try await view.loadWallpaper(from: fileURL, cache: customCache)
                try assertEqual(loadedImage.width, 100, "Loaded image width 100")
                try assertEqual(loadedImage.height, 100, "Loaded image height 100")
                try assertEqual(view.currentImageURL, fileURL, "currentImageURL recorded")
                try assertNotNil(customCache.image(for: fileURL), "Cached in memory")
            }

            // Test 6: DisplaySpanManager Multi-Monitor Spanning Geometry
            runner.test("DisplaySpanManager calculates normalized contentsRect across dual screens") {
                let spanManager = DisplaySpanManager()

                // Two 1920x1080 screens side-by-side:
                // Screen 1: (0, 0, 1920, 1080)
                // Screen 2: (1920, 0, 1920, 1080)
                // Combined Union: (0, 0, 3840, 1080)
                let id1: CGDirectDisplayID = 1
                let id2: CGDirectDisplayID = 2
                let allScreens: [CGDirectDisplayID: CGRect] = [
                    id1: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                    id2: CGRect(x: 1920, y: 0, width: 1920, height: 1080)
                ]

                let slice1 = spanManager.normalizedContentsRect(for: id1, allScreens: allScreens)
                let slice2 = spanManager.normalizedContentsRect(for: id2, allScreens: allScreens)

                try assertEqual(slice1.minX, 0.0, "Screen 1 slice minX is 0.0")
                try assertEqual(slice1.width, 0.5, "Screen 1 slice width is 0.5 (left half)")
                try assertEqual(slice1.height, 1.0, "Screen 1 slice height is 1.0")

                try assertEqual(slice2.minX, 0.5, "Screen 2 slice minX is 0.5")
                try assertEqual(slice2.width, 0.5, "Screen 2 slice width is 0.5 (right half)")
                try assertEqual(slice2.height, 1.0, "Screen 2 slice height is 1.0")
            }

            // Test 7: StaticWallpaperView ContentsRect Property Updates CALayer
            runner.test("StaticWallpaperView contentsRect property updates layer.contentsRect") {
                let view = StaticWallpaperView(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080))
                let customRect = CGRect(x: 0.25, y: 0.0, width: 0.5, height: 1.0)
                view.contentsRect = customRect

                try assertEqual(view.contentsRect, customRect, "contentsRect property returns assigned rect")
                try assertEqual(view.layer?.contentsRect, customRect, "layer.contentsRect updated")
            }
        }
    }

    // MARK: - Helpers

    private static func createSyntheticCGImage(width: Int = 100, height: Int = 100, color: CGColor = NSColor.blue.cgColor) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func saveCGImageToTempFile(_ cgImage: CGImage) -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_static_\(UUID().uuidString).png")
        if let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, cgImage, nil)
            CGImageDestinationFinalize(destination)
        }
        return tempURL
    }
}

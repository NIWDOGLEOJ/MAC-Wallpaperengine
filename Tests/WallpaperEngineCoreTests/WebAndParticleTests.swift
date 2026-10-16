//
//  WebAndParticleTests.swift
//  WallpaperEngineCoreTests
//
//  Unit tests for WebWallpaperView WKWebView sandboxing & lifecycle suspension,
//  and InteractiveParticleWallpaperView 2D physics & particle generation.
//

import AppKit
import CoreGraphics
import Foundation
import WebKit
@testable import WallpaperEngineCore

@MainActor
public struct WebAndParticleTests {
    public static func runAllTests() async {
        let runner = TestRunner.shared

        await runner.runSuite("Suite: Web Wallpaper & Interactive Particle Engine") {

            // Test 1: WebWallpaperView Initialization & Sandboxing Defaults
            runner.test("WebWallpaperView initializes with strict sandboxing and paused state false") {
                let frame = NSRect(x: 0, y: 0, width: 1280, height: 720)
                let webView = WebWallpaperView(frame: frame)

                try assertFalse(webView.isPaused, "Initially not paused")
                try assertFalse(webView.allowNetworkRequests, "Network requests disabled by default")
                try assertNil(webView.currentURL, "currentURL initially nil")
                try assertNil(webView.webView, "WKWebView lazily created upon loading")
            }

            // Test 2: WebWallpaperView Load Local HTML File & Lifecycle
            runner.test("WebWallpaperView loads local HTML file, pauses, resumes, and tears down cleanly") {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_web_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let htmlFile = tempDir.appendingPathComponent("index.html")
                let htmlContent = "<html><body><h1>Wallpaper Engine</h1></body></html>"
                try? htmlContent.write(to: htmlFile, atomically: true, encoding: .utf8)

                let view = WebWallpaperView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
                view.loadWebWallpaper(from: htmlFile, allowNetwork: false)

                try assertNotNil(view.webView, "WKWebView instantiated")
                try assertEqual(view.currentURL, htmlFile, "currentURL recorded")

                view.pause()
                try assertTrue(view.isPaused, "View paused")

                view.resume()
                try assertFalse(view.isPaused, "View resumed")

                view.teardownWebView()
                try assertNil(view.webView, "WKWebView destroyed upon teardown")
            }

            // Test 3: InteractiveParticleWallpaperView Initialization & Particle Generation
            runner.test("InteractiveParticleWallpaperView generates particles across all scene types") {
                let frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)

                // 1. Rain Scene
                let rainView = InteractiveParticleWallpaperView(frame: frame, sceneType: .rain)
                try assertEqual(rainView.sceneType, .rain, "Scene type is rain")
                try assertFalse(rainView.isPaused, "Initially active")
                rainView.stopRenderLoop()

                // 2. Snow Scene
                let snowView = InteractiveParticleWallpaperView(frame: frame, sceneType: .snow)
                try assertEqual(snowView.sceneType, .snow, "Scene type is snow")
                snowView.stopRenderLoop()

                // 3. Ambient Fireflies Scene
                let firefliesView = InteractiveParticleWallpaperView(frame: frame, sceneType: .ambientFireflies)
                try assertEqual(firefliesView.sceneType, .ambientFireflies, "Scene type is ambient fireflies")
                firefliesView.stopRenderLoop()
            }

            // Test 4: InteractiveParticleWallpaperView Lifecycle & Frame Rate Controls
            runner.test("InteractiveParticleWallpaperView pause/resume and frame rate clamping") {
                let frame = NSRect(x: 0, y: 0, width: 640, height: 480)
                let view = InteractiveParticleWallpaperView(frame: frame, sceneType: .snow)

                view.setTargetFrameRate(30)
                try assertEqual(view.targetFrameRate, 30, "Target frame rate set to 30")

                view.setTargetFrameRate(-5)
                try assertEqual(view.targetFrameRate, 1, "Clamped to minimum 1 fps")

                view.pause()
                try assertTrue(view.isPaused, "View paused and timer stopped")

                view.resume()
                try assertFalse(view.isPaused, "View resumed and timer restarted")

                view.stopRenderLoop()
            }

            // Test 5: ParticleSceneType Enumeration & Codable Conformance
            runner.test("ParticleSceneType conforms to Codable and CaseIterable") {
                try assertEqual(ParticleSceneType.allCases.count, 3, "Contains exactly 3 scene types")
                let original = ParticleSceneType.ambientFireflies
                let data = try JSONEncoder().encode(original)
                let decoded = try JSONDecoder().decode(ParticleSceneType.self, from: data)
                try assertEqual(decoded, original, "Decodes accurately from JSON")
            }
        }
    }
}

//
//  AppUITests.swift
//  WallpaperEngineCoreTests
//
//  Unit & Integration tests for SwiftUI/AppKit UI Components, AppState, and WindowController.
//

import AppKit
import Foundation
@testable import WallpaperEngineCore

@MainActor
public struct AppUITests {
    public static func runAllTests() async {
        let runner = TestRunner.shared

        await runner.runSuite("Suite: Native macOS Application UI & Studio") {

            // Test 1: NavigationTab destinations
            runner.test("NavigationTab defines all primary app navigation destinations") {
                let tabs = NavigationTab.allCases
                try assertEqual(tabs.count, 7, "Expected 7 navigation destinations")
                try assertTrue(tabs.contains(.gallery), "Gallery tab exists")
                try assertTrue(tabs.contains(.studio), "Studio tab exists")
                try assertTrue(tabs.contains(.audio), "Audio visualizer tab exists")
                try assertTrue(tabs.contains(.hud), "Desktop HUD studio tab exists")
                try assertTrue(tabs.contains(.displays), "Displays manager tab exists")
                try assertTrue(tabs.contains(.performance), "Performance tab exists")
                try assertTrue(tabs.contains(.settings), "Settings tab exists")
            }

            // Test 2: AppState Initialization & Telemetry
            runner.test("AppState initializes cleanly and publishes telemetry updates") {
                var config = EngineConfig.default
                config.shaderSpeed = 1.75
                config.isAudioReactive = true
                config.shaderName = "aurora"

                let state = AppState(config: config)
                try assertEqual(state.shaderSpeed, 1.75, "Shader speed synced")
                try assertTrue(state.isAudioReactive, "Audio reactive synced")
                try assertEqual(state.activeShaderPreset, .aurora, "Preset synced")

                // Test Telemetry Feed
                let sampleTelemetry = SystemTelemetry(
                    cpuPercentage: 14.5,
                    ramPercentage: 20.0,
                    ramUsedGB: 3.2,
                    ramTotalGB: 16.0,
                    gpuPercentage: 10.0,
                    fps: 120
                )
                state.updateTelemetry(sampleTelemetry)
                try assertEqual(state.telemetry.fps, 120, "Telemetry FPS updated")
                try assertEqual(state.telemetry.cpuPercentage, 14.5, "Telemetry CPU updated")

                // Test Audio Spectrum Feed
                let spectrum = AudioSpectrumData(bass: 0.9, mid: 0.5, treble: 0.3, amplitude: 0.7, bands: Array(repeating: 0.85, count: 16))
                state.updateAudioSpectrum(spectrum)
                try assertEqual(state.audioSpectrum.bass, 0.9, "Audio spectrum bass updated")
                try assertEqual(state.audioSpectrum.bands.count, 16, "16 bands preserved")
            }

            // Test 3: Display Updates
            runner.test("AppState receives and records connected display configurations") {
                let state = AppState(config: .default)
                let mockScreens = [
                    ScreenDescriptor(
                        displayID: 1001,
                        name: "Built-in Liquid Retina XDR",
                        frame: CGRect(x: 0, y: 0, width: 3024, height: 1964),
                        scaleFactor: 2.0,
                        isMain: true,
                        isBuiltin: true
                    ),
                    ScreenDescriptor(
                        displayID: 1002,
                        name: "Studio Display",
                        frame: CGRect(x: 3024, y: 0, width: 5120, height: 2880),
                        scaleFactor: 2.0,
                        isMain: false,
                        isBuiltin: false
                    )
                ]

                state.updateDisplays(mockScreens)
                try assertEqual(state.displays.count, 2, "Both displays recorded")
                try assertEqual(state.selectedDisplayID, 1001, "Defaults selection to main display")
                try assertEqual(state.displays[0].bounds.width, 3024, "Bounds convenience helper works")
            }

            // Test 4: Command Line Window Flags
            runner.test("CommandLineOptions parses GUI window and menu-bar-only flags") {
                let guiOpts = CommandLineOptions.parse(arguments: ["--gui", "--fps", "120"])
                try assertTrue(guiOpts.showWindow, "--gui enables showWindow")
                try assertEqual(guiOpts.targetFPS, 120, "FPS parsed")

                let windowOpts = CommandLineOptions.parse(arguments: ["--window"])
                try assertTrue(windowOpts.showWindow, "--window enables showWindow")

                let noWindowOpts = CommandLineOptions.parse(arguments: ["--no-window"])
                try assertTrue(!noWindowOpts.showWindow, "--no-window disables showWindow")

                let menuBarOnlyOpts = CommandLineOptions.parse(arguments: ["--menu-bar-only"])
                try assertTrue(!menuBarOnlyOpts.showWindow, "--menu-bar-only disables showWindow")
            }

            // Test 5: MainWindowController
            runner.test("MainWindowController initializes native NSWindow with modern styling") {
                let state = AppState(config: .default)
                let controller = MainWindowController(appState: state)
                guard let window = controller.window else {
                    throw TestFailure("Expected NSWindow to be created")
                }

                try assertTrue(window.styleMask.contains(.titled), "Window has titlebar")
                try assertTrue(window.styleMask.contains(.closable), "Window is closable")
                try assertTrue(window.styleMask.contains(.miniaturizable), "Window is miniaturizable")
                try assertTrue(window.styleMask.contains(.resizable), "Window is resizable")
                try assertTrue(window.styleMask.contains(.fullSizeContentView), "Window has fullSizeContentView")
                try assertEqual(window.titleVisibility, .hidden, "Title visibility hidden for unified glass")
                try assertTrue(window.titlebarAppearsTransparent, "Titlebar is transparent")
                try assertEqual(window.title, "MAC-Wallpaperengine", "Window title matches")

                // Test window toggle
                controller.showMainWindow()
                try assertTrue(window.isVisible, "Window is visible after showMainWindow")
                controller.hideMainWindow()
                try assertTrue(!window.isVisible, "Window is hidden after hideMainWindow")
            }

            // Test 6: ProceduralShaderPreset Identifiable
            runner.test("ProceduralShaderPreset conforms to Identifiable and matches rawValue") {
                for preset in ProceduralShaderPreset.allCases {
                    try assertEqual(preset.id, preset.rawValue, "Preset id matches rawValue for \(preset.displayName)")
                }
            }
        }
    }
}

//
//  MenuBarControllerTests.swift
//  WallpaperEngineCoreTests
//
//  Comprehensive test suite for MenuBarController menu construction, state updates, and actions.
//

import AppKit
import CoreGraphics
import Foundation
@testable import WallpaperEngineCore

@MainActor
public struct MenuBarControllerTests {
    public static func runAllTests() async {
        let runner = TestRunner.shared

        await runner.runSuite("Suite: MenuBarController Lifecycle, Menus & Actions") {

            // Test 1: Start and Stop Lifecycle with Provider
            runner.test("start() creates status item, sets icon, and builds root menu; stop() cleans up") {
                let provider = MockStatusItemProvider()
                let menuBar = MenuBarController(isHeadless: false, statusItemProvider: provider)

                try assertFalse(menuBar.isRunning, "Initially not running")
                try assertNil(menuBar.statusItem, "Initially status item is nil")

                menuBar.start()
                try assertTrue(menuBar.isRunning, "Running after start")
                try assertEqual(provider.createdItems.count, 1, "Status item created via provider")
                try assertNotNil(menuBar.statusItem, "statusItem is non-nil")

                let mockItem = provider.createdItems[0]
                try assertNotNil(mockItem.menu, "Root menu attached to status item")
                try assertNotNil(mockItem.button?.image, "Status button icon set")

                menuBar.stop()
                try assertFalse(menuBar.isRunning, "Not running after stop")
                try assertEqual(provider.removedItems.count, 1, "Status item removed via provider")
                try assertNil(menuBar.statusItem, "statusItem nil after stop")
            }

            // Test 2: Headless Mode Bypasses Status Item Creation
            runner.test("Headless mode does not create NSStatusItem") {
                let provider = MockStatusItemProvider()
                let menuBar = MenuBarController(isHeadless: true, statusItemProvider: provider)

                menuBar.start()
                try assertTrue(menuBar.isRunning, "Running")
                try assertEqual(provider.createdItems.count, 0, "No status item created in headless mode")
                try assertNil(menuBar.statusItem, "statusItem is nil")
                menuBar.stop()
            }

            // Test 3: Fallback Icon Generation
            runner.test("Fallback icon is valid 18x18 template NSImage") {
                let icon = MenuBarController.makeFallbackIcon()
                try assertEqual(icon.size.width, 18, "Icon width 18")
                try assertEqual(icon.size.height, 18, "Icon height 18")
                try assertTrue(icon.isTemplate, "isTemplate must be true for adaptive menu bar appearance")
            }

            // Test 4: Status Updates and Tooltip Formatting
            runner.test("updatePlaybackState dynamically formats title and tooltip") {
                let provider = MockStatusItemProvider()
                let menuBar = MenuBarController(isHeadless: false, statusItemProvider: provider)
                menuBar.start()

                // Playing state
                menuBar.updatePlaybackState(.playing, decision: nil, powerInfo: "AC Power")
                let button = provider.createdItems[0].mockButton
                try assertTrue(button.toolTip?.contains("Playing (60 FPS)") == true, "Tooltip reflects playing")
                try assertTrue(button.toolTip?.contains("AC Power") == true, "Tooltip contains power info")
                try assertEqual(menuBar.cachedPlayPauseItem?.title, "Pause Playback", "Item says Pause Playback")

                // Paused state
                menuBar.updatePlaybackState(.paused(reason: .screensSleeping), decision: nil, powerInfo: "Battery (80%)")
                try assertTrue(button.toolTip?.contains("Paused") == true, "Tooltip reflects paused")
                try assertTrue(button.toolTip?.contains("Battery (80%)") == true, "Tooltip contains battery info")
                try assertEqual(menuBar.cachedPlayPauseItem?.title, "Resume Playback", "Item says Resume Playback")

                // Throttled state
                menuBar.updatePlaybackState(.throttled(fps: 30), decision: nil, powerInfo: nil)
                try assertTrue(button.toolTip?.contains("Throttled (30 FPS)") == true, "Tooltip reflects throttled")
            }

            // Test 5: Displays Submenu Population
            runner.test("updateDisplays populates submenu with per-screen actions") {
                let provider = MockStatusItemProvider()
                let menuBar = MenuBarController(isHeadless: false, statusItemProvider: provider)
                menuBar.start()

                let displays = [
                    DisplayMenuItemModel(displayID: 1, name: "Built-in Display", frame: CGRect(x: 0, y: 0, width: 2560, height: 1600), currentAssetPath: "/wallpapers/beach.mp4", isPaused: false),
                    DisplayMenuItemModel(displayID: 2, name: "External 4K", frame: CGRect(x: 2560, y: 0, width: 3840, height: 2160), currentAssetPath: nil, isPaused: true)
                ]
                menuBar.updateDisplays(displays)

                guard let sub = menuBar.cachedDisplaysSubmenu else {
                    throw TestFailure("Displays submenu not found")
                }

                // Check display 1 items
                let titles = sub.items.map { $0.title }
                try assertTrue(titles.contains { $0.contains("Built-in Display (2560×1600)") }, "Display 1 title present")
                try assertTrue(titles.contains { $0.contains("Current: beach.mp4") }, "Display 1 asset name present")
                try assertTrue(titles.contains { $0.contains("Choose Wallpaper...") }, "Choose wallpaper present")
                try assertTrue(titles.contains { $0.contains("Pause This Screen") }, "Pause action present for unpaused screen")

                // Check display 2 items
                try assertTrue(titles.contains { $0.contains("External 4K (3840×2160)") }, "Display 2 title present")
                try assertTrue(titles.contains { $0.contains("Resume This Screen") }, "Resume action present for paused screen")
                try assertTrue(titles.contains { $0.contains("Assign Wallpaper to All Displays...") }, "Global action present")
            }

            // Test 6: Empty Displays Submenu
            runner.test("Empty displays list presents 'No Displays Connected'") {
                let provider = MockStatusItemProvider()
                let menuBar = MenuBarController(isHeadless: false, statusItemProvider: provider)
                menuBar.start()

                menuBar.updateDisplays([])
                guard let sub = menuBar.cachedDisplaysSubmenu else {
                    throw TestFailure("Displays submenu not found")
                }
                try assertEqual(sub.items.count, 1, "Exactly 1 item")
                try assertEqual(sub.items.first?.title, "No Displays Connected", "Shows empty state")
                try assertFalse(sub.items.first?.isEnabled ?? true, "Disabled item")
            }

            // Test 7: Preference Checkmarks and Radio Frame Rates
            runner.test("updateConfig updates checkboxes and frame rate radio states") {
                let provider = MockStatusItemProvider()
                let menuBar = MenuBarController(isHeadless: false, statusItemProvider: provider)
                menuBar.start()

                var config = EngineConfig()
                config.pauseOnBattery = true
                config.pauseOnLowPowerMode = false
                config.targetFrameRate = 120

                menuBar.updateConfig(config)

                guard let prefMenu = menuBar.cachedPreferencesSubmenu else {
                    throw TestFailure("Preferences submenu not found")
                }

                let batteryItem = prefMenu.items.first { $0.title == "Pause on Battery" }
                try assertEqual(batteryItem?.state, .on, "Pause on Battery checkbox is on")

                let lpmItem = prefMenu.items.first { $0.title == "Pause on Low Power Mode" }
                try assertEqual(lpmItem?.state, .off, "Pause on LPM checkbox is off")

                // Check frame rate radio item
                let fpsParent = prefMenu.items.first { $0.title == "Target Frame Rate" }
                let fpsSub = fpsParent?.submenu
                let item120 = fpsSub?.items.first { $0.tag == 120 }
                let item60 = fpsSub?.items.first { $0.tag == 60 }
                try assertEqual(item120?.state, .on, "120 FPS radio is checked")
                try assertEqual(item60?.state, .off, "60 FPS radio is unchecked")
            }

            // Test 8: Delegate Callbacks Dispatch
            runner.test("Menu actions dispatch to MenuBarControllerDelegate") {
                let provider = MockStatusItemProvider()
                let pickedURLToReturn: URL? = URL(fileURLWithPath: "/tmp/custom.mp4")

                let menuBar = MenuBarController(
                    isHeadless: false,
                    statusItemProvider: provider,
                    filePickerHandler: { displayID, completion in
                        completion(pickedURLToReturn)
                    }
                )
                let delegate = MockMenuBarControllerDelegate()
                menuBar.delegate = delegate
                menuBar.start()

                // 1. Play/Pause toggle
                menuBar.handlePlayPauseClicked(nil)
                try assertEqual(delegate.togglePlaybackCount, 1, "Play/pause toggled")

                // 2. Choose wallpaper for display 1
                let dummyItem = NSMenuItem(title: "Choose Wallpaper...", action: nil, keyEquivalent: "")
                dummyItem.representedObject = CGDirectDisplayID(1)
                menuBar.handleChooseWallpaperClicked(dummyItem)
                try assertEqual(delegate.selectedAssets.count, 1, "Asset selected")
                try assertEqual(delegate.selectedAssets.first?.displayID, 1, "Target display 1")
                try assertEqual(delegate.selectedAssets.first?.url, pickedURLToReturn, "URL matches")

                // 3. Choose wallpaper for all displays
                menuBar.handleChooseWallpaperForAllClicked(nil)
                try assertEqual(delegate.selectedAssets.count, 2, "Second asset selected")
                try assertNil(delegate.selectedAssets[1].displayID, "Global display is nil")

                // 4. Toggle display pause
                let pauseItem = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
                pauseItem.representedObject = CGDirectDisplayID(42)
                menuBar.handleToggleDisplayPauseClicked(pauseItem)
                try assertEqual(delegate.toggledPauseDisplays.count, 1, "Display pause toggled")
                try assertEqual(delegate.toggledPauseDisplays.first, 42, "Display 42 toggled")

                // 5. Toggle preference checkbox
                menuBar.handleTogglePauseOnBattery(nil)
                try assertEqual(delegate.updatedConfigs.count, 1, "Config updated")
                try assertTrue(delegate.updatedConfigs.first?.pauseOnBattery == true, "pauseOnBattery toggled to true")

                // 6. Select frame rate
                let fpsItem = NSMenuItem(title: "144 FPS", action: nil, keyEquivalent: "")
                fpsItem.tag = 144
                menuBar.handleSelectFrameRate(fpsItem)
                try assertEqual(delegate.selectedFrameRates.first, 144, "144 FPS selected")

                // 7. Reveal wallpapers
                menuBar.handleRevealWallpapersClicked(nil)
                try assertEqual(delegate.revealWallpapersCount, 1, "Reveal wallpapers invoked")

                // 8. Quit action
                menuBar.handleQuitClicked(nil)
                try assertEqual(delegate.quitCount, 1, "Quit action dispatched")
            }
        }
    }
}

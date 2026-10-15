import AppKit
import CoreGraphics
import Foundation
import QuartzCore
@testable import WallpaperEngineCore

@main
@MainActor
struct ChallengerProbes {
    static func main() {
        print("╔════════════════════════════════════════════════════════════════════╗")
        print("║   Milestone 1 DesktopWindow Challenger Empirical Probe Suite       ║")
        print("║   Testing: Levels, Collection Behaviors, Event Immunity, Layers    ║")
        print("╚════════════════════════════════════════════════════════════════════╝")

        var passed = 0
        var failed = 0

        func probe(_ name: String, _ check: () throws -> Void) {
            print("  - Probe: [\(name)]...", terminator: " ")
            fflush(stdout)
            do {
                try check()
                passed += 1
                print("[\u{001B}[32mPASS\u{001B}[0m]")
            } catch {
                failed += 1
                print("[\u{001B}[31mFAIL\u{001B}[0m]: \(error)")
            }
        }

        struct ProbeFailure: Error, CustomStringConvertible {
            let description: String
            init(_ description: String) { self.description = description }
        }

        func require(_ condition: Bool, _ msg: String) throws {
            if !condition { throw ProbeFailure(msg) }
        }

        // -------------------------------------------------------------
        // Probe 1: Exact Window Level & Quartz Constants
        // -------------------------------------------------------------
        print("\n=== Category 1: Window Level & Quartz Z-Order Invariants ===")
        probe("P1.1: Exact CGWindowLevelForKey(.desktopWindow) value is -2147483623") {
            let expected = Int(CGWindowLevelForKey(.desktopWindow))
            try require(expected == -2147483623, "CGWindowLevelForKey(.desktopWindow) must be -2147483623, got \(expected)")
        }

        probe("P1.2: Exact DesktopWindow level equals -2147483623 on initialization") {
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            defer { w.closeAndRelease() }
            let lvl = w.level.rawValue
            try require(lvl == -2147483623, "DesktopWindow level must be -2147483623, got \(lvl)")
            try require(w.windowLevel == -2147483623, "windowLevel protocol property must be -2147483623, got \(w.windowLevel)")
        }

        probe("P1.3: Window level is strictly 20 levels below desktopIconWindow (-2147483603)") {
            let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
            try require(iconLevel == -2147483603, "desktopIconWindow level must be -2147483603, got \(iconLevel)")
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            defer { w.closeAndRelease() }
            try require(w.level.rawValue < iconLevel, "DesktopWindow level must be strictly lower than iconLevel")
            try require(iconLevel - w.level.rawValue == 20, "Distance must be exactly 20 levels below desktopIconWindow")
        }

        probe("P1.4: Window level is strictly 25 levels above baseWindow (-2147483648)") {
            let baseLevel = Int(CGWindowLevelForKey(.baseWindow))
            try require(baseLevel == -2147483648, "baseWindow level must be -2147483648, got \(baseLevel)")
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            defer { w.closeAndRelease() }
            try require(w.level.rawValue > baseLevel, "DesktopWindow level must be strictly higher than baseWindow")
            try require(w.level.rawValue - baseLevel == 25, "Distance above baseWindow must be 25 levels")
        }

        probe("P1.5: Window level stability through ordering and geometry changes") {
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            defer { w.closeAndRelease() }
            w.orderToDesktopLevel()
            try require(w.level.rawValue == -2147483623, "Level must remain -2147483623 after orderToDesktopLevel")
            w.orderBack(nil)
            try require(w.level.rawValue == -2147483623, "Level must remain -2147483623 after orderBack")
            w.updateFrame(CGRect(x: 100, y: 100, width: 2560, height: 1440))
            try require(w.level.rawValue == -2147483623, "Level must remain -2147483623 after updateFrame")
        }

        // -------------------------------------------------------------
        // Probe 2: Collection Behavior Bitmask & Flags
        // -------------------------------------------------------------
        print("\n=== Category 2: Collection Behavior Bitmask & Spaces Flags ===")
        probe("P2.1: Collection behavior contains 4 required flags") {
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            defer { w.closeAndRelease() }
            let b = w.collectionBehavior
            try require(b.contains(.canJoinAllSpaces), "Missing .canJoinAllSpaces (1)")
            try require(b.contains(.stationary), "Missing .stationary (16)")
            try require(b.contains(.ignoresCycle), "Missing .ignoresCycle (64)")
            try require(b.contains(.fullScreenAuxiliary), "Missing .fullScreenAuxiliary (256)")
            try require(w.collectionBehaviorFlags == b, "collectionBehaviorFlags protocol property mismatch")
        }

        probe("P2.2: Composite bitmask exact raw value equals 337 (1 | 16 | 64 | 256)") {
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            defer { w.closeAndRelease() }
            let raw = Int(w.collectionBehavior.rawValue)
            try require(raw == 337, "Raw collectionBehavior must be exactly 337, got \(raw)")
            let expectedMask = 1 | 16 | 64 | 256
            try require(raw ^ expectedMask == 0, "Extra or missing bits found: raw ^ expected = \(raw ^ expectedMask)")
        }

        probe("P2.3: Collection behavior invariant under frame resize and ordering") {
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            defer { w.closeAndRelease() }
            w.orderToDesktopLevel()
            w.updateFrame(CGRect(x: 0, y: 0, width: 3840, height: 2160))
            try require(Int(w.collectionBehavior.rawValue) == 337, "Collection behavior changed after resize: \(w.collectionBehavior.rawValue)")
        }

        // -------------------------------------------------------------
        // Probe 3: Hit-Testing, Event Pass-Through & Focus Immunity
        // -------------------------------------------------------------
        print("\n=== Category 3: Hit-Testing & Focus Immunity ===")
        probe("P3.1: ignoresMouseEvents and ignoresMouseEventsFlag are strictly true") {
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            defer { w.closeAndRelease() }
            try require(w.ignoresMouseEvents == true, "ignoresMouseEvents must be true")
            try require(w.ignoresMouseEventsFlag == true, "ignoresMouseEventsFlag must be true")
        }

        probe("P3.2: Focus overrides prevent becoming key or main window") {
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            defer { w.closeAndRelease() }
            try require(w.canBecomeKey == false, "canBecomeKey must be false")
            try require(w.canBecomeMain == false, "canBecomeMain must be false")
            try require(w.canBecomeKeyWindow == false, "canBecomeKeyWindow must be false")
            try require(w.canBecomeMainWindow == false, "canBecomeMainWindow must be false")

            // Attempt to force key/main activation
            w.makeKeyAndOrderFront(nil)
            try require(w.isKeyWindow == false, "Window must not become key even after makeKeyAndOrderFront")
            try require(w.isMainWindow == false, "Window must not become main window")
        }

        probe("P3.3: Visual chrome styling (borderless, shadowless, opaque, black)") {
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            defer { w.closeAndRelease() }
            try require(w.styleMask.contains(.borderless), "Style mask must contain .borderless")
            try require(w.hasShadow == false, "hasShadow must be false")
            try require(w.isOpaque == true, "isOpaque must be true")
            try require(w.backgroundColor == .black, "backgroundColor must be black")
            try require(w.canHide == false, "canHide must be false")
            try require(w.hidesOnDeactivate == false, "hidesOnDeactivate must be false")
            try require(w.animationBehavior == .none, "animationBehavior must be .none")
            try require(w.sharingType == .none, "sharingType must be .none")
        }

        // -------------------------------------------------------------
        // Probe 4: CALayer Video Scanout Hosting Hierarchy
        // -------------------------------------------------------------
        print("\n=== Category 4: CALayer Video Scanout Hosting Hierarchy ===")
        probe("P4.1: Root layer hosting and video container layer structure") {
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            defer { w.closeAndRelease() }
            try require(w.contentView != nil, "contentView must not be nil")
            try require(w.contentView?.wantsLayer == true, "contentView must have wantsLayer == true")
            try require(w.rootHostingLayer != nil, "rootHostingLayer must not be nil")
            try require(w.currentActiveLayer == nil, "currentActiveLayer must be nil initially")
        }

        probe("P4.2: Direct player layer attachment and removal") {
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            defer { w.closeAndRelease() }
            let player = CALayer()
            player.name = "TestScanoutLayer"
            w.attachPlayerLayer(player)
            try require(w.currentActiveLayer === player, "currentActiveLayer must match attached layer")
            try require(player.superlayer != nil, "player layer must have a superlayer")
            try require(player.frame.size == CGSize(width: 1920, height: 1080), "player layer frame must match window size")

            // Removal
            w.removePlayerLayer()
            try require(w.currentActiveLayer == nil, "currentActiveLayer must be nil after removal")
            try require(player.superlayer == nil, "player layer must be unparented after removal")
        }

        probe("P4.3: contentLayer property get and set") {
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            defer { w.closeAndRelease() }
            try require(w.contentLayer === w.rootHostingLayer, "contentLayer getter should return rootHostingLayer")

            let testLayer = CALayer()
            w.contentLayer = testLayer
            try require(w.currentActiveLayer === testLayer, "contentLayer setter with non-nil should attach layer")

            w.contentLayer = nil
            try require(w.currentActiveLayer == nil, "contentLayer setter with nil should remove layer")
        }

        probe("P4.4: Geometry resizing synchronizes active layer frame") {
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            defer { w.closeAndRelease() }
            let player = CALayer()
            w.attachPlayerLayer(player)
            w.updateFrame(CGRect(x: 0, y: 0, width: 2560, height: 1440))
            try require(w.frame.size == CGSize(width: 2560, height: 1440), "Window frame size must be 2560x1440")
            try require(player.frame.size == CGSize(width: 2560, height: 1440), "Player layer frame must adapt to 2560x1440")
        }

        probe("P4.5: Idempotent closeAndRelease cleans up layers and views cleanly") {
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            let player = CALayer()
            w.attachPlayerLayer(player)
            w.closeAndRelease()
            w.closeAndRelease()
            w.closeAndRelease()
            try require(w.currentActiveLayer == nil, "currentActiveLayer must be nil after closeAndRelease")
            try require(w.contentView == nil, "contentView must be nil after closeAndRelease")
        }

        // -------------------------------------------------------------
        // Probe 5: Rapid Transition Animations Stress Test
        // -------------------------------------------------------------
        print("\n=== Category 5: Rapid Transition Animations Stress Testing ===")
        probe("P5.1: Rapid-fire 50 transitions in succession and intermediate layer eviction") {
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            defer { w.closeAndRelease() }

            var layers: [CALayer] = []
            for i in 0..<50 {
                let l = CALayer()
                l.name = "Layer-\(i)"
                layers.append(l)
            }

            for (i, layer) in layers.enumerated() {
                w.transitionToPlayerLayer(layer, duration: 0.02)
                try require(w.currentActiveLayer === layer, "Active layer must immediately update to Layer-\(i)")
            }

            // Pump runloop for 0.4s to let all CATransaction completion blocks fire
            let deadline = Date().addingTimeInterval(0.4)
            while Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }

            try require(w.currentActiveLayer === layers.last, "Final active layer must be Layer-49")

            guard let rootLayer = w.rootHostingLayer,
                  let container = rootLayer.sublayers?.first else {
                throw ProbeFailure("Could not locate videoContainerLayer")
            }

            let remainingSublayers = container.sublayers ?? []
            try require(remainingSublayers.contains(where: { $0 === layers.last }), "Final layer must be present in container sublayers")
            try require(remainingSublayers.count == 1, "All 49 intermediate layers must be evicted; remaining count was \(remainingSublayers.count)")
        }

        probe("P5.2: Transition with zero duration (immediate swap)") {
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            defer { w.closeAndRelease() }

            let l1 = CALayer()
            let l2 = CALayer()
            w.attachPlayerLayer(l1)
            w.transitionToPlayerLayer(l2, duration: 0.0)

            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            try require(w.currentActiveLayer === l2, "Zero duration transition must switch active layer to l2")
        }

        probe("P5.3: Transition followed immediately by attachPlayerLayer (interrupt)") {
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            defer { w.closeAndRelease() }

            let l1 = CALayer()
            let l2 = CALayer()
            let l3 = CALayer()

            w.attachPlayerLayer(l1)
            w.transitionToPlayerLayer(l2, duration: 0.5)
            w.attachPlayerLayer(l3)

            try require(w.currentActiveLayer === l3, "Immediate attach must override active transition to l3")
        }

        probe("P5.4: Transition followed immediately by removePlayerLayer (interrupt)") {
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            defer { w.closeAndRelease() }

            let l1 = CALayer()
            let l2 = CALayer()

            w.attachPlayerLayer(l1)
            w.transitionToPlayerLayer(l2, duration: 0.5)
            w.removePlayerLayer()

            try require(w.currentActiveLayer == nil, "removePlayerLayer must clear active layer")
        }

        probe("P5.5: Transition followed immediately by closeAndRelease (shutdown during animation)") {
            let w = DesktopWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), displayID: 100)
            let l1 = CALayer()
            let l2 = CALayer()
            w.attachPlayerLayer(l1)
            w.transitionToPlayerLayer(l2, duration: 0.5)
            w.closeAndRelease()

            let deadline = Date().addingTimeInterval(0.1)
            while Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
        }

        // -------------------------------------------------------------
        // Probe 6: Multi-Screen & Geometry Boundary Invariants
        // -------------------------------------------------------------
        print("\n=== Category 6: Boundary Geometries & Screen Coordinates ===")
        probe("P6.1: Zero and extreme window frames preserve window level and bitmask") {
            let wZero = DesktopWindow(contentRect: .zero, displayID: 200)
            defer { wZero.closeAndRelease() }
            try require(wZero.level.rawValue == -2147483623, "Zero frame window level must be -2147483623")
            try require(Int(wZero.collectionBehavior.rawValue) == 337, "Zero frame window collection behavior must be 337")

            let wHuge = DesktopWindow(contentRect: CGRect(x: -5000, y: -5000, width: 16000, height: 16000), displayID: 201)
            defer { wHuge.closeAndRelease() }
            try require(wHuge.level.rawValue == -2147483623, "Huge frame window level must be -2147483623")
            try require(Int(wHuge.collectionBehavior.rawValue) == 337, "Huge frame window collection behavior must be 337")
        }

        print("\n==================================================")
        print("EMPIRICAL PROBE SUMMARY:")
        print("  Total Probes: \(passed + failed)")
        print("  Passed:       \u{001B}[32m\(passed)\u{001B}[0m")
        print("  Failed:       \(failed > 0 ? "\u{001B}[31m\(failed)\u{001B}[0m" : "0")")
        print("==================================================")

        if failed > 0 {
            print("\n\u{001B}[31mFAILURES DETECTED IN PROBE RUN!\u{001B}[0m\n")
            exit(1)
        } else {
            print("\n\u{001B}[32mAll DesktopWindow empirical probes PASSED successfully!\u{001B}[0m\n")
            exit(0)
        }
    }
}

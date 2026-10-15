//
//  MainWindowController.swift
//  WallpaperEngineCore
//
//  Native NSWindowController managing the primary application window lifecycle,
//  vibrancy, dark/light theme, and macOS activation policy transitions.
//

import AppKit
import SwiftUI

@MainActor
public final class MainWindowController: NSWindowController, NSWindowDelegate {
    public let appState: AppState

    public init(appState: AppState) {
        self.appState = appState

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.minSize = NSSize(width: 880, height: 560)
        window.title = "MAC-Wallpaperengine"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("WallpaperEngineMainWindow")

        let hostingView = NSHostingView(rootView: AppMainView(state: appState))
        window.contentView = hostingView

        super.init(window: window)
        window.delegate = self
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Window Management

    /// Shows and activates the main window, transitioning the app to regular activation policy.
    public func showMainWindow() {
        guard let win = window else { return }

        // Switch to regular activation policy so the app appears in the Dock and Cmd+Tab switcher
        NSApp.setActivationPolicy(.regular)

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hides the main window and returns to accessory activation policy.
    public func hideMainWindow() {
        guard let win = window else { return }
        win.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    /// Toggles the main window between visible and hidden.
    public func toggleMainWindow() {
        guard let win = window else { return }
        if win.isVisible && win.isKeyWindow {
            hideMainWindow()
        } else {
            showMainWindow()
        }
    }

    // MARK: - NSWindowDelegate

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide window instead of terminating the background live wallpaper engine
        hideMainWindow()
        return false
    }
}

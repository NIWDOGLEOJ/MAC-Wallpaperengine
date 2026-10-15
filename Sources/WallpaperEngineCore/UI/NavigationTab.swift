//
//  NavigationTab.swift
//  WallpaperEngineCore
//
//  Sidebar navigation sections for the Wallpaper Engine application.
//

import Foundation
import SwiftUI

public enum NavigationTab: String, CaseIterable, Identifiable, Sendable {
    case gallery = "Gallery"
    case studio = "Live Studio"
    case audio = "Audio Reactive"
    case hud = "Desktop HUD"
    case displays = "Displays"
    case performance = "Performance"
    case settings = "About & Settings"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gallery: return "Discover & Gallery"
        case .studio: return "Live Studio & Preview"
        case .audio: return "Audio Reactive Visualizer"
        case .hud: return "Desktop HUD & Widgets"
        case .displays: return "Displays & Monitors"
        case .performance: return "Performance & Power"
        case .settings: return "About & Preferences"
        }
    }

    public var iconName: String {
        switch self {
        case .gallery: return "square.grid.2x2.fill"
        case .studio: return "play.desktopcomputer"
        case .audio: return "waveform"
        case .hud: return "macwindow.on.rectangle"
        case .displays: return "display.2"
        case .performance: return "bolt.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

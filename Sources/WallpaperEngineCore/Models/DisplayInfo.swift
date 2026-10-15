//
//  DisplayInfo.swift
//  WallpaperEngineCore
//
//  Display metadata and screen descriptor models for Milestone 1.
//

import AppKit
import CoreGraphics
import Foundation

/// Type alias for CoreGraphics display identifier.
public typealias DisplayID = CGDirectDisplayID

/// Immutable, Sendable snapshot of physical or virtual display properties.
public struct ScreenDescriptor: Identifiable, Equatable, Hashable, Sendable {
    public var id: CGDirectDisplayID { displayID }
    public let displayID: CGDirectDisplayID
    public let name: String
    public let frame: CGRect
    public let scaleFactor: CGFloat
    public let isMain: Bool
    public let isBuiltin: Bool

    /// Initializes a ScreenDescriptor from an AppKit NSScreen instance.
    @MainActor
    public init(screen: NSScreen) {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let screenNumber = (screen.deviceDescription[key] as? NSNumber)?.uint32Value
            ?? (screen.deviceDescription[key] as? CGDirectDisplayID)
            ?? 0
        self.displayID = screenNumber
        self.name = screen.localizedName
        self.frame = screen.frame
        self.scaleFactor = screen.backingScaleFactor
        self.isMain = (screen == NSScreen.screens.first)
        self.isBuiltin = CGDisplayIsBuiltin(screenNumber) != 0
    }

    /// Memberwise initializer for physical displays, simulations, or headless testing.
    public init(
        displayID: CGDirectDisplayID,
        name: String,
        frame: CGRect,
        scaleFactor: CGFloat = 2.0,
        isMain: Bool = false,
        isBuiltin: Bool = false
    ) {
        self.displayID = displayID
        self.name = name
        self.frame = frame
        self.scaleFactor = scaleFactor
        self.isMain = isMain
        self.isBuiltin = isBuiltin
    }
}

/// Type alias providing DisplayInfo as an equivalent to ScreenDescriptor.
public typealias DisplayInfo = ScreenDescriptor

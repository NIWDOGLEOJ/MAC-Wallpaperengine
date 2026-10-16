//
//  DisplaySpanManager.swift
//  WallpaperEngineCore
//
//  Feature 8: Multi-monitor wallpaper spanning coordinator.
//  Calculates bounding rect union and applies hardware CoreAnimation contentsRect slices.
//

import AppKit
import CoreGraphics
import Foundation
import QuartzCore

public struct DisplaySpanGeometry: Sendable, Equatable {
    public var globalBounds: CGRect
    public var displayRects: [CGDirectDisplayID: CGRect]
    public var normalizedSlices: [CGDirectDisplayID: CGRect]
}

public final class DisplaySpanManager: @unchecked Sendable {
    public static let shared = DisplaySpanManager()

    public init() {}

    /// Computes the union bounding box and normalized contentsRect for each display.
    public func calculateSpanGeometry(screens: [NSScreen]) -> DisplaySpanGeometry {
        guard !screens.isEmpty else {
            return DisplaySpanGeometry(globalBounds: .zero, displayRects: [:], normalizedSlices: [:])
        }

        var globalUnion: CGRect = .null
        var displayRects: [CGDirectDisplayID: CGRect] = [:]

        for screen in screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }
            let frame = screen.frame
            displayRects[id] = frame
            globalUnion = globalUnion.isNull ? frame : globalUnion.union(frame)
        }

        var normalizedSlices: [CGDirectDisplayID: CGRect] = [:]
        guard globalUnion.width > 0 && globalUnion.height > 0 else {
            return DisplaySpanGeometry(globalBounds: globalUnion, displayRects: displayRects, normalizedSlices: [:])
        }

        for (id, frame) in displayRects {
            let normX = (frame.minX - globalUnion.minX) / globalUnion.width
            let normY = (frame.minY - globalUnion.minY) / globalUnion.height
            let normW = frame.width / globalUnion.width
            let normH = frame.height / globalUnion.height
            normalizedSlices[id] = CGRect(x: normX, y: normY, width: normW, height: normH)
        }

        return DisplaySpanGeometry(globalBounds: globalUnion, displayRects: displayRects, normalizedSlices: normalizedSlices)
    }

    /// Computes the normalized slice for a single display given all screen frames.
    public func normalizedContentsRect(for displayID: CGDirectDisplayID, allScreens: [CGDirectDisplayID: CGRect]) -> CGRect {
        guard !allScreens.isEmpty else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        var globalUnion: CGRect = .null
        for frame in allScreens.values {
            globalUnion = globalUnion.isNull ? frame : globalUnion.union(frame)
        }
        guard let frame = allScreens[displayID], globalUnion.width > 0, globalUnion.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let normX = (frame.minX - globalUnion.minX) / globalUnion.width
        let normY = (frame.minY - globalUnion.minY) / globalUnion.height
        let normW = frame.width / globalUnion.width
        let normH = frame.height / globalUnion.height
        return CGRect(x: normX, y: normY, width: normW, height: normH)
    }


    /// Applies the calculated normalized slice to a target CALayer using CoreAnimation zero-copy contentsRect.
    @MainActor
    public func applySpanSlice(to layer: CALayer, for displayID: CGDirectDisplayID, geometry: DisplaySpanGeometry) {
        if let slice = geometry.normalizedSlices[displayID] {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.contentsRect = slice
            CATransaction.commit()
        }
    }

    /// Resets the layer to render the entire wallpaper asset (1:1).
    @MainActor
    public func resetSpanSlice(on layer: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        CATransaction.commit()
    }
}

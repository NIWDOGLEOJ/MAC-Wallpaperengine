//
//  PlaybackState.swift
//  WallpaperEngineCore
//
//  Playback state models, pause reasons, and throttling decisions.
//

import CoreGraphics
import Foundation

/// Enumeration of reasons why video playback may be paused.
public enum PauseReason: String, Codable, Hashable, Sendable {
    case userRequested = "User Paused"
    case systemSleeping = "System Sleeping"
    case screensSleeping = "Display Sleeping"
    case screenLocked = "Screen Locked"
    case screensaverActive = "Screensaver Active"
    case sessionInactive = "Session Inactive (Fast User Switching)"
    case lowPowerMode = "Low Power Mode Enabled"
    case onBattery = "Running on Battery Power"
    case displayOccluded = "Display Fully Occluded"
    case thermalPressure = "Thermal Pressure Protection"
}

/// Enumeration of reasons why video playback frame rate may be throttled.
public enum ThrottleReason: String, Codable, Hashable, Sendable {
    case onBattery = "Battery Power Throttling"
    case thermalPressure = "Elevated Thermal State"
}

/// Dynamic playback state of an individual video player pipeline.
public enum PlaybackState: Sendable, Equatable {
    case idle
    case loading(URL)
    case playing
    case paused(reason: PauseReason)
    case throttled(fps: Int)
    case stalled(reason: String)
    case failed(VideoEngineError)
}

/// Video engine errors encountered during media preparation or playback.
public enum VideoEngineError: Error, LocalizedError, Sendable, Equatable {
    case fileNotFound(URL)
    case assetNotPlayable(URL)
    case noVideoTrack(URL)
    case unreadableFormat(String)
    case looperCreationFailed(String)
    case playbackStalled
    case displayNotFound(CGDirectDisplayID)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Video file not found at: \(url.path)"
        case .assetNotPlayable(let url):
            return "Asset is not playable: \(url.path)"
        case .noVideoTrack(let url):
            return "No video track found in: \(url.path)"
        case .unreadableFormat(let msg):
            return "Unreadable format: \(msg)"
        case .looperCreationFailed(let msg):
            return "AVPlayerLooper creation failed: \(msg)"
        case .playbackStalled:
            return "Playback stalled and failed recovery"
        case .displayNotFound(let id):
            return "Display not found for ID: \(id)"
        }
    }
}

/// Consolidated state decision produced by the state evaluator engine.
public enum PlaybackDecision: Equatable, Sendable {
    case play(fps: Int = 60)
    case pause(reasons: Set<PauseReason>)
    case throttle(fps: Int, reasons: Set<ThrottleReason>)
}

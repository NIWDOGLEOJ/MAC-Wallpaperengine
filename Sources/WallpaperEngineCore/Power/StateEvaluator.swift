//
//  StateEvaluator.swift
//  WallpaperEngineCore
//
//  Pure functional playback decision engine for power, sleep, and occlusion states.
//

import CoreGraphics
import Foundation

public struct StateEvaluator: Sendable {
    
    /// Evaluates the consolidated playback decision for a single display.
    ///
    /// - Parameters:
    ///   - manualPause: Explicit user pause state from menu bar, hotkey, or CLI.
    ///   - sleepLock: Snapshot of system sleep, display sleep, screen lock, and session activity.
    ///   - power: Snapshot of power source (AC/Battery), low power mode, and thermal state.
    ///   - isDisplayVisible: Occlusion state for the target display (true if visible).
    ///   - config: User engine configuration and throttling policies.
    /// - Returns: A deterministic `PlaybackDecision` (.play, .pause, or .throttle).
    public static func evaluate(
        manualPause: Bool,
        sleepLock: SleepLockState,
        power: PowerState,
        isDisplayVisible: Bool,
        config: EngineConfig,
        isFullscreen: Bool = false,
        isGameActive: Bool = false,
        isIdle: Bool = false,
        memoryPressure: MemoryPressureLevel = .normal
    ) -> PlaybackDecision {
        var pauseReasons = Set<PauseReason>()

        // 1. User manual override (Highest priority, unconditional)
        if manualPause || config.isPaused {
            pauseReasons.insert(.userRequested)
        }

        // 2. Sleep, Lock, Screensaver, and Session states
        if sleepLock.isSystemSleeping && config.pauseOnDisplaySleep {
            pauseReasons.insert(.systemSleeping)
        }
        if sleepLock.areScreensSleeping && config.pauseOnDisplaySleep {
            pauseReasons.insert(.screensSleeping)
        }
        if sleepLock.isScreenLocked && config.pauseOnScreenLock {
            pauseReasons.insert(.screenLocked)
        }
        if sleepLock.isScreensaverActive {
            pauseReasons.insert(.screensaverActive)
        }
        if !sleepLock.isSessionActive {
            pauseReasons.insert(.sessionInactive)
        }

        // 3. Power, Low Power Mode, and Critical Thermal states
        if power.isLowPowerModeEnabled && config.pauseOnLowPowerMode {
            pauseReasons.insert(.lowPowerMode)
        }
        if power.isOnBattery && config.pauseOnBattery {
            pauseReasons.insert(.onBattery)
        }
        if power.thermalState == .critical {
            pauseReasons.insert(.thermalPressure)
        }

        // 4. Memory Pressure Protection
        if memoryPressure == .critical {
            pauseReasons.insert(.memoryPressure)
        }

        // 5. Fullscreen App & Game Suspension
        if isFullscreen {
            pauseReasons.insert(.fullscreenApp)
        }
        if isGameActive {
            pauseReasons.insert(.gameActive)
        }

        // 6. Display Occlusion (per-display evaluation)
        if !isDisplayVisible && config.pauseWhenOccluded {
            pauseReasons.insert(.displayOccluded)
        }

        // --- Stage 1 Decision: Pause ---
        if !pauseReasons.isEmpty {
            return .pause(reasons: pauseReasons)
        }

        // --- Stage 2 Decision: Throttling ---
        var throttleReasons = Set<ThrottleReason>()

        if power.isOnBattery && config.throttleOnBattery {
            throttleReasons.insert(.onBattery)
        }
        if power.thermalState == .serious {
            throttleReasons.insert(.thermalPressure)
        }
        if isIdle {
            throttleReasons.insert(.desktopIdle)
        }

        if !throttleReasons.isEmpty {
            return .throttle(fps: config.throttledFrameRate, reasons: throttleReasons)
        }

        // --- Stage 3 Decision: Normal Playback ---
        return .play(fps: config.targetFrameRate)
    }

    /// Evaluates playback decisions for a batch of displays sharing global power and sleep state.
    public static func evaluate(
        manualPause: Bool,
        sleepLock: SleepLockState,
        power: PowerState,
        displays: [CGDirectDisplayID: Bool],
        config: EngineConfig,
        fullscreenDisplays: Set<CGDirectDisplayID> = [],
        isGameActive: Bool = false,
        isIdle: Bool = false,
        memoryPressure: MemoryPressureLevel = .normal
    ) -> [CGDirectDisplayID: PlaybackDecision] {
        var decisions: [CGDirectDisplayID: PlaybackDecision] = [:]

        for (displayID, isVisible) in displays {
            let isFs = fullscreenDisplays.contains(displayID)
            decisions[displayID] = evaluate(
                manualPause: manualPause,
                sleepLock: sleepLock,
                power: power,
                isDisplayVisible: isVisible,
                config: config,
                isFullscreen: isFs,
                isGameActive: isGameActive,
                isIdle: isIdle,
                memoryPressure: memoryPressure
            )
        }

        return decisions
    }
}

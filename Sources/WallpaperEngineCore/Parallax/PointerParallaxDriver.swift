import AppKit
import Foundation
import os
import simd

/// Tracks mouse cursor movements across the display space and applies
/// spring-damper smoothing to produce natural, fluid 3D parallax coordinates.
public final class PointerParallaxDriver: ParallaxTrackingDriver, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "PointerParallaxDriver")
    private let lock = NSLock()

    // Configuration
    public var sensitivity: Float = 1.0
    public var smoothingFactor: Float = 0.08
    public var invertX: Bool = false
    public var invertY: Bool = false

    // State
    private var _targetOffset: SIMD2<Float> = .zero
    private var _currentOffset: SIMD2<Float> = .zero
    private var isRunning: Bool = false

    private var eventMonitor: Any?
    private var updateTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.wallpaperengine.parallax.pointer", qos: .userInteractive)

    public var onOffsetUpdate: (@Sendable (SIMD2<Float>) -> Void)?

    public var currentOffset: SIMD2<Float> {
        lock.lock()
        defer { lock.unlock() }
        return _currentOffset
    }

    public init(sensitivity: Float = 1.0, smoothingFactor: Float = 0.08) {
        self.sensitivity = sensitivity
        self.smoothingFactor = smoothingFactor
    }

    deinit {
        stop()
    }

    public func start() {
        lock.lock()
        guard !isRunning else {
            lock.unlock()
            return
        }
        isRunning = true
        lock.unlock()

        logger.info("Starting PointerParallaxDriver")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.eventMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            ) { [weak self] _ in
                self?.sampleMouseLocation()
            }
        }

        startSmoothingTimer()
    }

    public func stop() {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }
        isRunning = false

        if let timer = updateTimer {
            timer.cancel()
            updateTimer = nil
        }
        lock.unlock()

        logger.info("Stopping PointerParallaxDriver")

        DispatchQueue.main.async { [weak self] in
            if let monitor = self?.eventMonitor {
                NSEvent.removeMonitor(monitor)
                self?.eventMonitor = nil
            }
        }
    }

    /// Directly inject target coordinates for testing or manual input.
    public func setTarget(x: Float, y: Float) {
        lock.lock()
        _targetOffset = SIMD2<Float>(
            max(-1.0, min(1.0, x)),
            max(-1.0, min(1.0, y))
        )
        lock.unlock()
    }

    private func sampleMouseLocation() {
        let mouseLoc = NSEvent.mouseLocation
        let mainScreen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let halfWidth = Float(max(1.0, mainScreen.width / 2.0))
        let halfHeight = Float(max(1.0, mainScreen.height / 2.0))

        var normX = (Float(mouseLoc.x - mainScreen.midX) / halfWidth) * sensitivity
        var normY = (Float(mouseLoc.y - mainScreen.midY) / halfHeight) * sensitivity

        if invertX { normX = -normX }
        if invertY { normY = -normY }

        lock.lock()
        _targetOffset = SIMD2<Float>(
            max(-1.0, min(1.0, normX)),
            max(-1.0, min(1.0, normY))
        )
        lock.unlock()
    }

    private func startSmoothingTimer() {
        let timer = DispatchSource.makeTimerSource(flags: [], queue: timerQueue)
        // Run at 60 Hz for fluid interpolation
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            self?.tickSmoothing()
        }
        updateTimer = timer
        timer.resume()
    }

    private func tickSmoothing() {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }

        let delta = _targetOffset - _currentOffset
        if simd_length(delta) > 0.0005 {
            _currentOffset += delta * smoothingFactor
            let offsetToSend = _currentOffset
            let callback = onOffsetUpdate
            lock.unlock()
            callback?(offsetToSend)
        } else {
            lock.unlock()
        }
    }
}

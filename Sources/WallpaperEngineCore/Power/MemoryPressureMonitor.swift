//
//  MemoryPressureMonitor.swift
//  WallpaperEngineCore
//
//  Feature: Native Darwin DISPATCH_SOURCE_TYPE_MEMORYPRESSURE listener.
//  Monitors OS memory pressure levels and triggers cache trimming and asset release.
//

import Darwin
import Foundation
import OSLog

public enum MemoryPressureLevel: String, Sendable, Equatable {
    case normal = "Normal"
    case warning = "Warning"
    case critical = "Critical"
}

@MainActor
public protocol MemoryPressureDelegate: AnyObject {
    func memoryPressureDidChange(to level: MemoryPressureLevel)
}

public final class MemoryPressureMonitor: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "MemoryPressure")
    private let lock = NSLock()
    private var source: DispatchSourceMemoryPressure?
    private let queue = DispatchQueue(label: "com.wallpaperengine.memorypressure", qos: .utility)
    
    public private(set) var currentLevel: MemoryPressureLevel = .normal
    public weak var delegate: MemoryPressureDelegate?
    public var onPressureChange: (@Sendable (MemoryPressureLevel) -> Void)?

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        lock.lock()
        guard source == nil else {
            lock.unlock()
            return
        }

        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical, .normal],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = source.data
            let level: MemoryPressureLevel
            if event.contains(.critical) {
                level = .critical
            } else if event.contains(.warning) {
                level = .warning
            } else {
                level = .normal
            }

            self.lock.lock()
            let previous = self.currentLevel
            self.currentLevel = level
            self.lock.unlock()

            if previous != level {
                self.logger.notice("Memory pressure changed to \(level.rawValue)")
                self.onPressureChange?(level)
                Task { @MainActor [weak self] in
                    self?.delegate?.memoryPressureDidChange(to: level)
                }
            }
        }

        source.resume()
        self.source = source
        lock.unlock()
        logger.info("MemoryPressureMonitor started.")
    }

    public func stop() {
        lock.lock()
        guard let s = source else {
            lock.unlock()
            return
        }
        s.cancel()
        self.source = nil
        currentLevel = .normal
        lock.unlock()
        logger.info("MemoryPressureMonitor stopped.")
    }

    /// For testing purposes: manually simulate a memory pressure event.
    public func simulatePressureChange(to level: MemoryPressureLevel) {
        lock.lock()
        let previous = currentLevel
        currentLevel = level
        lock.unlock()

        if previous != level {
            logger.notice("Simulated memory pressure: \(level.rawValue)")
            onPressureChange?(level)
            Task { @MainActor [weak self] in
                self?.delegate?.memoryPressureDidChange(to: level)
            }
        }
    }
}

//
//  EngineConfig.swift
//  WallpaperEngineCore
//
//  Configuration, throttling preferences, display settings, and persistence manager.
//

import Foundation
import OSLog

// MARK: - Logging Subsystem

public enum EngineLogger {
    public static let config = Logger(subsystem: "com.wallpaperengine.core", category: "Config")
    public static let coordinator = Logger(subsystem: "com.wallpaperengine.core", category: "AppCoordinator")
    public static let menuBar = Logger(subsystem: "com.wallpaperengine.core", category: "MenuBar")
}

// MARK: - Engine Configuration Model

public struct EngineConfig: Codable, Equatable, Sendable {
    public var version: Int
    public var isPaused: Bool
    public var targetFrameRate: Int
    public var throttledFrameRate: Int

    // Throttling and Power Toggles
    public var pauseOnBattery: Bool
    public var throttleOnBattery: Bool
    public var pauseOnLowPowerMode: Bool
    public var pauseOnScreenLock: Bool
    public var pauseOnDisplaySleep: Bool
    public var pauseWhenOccluded: Bool

    // Global Media Settings
    public var isMuted: Bool
    public var hardwareDecodingEnabled: Bool
    public var defaultAssetPath: String?

    // Per-display configurations (Key: Display Identifier UUID or CGDirectDisplayID string)
    public var displayConfigurations: [String: DisplayConfig]

    public static let `default` = EngineConfig()

    public init(
        version: Int = 1,
        isPaused: Bool = false,
        targetFrameRate: Int = 60,
        throttledFrameRate: Int = 30,
        pauseOnBattery: Bool = false,
        throttleOnBattery: Bool = true,
        pauseOnLowPowerMode: Bool = true,
        pauseOnScreenLock: Bool = true,
        pauseOnDisplaySleep: Bool = true,
        pauseWhenOccluded: Bool = true,
        isMuted: Bool = true,
        hardwareDecodingEnabled: Bool = true,
        defaultAssetPath: String? = nil,
        displayConfigurations: [String: DisplayConfig] = [:]
    ) {
        self.version = version
        self.isPaused = isPaused
        let sanitizedTarget = max(1, targetFrameRate)
        self.targetFrameRate = sanitizedTarget
        self.throttledFrameRate = max(1, min(throttledFrameRate, sanitizedTarget))
        self.pauseOnBattery = pauseOnBattery
        self.throttleOnBattery = throttleOnBattery
        self.pauseOnLowPowerMode = pauseOnLowPowerMode
        self.pauseOnScreenLock = pauseOnScreenLock
        self.pauseOnDisplaySleep = pauseOnDisplaySleep
        self.pauseWhenOccluded = pauseWhenOccluded
        self.isMuted = isMuted
        self.hardwareDecodingEnabled = hardwareDecodingEnabled
        self.defaultAssetPath = defaultAssetPath
        self.displayConfigurations = displayConfigurations
    }

    public struct DisplayConfig: Codable, Equatable, Sendable {
        public var assetPath: String?
        public var scalingMode: ScalingMode
        public var isEnabled: Bool
        public var isMuted: Bool

        public enum ScalingMode: String, Codable, Sendable {
            case aspectFill
            case aspectFit
            case resize
        }

        public init(
            assetPath: String? = nil,
            scalingMode: ScalingMode = .aspectFill,
            isEnabled: Bool = true,
            isMuted: Bool = true
        ) {
            self.assetPath = assetPath
            self.scalingMode = scalingMode
            self.isEnabled = isEnabled
            self.isMuted = isMuted
        }
    }
}

public typealias DisplayConfig = EngineConfig.DisplayConfig

// MARK: - Configuration Persistence Protocols & Implementations

public protocol ConfigPersistenceProtocol: Sendable {
    var configURL: URL { get }
    func load() -> EngineConfig
    func save(_ config: EngineConfig) throws
}

public protocol ConfigStorageProtocol: AnyObject, Sendable {
    func load() -> EngineConfig?
    func save(_ config: EngineConfig) throws
}

/// Robust JSON configuration persistence manager with atomic file writes and resilient fallbacks.
public final class ConfigPersistenceManager: ConfigPersistenceProtocol, @unchecked Sendable {
    public let configURL: URL
    private let fileManager: FileManager

    public static var defaultConfigDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("WallpaperEngineCore", isDirectory: true)
    }

    public static var defaultConfigURL: URL {
        return defaultConfigDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    }

    public init(configURL: URL? = nil, fileManager: FileManager = .default) {
        self.configURL = configURL ?? Self.defaultConfigURL
        self.fileManager = fileManager
    }

    /// Loads configuration from disk, falling back gracefully to `EngineConfig.default` if missing, empty, or corrupted.
    public func load() -> EngineConfig {
        guard fileManager.fileExists(atPath: configURL.path) else {
            EngineLogger.config.debug("No config file found at \(self.configURL.path). Using EngineConfig.default.")
            return EngineConfig.default
        }

        do {
            let data = try Data(contentsOf: configURL)
            guard !data.isEmpty else {
                EngineLogger.config.warning("Config file at \(self.configURL.path) is empty. Falling back to EngineConfig.default.")
                return EngineConfig.default
            }
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(EngineConfig.self, from: data)
            EngineLogger.config.info("Successfully loaded EngineConfig from \(self.configURL.path).")
            return decoded
        } catch {
            EngineLogger.config.warning("Failed to decode config at \(self.configURL.path): \(error.localizedDescription). Falling back to EngineConfig.default.")
            return EngineConfig.default
        }
    }

    /// Saves configuration to disk atomically, auto-creating directory tree if missing.
    public func save(_ config: EngineConfig) throws {
        let dirURL = configURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dirURL.path) {
            try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
        EngineLogger.config.info("Successfully saved EngineConfig atomically to \(self.configURL.path).")
    }
}

/// File storage adaptor conforming to ConfigStorageProtocol.
public final class FileConfigStorage: ConfigStorageProtocol, @unchecked Sendable {
    public let persistenceManager: ConfigPersistenceManager

    public var fileURL: URL {
        persistenceManager.configURL
    }

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.persistenceManager = ConfigPersistenceManager(configURL: fileURL, fileManager: fileManager)
    }

    public func load() -> EngineConfig? {
        guard FileManager.default.fileExists(atPath: persistenceManager.configURL.path) else {
            return nil
        }
        return persistenceManager.load()
    }

    public func save(_ config: EngineConfig) throws {
        try persistenceManager.save(config)
    }
}

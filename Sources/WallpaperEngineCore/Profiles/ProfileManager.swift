//
//  ProfileManager.swift
//  WallpaperEngineCore
//
//  Feature 14: Saved wallpaper & performance profiles and presets.
//  Supports Work, Gaming, Battery Saver, Night, Entertainment, and Custom configurations.
//

import Foundation
import OSLog

public enum EngineProfileType: String, Codable, CaseIterable, Sendable {
    case work = "Work"
    case gaming = "Gaming"
    case batterySaver = "Battery Saver"
    case night = "Night"
    case entertainment = "Entertainment"
    case custom = "Custom"
}

public struct EngineProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var type: EngineProfileType
    public var targetFrameRate: Int
    public var throttledFrameRate: Int
    public var pauseOnBattery: Bool
    public var throttleOnBattery: Bool
    public var pauseOnFullscreen: Bool
    public var pauseOnGame: Bool
    public var isAudioReactive: Bool
    public var useCPUOnlyEngine: Bool
    public var showHUD: Bool
    public var preferredShader: String?
    public var description: String

    public init(
        id: UUID = UUID(),
        name: String,
        type: EngineProfileType,
        targetFrameRate: Int = 60,
        throttledFrameRate: Int = 30,
        pauseOnBattery: Bool = false,
        throttleOnBattery: Bool = true,
        pauseOnFullscreen: Bool = true,
        pauseOnGame: Bool = true,
        isAudioReactive: Bool = true,
        useCPUOnlyEngine: Bool = false,
        showHUD: Bool = true,
        preferredShader: String? = nil,
        description: String = ""
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.targetFrameRate = targetFrameRate
        self.throttledFrameRate = throttledFrameRate
        self.pauseOnBattery = pauseOnBattery
        self.throttleOnBattery = throttleOnBattery
        self.pauseOnFullscreen = pauseOnFullscreen
        self.pauseOnGame = pauseOnGame
        self.isAudioReactive = isAudioReactive
        self.useCPUOnlyEngine = useCPUOnlyEngine
        self.showHUD = showHUD
        self.preferredShader = preferredShader
        self.description = description
    }

    public static let standardProfiles: [EngineProfile] = [
        EngineProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Work & Productivity",
            type: .work,
            targetFrameRate: 30,
            throttledFrameRate: 15,
            pauseOnBattery: true,
            throttleOnBattery: true,
            pauseOnFullscreen: true,
            pauseOnGame: true,
            isAudioReactive: false,
            useCPUOnlyEngine: true,
            showHUD: true,
            preferredShader: "gradientFlow",
            description: "Low-overhead ambient gradient with productivity clock and date. Pauses on battery to maximize work longevity."
        ),
        EngineProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Gaming & Performance",
            type: .gaming,
            targetFrameRate: 60,
            throttledFrameRate: 20,
            pauseOnBattery: true,
            throttleOnBattery: true,
            pauseOnFullscreen: true,
            pauseOnGame: true,
            isAudioReactive: false,
            useCPUOnlyEngine: true,
            showHUD: false,
            description: "Zero interference with games. Suspends rendering immediately when 3D titles or full-screen apps launch."
        ),
        EngineProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Battery Saver",
            type: .batterySaver,
            targetFrameRate: 24,
            throttledFrameRate: 12,
            pauseOnBattery: true,
            throttleOnBattery: true,
            pauseOnFullscreen: true,
            pauseOnGame: true,
            isAudioReactive: false,
            useCPUOnlyEngine: true,
            showHUD: false,
            description: "Maximum energy conservation with minimal CPU ticks and CPU-only live wallpaper."
        ),
        EngineProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: "Night Mode",
            type: .night,
            targetFrameRate: 45,
            throttledFrameRate: 24,
            pauseOnBattery: false,
            throttleOnBattery: true,
            pauseOnFullscreen: true,
            pauseOnGame: true,
            isAudioReactive: false,
            useCPUOnlyEngine: false,
            showHUD: true,
            preferredShader: "starfield",
            description: "Subdued deep starfield and dark theme for low-light environments."
        ),
        EngineProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            name: "Entertainment & Audiophile",
            type: .entertainment,
            targetFrameRate: 60,
            throttledFrameRate: 30,
            pauseOnBattery: false,
            throttleOnBattery: true,
            pauseOnFullscreen: false,
            pauseOnGame: false,
            isAudioReactive: true,
            useCPUOnlyEngine: false,
            showHUD: true,
            preferredShader: "aurora",
            description: "Full visual fidelity with real-time 16-band audio spectrum analyzer and music card."
        )
    ]
}

@MainActor
public final class ProfileManager: ObservableObject {
    @Published public private(set) var profiles: [EngineProfile] = EngineProfile.standardProfiles
    @Published public private(set) var activeProfile: EngineProfile = EngineProfile.standardProfiles[0]

    private let persistenceURL: URL
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "ProfileManager")

    public init(persistenceURL: URL? = nil) {
        if let url = persistenceURL {
            self.persistenceURL = url
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let dir = appSupport.appendingPathComponent("WallpaperEngineCore", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.persistenceURL = dir.appendingPathComponent("profiles.json")
        }
        loadFromDisk()
    }

    public func selectProfile(_ profile: EngineProfile, applyTo config: inout EngineConfig) {
        self.activeProfile = profile
        config.targetFrameRate = profile.targetFrameRate
        config.throttledFrameRate = profile.throttledFrameRate
        config.pauseOnBattery = profile.pauseOnBattery
        config.throttleOnBattery = profile.throttleOnBattery
        config.isAudioReactive = profile.isAudioReactive
        config.useCPUOnlyEngine = profile.useCPUOnlyEngine
        config.hudConfig.isEnabled = profile.showHUD
        if let sh = profile.preferredShader {
            config.shaderName = sh
        }
        logger.info("Applied profile: \(profile.name)")
        saveToDisk()
    }

    public func applyProfile(_ profile: EngineProfile, to config: inout EngineConfig) {
        selectProfile(profile, applyTo: &config)
    }


    public func addCustomProfile(_ profile: EngineProfile) {
        profiles.append(profile)
        saveToDisk()
    }

    public func removeProfile(id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        // Prevent deleting built-in standard profiles
        guard profile.type == .custom else {
            logger.warning("Cannot delete built-in profile: \(profile.name)")
            return
        }
        profiles.removeAll(where: { $0.id == id })
        saveToDisk()
    }

    public func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            logger.error("Failed to save profiles: \(error.localizedDescription)")
        }
    }

    public func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path),
              let data = try? Data(contentsOf: persistenceURL),
              let list = try? JSONDecoder().decode([EngineProfile].self, from: data),
              !list.isEmpty else {
            return
        }
        var merged = EngineProfile.standardProfiles
        let customProfiles = list.filter { $0.type == .custom }
        merged.append(contentsOf: customProfiles)
        self.profiles = merged
        if let first = merged.first {
            self.activeProfile = first
        }
    }
}

//
//  MotionBGsFavoritesManager.swift
//  WallpaperEngineCore
//
//  Persisted storage for MotionBGs favorites and recently viewed wallpapers.
//  Operates completely offline with zero network dependency.
//

import Foundation
import OSLog

public struct DiscoverPersistentData: Codable, Sendable {
    public var favorites: [MotionBGsWallpaper]
    public var recents: [MotionBGsWallpaper]

    public init(favorites: [MotionBGsWallpaper] = [], recents: [MotionBGsWallpaper] = []) {
        self.favorites = favorites
        self.recents = recents
    }
}

@MainActor
public final class MotionBGsFavoritesManager: ObservableObject {
    public static let shared = MotionBGsFavoritesManager()

    @Published public private(set) var favorites: [MotionBGsWallpaper] = []
    @Published public private(set) var recents: [MotionBGsWallpaper] = []

    private let fileURL: URL
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "MotionBGsFavoritesManager")

    public init(storageURL: URL? = nil) {
        if let url = storageURL {
            self.fileURL = url
        } else {
            let appSupport = ConfigPersistenceManager.defaultConfigDirectoryURL
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            self.fileURL = appSupport.appendingPathComponent("discover_favorites.json")
        }
        loadFromDisk()
    }

    public func isFavorite(id: String) -> Bool {
        favorites.contains(where: { $0.id == id })
    }

    public func toggleFavorite(wallpaper: MotionBGsWallpaper) {
        var item = wallpaper
        if let index = favorites.firstIndex(where: { $0.id == item.id }) {
            favorites.remove(at: index)
        } else {
            item.isFavorite = true
            favorites.insert(item, at: 0)
        }
        saveToDisk()
    }

    public func recordRecent(wallpaper: MotionBGsWallpaper) {
        var item = wallpaper
        item.lastViewed = Date()
        recents.removeAll(where: { $0.id == item.id })
        recents.insert(item, at: 0)
        if recents.count > 40 {
            recents.removeLast()
        }
        saveToDisk()
    }

    public func clearRecents() {
        recents.removeAll()
        saveToDisk()
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(DiscoverPersistentData.self, from: data)
            self.favorites = decoded.favorites
            self.recents = decoded.recents
        } catch {
            logger.error("Failed to decode discover_favorites.json: \(error.localizedDescription)")
        }
    }

    private func saveToDisk() {
        let payload = DiscoverPersistentData(favorites: favorites, recents: recents)
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save discover_favorites.json: \(error.localizedDescription)")
        }
    }
}

//
//  WallpaperPlaylistManager.swift
//  WallpaperEngineCore
//
//  Feature 6: Efficient event-driven wallpaper playlist and scheduler engine.
//  Wakes only when the next scheduled change is due; strictly 0% polling overhead.
//

import CoreGraphics
import Foundation
import OSLog

public enum PlaylistOrder: String, Codable, Sendable, CaseIterable {
    case sequential = "Sequential"
    case shuffle = "Shuffle"
}

public struct PlaylistItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var url: URL
    public var title: String
    public var durationSeconds: TimeInterval?
    public var isFavorite: Bool

    public init(id: UUID = UUID(), url: URL, title: String, durationSeconds: TimeInterval? = nil, isFavorite: Bool = false) {
        self.id = id
        self.url = url
        self.title = title
        self.durationSeconds = durationSeconds
        self.isFavorite = isFavorite
    }
}

public struct WallpaperPlaylist: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var items: [PlaylistItem]
    public var order: PlaylistOrder
    public var intervalSeconds: TimeInterval
    public var isEnabled: Bool
    public var targetDisplayID: CGDirectDisplayID?
    public var onlyFavorites: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        items: [PlaylistItem] = [],
        order: PlaylistOrder = .sequential,
        intervalSeconds: TimeInterval = 300,
        isEnabled: Bool = true,
        targetDisplayID: CGDirectDisplayID? = nil,
        onlyFavorites: Bool = false
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.order = order
        self.intervalSeconds = max(5, intervalSeconds)
        self.isEnabled = isEnabled
        self.targetDisplayID = targetDisplayID
        self.onlyFavorites = onlyFavorites
    }
}

public enum TimeOfDayProfile: String, Codable, CaseIterable, Sendable {
    case morning = "Morning (06:00 - 12:00)"
    case afternoon = "Afternoon (12:00 - 18:00)"
    case evening = "Evening (18:00 - 22:00)"
    case night = "Night (22:00 - 06:00)"

    public static func current() -> TimeOfDayProfile {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<12: return .morning
        case 12..<18: return .afternoon
        case 18..<22: return .evening
        default: return .night
        }
    }
}

@MainActor
public protocol WallpaperPlaylistDelegate: AnyObject {
    func playlistManager(_ manager: WallpaperPlaylistManager, didRequestSwitchTo item: PlaylistItem, for displayID: CGDirectDisplayID?)
}

@MainActor
public final class WallpaperPlaylistManager: ObservableObject {
    @Published public private(set) var playlists: [WallpaperPlaylist] = []
    @Published public private(set) var activePlaylistID: UUID?
    @Published public private(set) var currentIndex: Int = 0
    @Published public private(set) var isRunning: Bool = false

    public weak var delegate: WallpaperPlaylistDelegate?

    private var scheduleTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.wallpaperengine.playlist", qos: .utility)
    private let persistenceURL: URL
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "PlaylistManager")

    public init(persistenceURL: URL? = nil) {
        if let url = persistenceURL {
            self.persistenceURL = url
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let dir = appSupport.appendingPathComponent("WallpaperEngineCore", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.persistenceURL = dir.appendingPathComponent("playlists.json")
        }
        loadFromDisk()
    }

    public func addPlaylist(_ playlist: WallpaperPlaylist) {
        playlists.append(playlist)
        saveToDisk()
    }

    public func createPlaylist(_ playlist: WallpaperPlaylist) {
        addPlaylist(playlist)
    }

    public func removePlaylist(id: UUID) {
        if activePlaylistID == id {
            stop()
            activePlaylistID = nil
        }
        playlists.removeAll(where: { $0.id == id })
        saveToDisk()
    }

    public func startPlaylist(id: UUID) {
        guard let playlist = playlists.first(where: { $0.id == id }), !playlist.items.isEmpty else {
            logger.warning("Cannot start empty or nonexistent playlist \(id)")
            return
        }
        stop()
        activePlaylistID = id
        currentIndex = 0
        isRunning = true

        // Immediately trigger first item
        applyCurrentItem()
        scheduleNextTransition()
        saveToDisk()
    }

    public func start(playlistID: UUID) {
        startPlaylist(id: playlistID)
    }

    public func stop() {
        scheduleTimer?.cancel()
        scheduleTimer = nil
        isRunning = false
    }

    public func pause() {
        guard isRunning else { return }
        scheduleTimer?.cancel()
        scheduleTimer = nil
        isRunning = false
        saveToDisk()
        logger.info("Playlist paused at index \(self.currentIndex)")
    }

    public func resume() {
        guard !isRunning, let _ = activePlaylist, !effectiveItems.isEmpty else { return }
        isRunning = true
        scheduleNextTransition()
        logger.info("Playlist resumed at index \(self.currentIndex)")
    }

    public var effectiveItems: [PlaylistItem] {
        guard let playlist = activePlaylist else { return [] }
        if playlist.onlyFavorites {
            let favs = playlist.items.filter { $0.isFavorite }
            return favs.isEmpty ? playlist.items : favs
        }
        return playlist.items
    }

    public func next() {
        guard let playlist = activePlaylist else { return }
        advanceIndex(order: playlist.order)
        applyCurrentItem()
        scheduleNextTransition()
    }

    @discardableResult
    public func nextItem() -> PlaylistItem? {
        next()
        let items = effectiveItems
        guard currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    public func previous() {
        let items = effectiveItems
        guard !items.isEmpty else { return }
        currentIndex = (currentIndex - 1 + items.count) % items.count
        applyCurrentItem()
        scheduleNextTransition()
        saveToDisk()
    }

    public var activePlaylist: WallpaperPlaylist? {
        guard let id = activePlaylistID else { return nil }
        return playlists.first(where: { $0.id == id })
    }

    private func advanceIndex(order: PlaylistOrder) {
        let items = effectiveItems
        guard !items.isEmpty else { return }
        switch order {
        case .sequential:
            currentIndex = (currentIndex + 1) % items.count
        case .shuffle:
            if items.count > 1 {
                var nextIdx = Int.random(in: 0..<items.count)
                while nextIdx == currentIndex {
                    nextIdx = Int.random(in: 0..<items.count)
                }
                currentIndex = nextIdx
            }
        }
        saveToDisk()
    }

    private func applyCurrentItem() {
        let items = effectiveItems
        guard items.indices.contains(currentIndex) else { return }
        let item = items[currentIndex]
        logger.info("Playlist switching to item \(item.title) for display: \(String(describing: self.activePlaylist?.targetDisplayID))")
        delegate?.playlistManager(self, didRequestSwitchTo: item, for: self.activePlaylist?.targetDisplayID)
    }

    private func scheduleNextTransition() {
        scheduleTimer?.cancel()
        scheduleTimer = nil
        let items = effectiveItems
        guard isRunning, let playlist = activePlaylist, !items.isEmpty else { return }

        let safeIndex = min(currentIndex, items.count - 1)
        let item = items[safeIndex]
        let interval = item.durationSeconds ?? playlist.intervalSeconds

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                self.advanceIndex(order: playlist.order)
                self.applyCurrentItem()
                self.scheduleNextTransition()
            }
        }
        timer.resume()
        self.scheduleTimer = timer
    }

    // MARK: - Persistence

    private struct PlaylistStateSnapshot: Codable {
        var playlists: [WallpaperPlaylist]
        var activePlaylistID: UUID?
        var currentIndex: Int
    }

    public func saveToDisk() {
        do {
            let snapshot = PlaylistStateSnapshot(
                playlists: playlists,
                activePlaylistID: activePlaylistID,
                currentIndex: currentIndex
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            logger.error("Failed to save playlists: \(error.localizedDescription)")
        }
    }

    public func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path),
              let data = try? Data(contentsOf: persistenceURL) else {
            return
        }
        if let snapshot = try? JSONDecoder().decode(PlaylistStateSnapshot.self, from: data) {
            self.playlists = snapshot.playlists
            self.activePlaylistID = snapshot.activePlaylistID
            self.currentIndex = snapshot.currentIndex
        } else if let list = try? JSONDecoder().decode([WallpaperPlaylist].self, from: data) {
            self.playlists = list
        }
    }
}

//
//  MotionBGsModel.swift
//  WallpaperEngineCore
//
//  Data models for MotionBGs online wallpaper discovery, search, and metadata.
//

import Foundation

public struct MotionBGsWallpaper: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let slug: String
    public let thumbnailURL: URL
    public var previewVideoURL: URL?
    public let resolution: String
    public var download4KURL: URL?
    public var downloadHDURL: URL?
    public let pageURL: URL
    public var tags: [String]
    public var width: Int?
    public var height: Int?
    public var durationSeconds: Double?
    public var fileSizeBytes: Int64?
    public var creator: String?
    public var isFavorite: Bool
    public var lastViewed: Date?

    public var resolutionFormatted: String {
        if let w = width, let h = height, w > 0 && h > 0 {
            return "\(w) × \(h) (\(resolution))"
        }
        return resolution == "4K" ? "3840 × 2160 (4K)" : "1920 × 1080 (Full HD)"
    }

    public var fileSizeFormatted: String {
        guard let bytes = fileSizeBytes, bytes > 0 else {
            return resolution == "4K" ? "~25-45 MB" : "~8-15 MB"
        }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }

    public init(
        id: String,
        title: String,
        slug: String,
        thumbnailURL: URL,
        previewVideoURL: URL? = nil,
        resolution: String = "4K",
        download4KURL: URL? = nil,
        downloadHDURL: URL? = nil,
        pageURL: URL,
        tags: [String] = [],
        width: Int? = nil,
        height: Int? = nil,
        durationSeconds: Double? = nil,
        fileSizeBytes: Int64? = nil,
        creator: String? = nil,
        isFavorite: Bool = false,
        lastViewed: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.slug = slug
        self.thumbnailURL = thumbnailURL
        self.previewVideoURL = previewVideoURL
        self.resolution = resolution
        self.download4KURL = download4KURL
        self.downloadHDURL = downloadHDURL
        self.pageURL = pageURL
        self.tags = tags
        self.width = width
        self.height = height
        self.durationSeconds = durationSeconds
        self.fileSizeBytes = fileSizeBytes
        self.creator = creator
        self.isFavorite = isFavorite
        self.lastViewed = lastViewed
    }
}

public enum MotionBGsCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case fourK = "4K Wallpapers"
    case anime = "Anime"
    case games = "Games"
    case cyberpunk = "Cyberpunk"
    case nature = "Nature"
    case cars = "Cars"
    case tv = "TV & Movies"
    case space = "Space"
    case superhero = "Superhero"
    case fantasy = "Fantasy"
    case technology = "Technology"
    case japan = "Japan"

    public var id: String { rawValue }

    public var pathComponent: String {
        switch self {
        case .all: return ""
        case .fourK: return "4k"
        case .anime: return "tag:anime"
        case .games: return "tag:games"
        case .cyberpunk: return "tag:cyberpunk"
        case .nature: return "tag:nature"
        case .cars: return "tag:car"
        case .tv: return "tag:tv"
        case .space: return "tag:space"
        case .superhero: return "tag:superhero"
        case .fantasy: return "tag:fantasy"
        case .technology: return "tag:technology"
        case .japan: return "tag:japan"
        }
    }

    public var iconName: String {
        switch self {
        case .all: return "sparkles"
        case .fourK: return "tv.fill"
        case .anime: return "wand.and.stars"
        case .games: return "gamecontroller.fill"
        case .cyberpunk: return "cpu"
        case .nature: return "leaf.fill"
        case .cars: return "car.fill"
        case .tv: return "film.fill"
        case .space: return "moon.stars.fill"
        case .superhero: return "shield.fill"
        case .fantasy: return "flame.fill"
        case .technology: return "laptopcomputer"
        case .japan: return "sun.max.fill"
        }
    }
}

public enum DiscoverFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "Explore"
    case favorites = "Favorites"
    case recents = "Recently Viewed"

    public var id: String { rawValue }
}

public enum WallpaperDownloadResolution: String, CaseIterable, Identifiable, Sendable {
    case fourK = "4K UHD (2160p)"
    case hd = "Full HD (1080p)"

    public var id: String { rawValue }
}

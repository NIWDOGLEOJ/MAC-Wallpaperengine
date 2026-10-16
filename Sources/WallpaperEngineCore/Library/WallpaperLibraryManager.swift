//
//  WallpaperLibraryManager.swift
//  WallpaperEngineCore
//
//  Feature 5: Fast, searchable local wallpaper library with metadata extraction,
//  duplicate detection, missing-file auditing, and lazy thumbnail generation.
//

import AVFoundation
import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import OSLog

public enum LibraryWallpaperType: String, Codable, CaseIterable, Sendable {
    case staticImage = "Image"
    case video = "Video"
    case shader = "Shader"
    case parallax = "3D Parallax"
    case web = "Web"
    case particle = "Particles"
}

public struct WallpaperLibraryItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL
    public var type: LibraryWallpaperType
    public var width: Int
    public var height: Int
    public var fileSizeBytes: Int64
    public var dateAdded: Date
    public var isFavorite: Bool
    public var tags: [String]
    public var category: String
    public var sha256: String?

    public var resolutionFormatted: String {
        guard width > 0 && height > 0 else { return "Dynamic" }
        return "\(width) × \(height)"
    }

    public var fileSizeFormatted: String {
        guard fileSizeBytes > 0 else { return "--" }
        let mb = Double(fileSizeBytes) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }

    public var aspectRatioFormatted: String {
        guard width > 0 && height > 0 else { return "Adaptive" }
        let gcdVal = gcd(width, height)
        return "\(width / gcdVal):\(height / gcdVal)"
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a, y = b
        while y != 0 {
            let t = y
            y = x % y
            x = t
        }
        return max(1, abs(x))
    }

    public init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        type: LibraryWallpaperType,
        width: Int = 0,
        height: Int = 0,
        fileSizeBytes: Int64 = 0,
        dateAdded: Date = Date(),
        isFavorite: Bool = false,
        tags: [String] = [],
        category: String = "General",
        sha256: String? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.type = type
        self.width = width
        self.height = height
        self.fileSizeBytes = fileSizeBytes
        self.dateAdded = dateAdded
        self.isFavorite = isFavorite
        self.tags = tags
        self.category = category
        self.sha256 = sha256
    }
}

@MainActor
public final class WallpaperLibraryManager: ObservableObject {
    @Published public private(set) var items: [WallpaperLibraryItem] = []
    @Published public private(set) var recentIDs: [UUID] = []

    private let persistenceURL: URL
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "LibraryManager")
    public let thumbnailCache: WallpaperThumbnailCache

    public init(
        persistenceURL: URL? = nil,
        thumbnailCache: WallpaperThumbnailCache = .shared
    ) {
        self.thumbnailCache = thumbnailCache
        if let url = persistenceURL {
            self.persistenceURL = url
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let dir = appSupport.appendingPathComponent("WallpaperEngineCore", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.persistenceURL = dir.appendingPathComponent("library.json")
        }
        loadFromDisk()
    }

    // MARK: - Import Operations

    public func importWallpaper(from url: URL, type: LibraryWallpaperType? = nil, tags: [String] = [], category: String = "General") async throws -> WallpaperLibraryItem {
        let detectedType = type ?? detectType(for: url)
        let (width, height, size, hash) = try await extractMetadata(for: url, type: detectedType)

        // Check for existing duplicate by URL
        if let existing = items.first(where: { $0.url == url }) {
            return existing
        }

        let title = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized

        let item = WallpaperLibraryItem(
            title: title,
            url: url,
            type: detectedType,
            width: width,
            height: height,
            fileSizeBytes: size,
            dateAdded: Date(),
            tags: tags,
            category: category,
            sha256: hash
        )

        items.append(item)
        saveToDisk()
        return item
    }

    public func scanDirectory(at directoryURL: URL) async -> [WallpaperLibraryItem] {
        var imported: [WallpaperLibraryItem] = []
        var fileURLs: [URL] = []
        if let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            while let fileURL = enumerator.nextObject() as? URL {
                fileURLs.append(fileURL)
            }
        }

        for fileURL in fileURLs {
            let ext = fileURL.pathExtension.lowercased()
            if ["png", "jpg", "jpeg", "heic", "webp", "mp4", "mov", "m4v", "html"].contains(ext) {
                if let item = try? await importWallpaper(from: fileURL) {
                    imported.append(item)
                }
            }
        }
        return imported
    }


    public func removeItem(id: UUID) {
        items.removeAll(where: { $0.id == id })
        recentIDs.removeAll(where: { $0 == id })
        saveToDisk()
    }

    public func toggleFavorite(id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isFavorite.toggle()
            saveToDisk()
        }
    }

    public func recordRecent(id: UUID) {
        recentIDs.removeAll(where: { $0 == id })
        recentIDs.insert(id, at: 0)
        if recentIDs.count > 20 {
            recentIDs.removeLast()
        }
        saveToDisk()
    }

    // MARK: - Search & Filtering

    public func search(
        query: String = "",
        tag: String? = nil,
        category: String? = nil,
        onlyFavorites: Bool = false
    ) -> [WallpaperLibraryItem] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            if !clean.isEmpty {
                let matchesTitle = item.title.lowercased().contains(clean)
                let matchesCategory = item.category.lowercased().contains(clean)
                let matchesTags = item.tags.contains(where: { $0.lowercased().contains(clean) })
                if !matchesTitle && !matchesCategory && !matchesTags {
                    return false
                }
            }
            if let tag = tag, !tag.isEmpty {
                if !item.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                    return false
                }
            }
            if let category = category, !category.isEmpty {
                if item.category.caseInsensitiveCompare(category) != .orderedSame {
                    return false
                }
            }
            if onlyFavorites && !item.isFavorite {
                return false
            }
            return true
        }
    }

    public func filter(by type: LibraryWallpaperType? = nil, category: String? = nil, onlyFavorites: Bool = false) -> [WallpaperLibraryItem] {
        items.filter { item in
            if let t = type, item.type != t { return false }
            if let c = category, item.category != c { return false }
            if onlyFavorites && !item.isFavorite { return false }
            return true
        }
    }

    // MARK: - Auditing: Duplicate & Missing Files

    public func detectDuplicates() -> [String: [WallpaperLibraryItem]] {
        var groups: [String: [WallpaperLibraryItem]] = [:]
        for item in items {
            let key = item.sha256 ?? "\(item.fileSizeBytes)_\(item.width)x\(item.height)"
            groups[key, default: []].append(item)
        }
        return groups.filter { $0.value.count > 1 }
    }

    public func detectMissingFiles() -> [WallpaperLibraryItem] {
        items.filter { !FileManager.default.fileExists(atPath: $0.url.path) }
    }

    public func auditMissingFiles() -> [WallpaperLibraryItem] {
        detectMissingFiles()
    }

    // MARK: - Metadata Extraction

    private func detectType(for url: URL) -> LibraryWallpaperType {
        let ext = url.pathExtension.lowercased()
        if ["mp4", "mov", "m4v"].contains(ext) { return .video }
        if ["html", "htm"].contains(ext) { return .web }
        if ["metal", "frag", "glsl"].contains(ext) { return .shader }
        return .staticImage
    }

    private func extractMetadata(for url: URL, type: LibraryWallpaperType) async throws -> (width: Int, height: Int, size: Int64, sha256: String?) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? Int64) ?? 0

        // Memory-bounded streaming SHA-256 for duplicate detection
        let hash: String? = await Task.detached(priority: .utility) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            var hasher = SHA256()
            while true {
                let chunk = handle.readData(ofLength: 64 * 1024)
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value


        var width = 0
        var height = 0

        if type == .staticImage {
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
                height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
            }
        } else if type == .video {
            let asset = AVURLAsset(url: url)
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                let naturalSize = try? await track.load(.naturalSize)
                width = Int(naturalSize?.width ?? 0)
                height = Int(naturalSize?.height ?? 0)
            }
        }

        return (width, height, size, hash)
    }

    // MARK: - Persistence

    private struct LibraryStateSnapshot: Codable {
        var items: [WallpaperLibraryItem]
        var recentIDs: [UUID]
    }

    public func saveToDisk() {
        let snapshot = LibraryStateSnapshot(items: items, recentIDs: recentIDs)
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            logger.error("Failed to persist library state: \(error.localizedDescription)")
        }
    }

    public func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path),
              let data = try? Data(contentsOf: persistenceURL),
              let snapshot = try? JSONDecoder().decode(LibraryStateSnapshot.self, from: data) else {
            return
        }
        self.items = snapshot.items
        self.recentIDs = snapshot.recentIDs
    }
}

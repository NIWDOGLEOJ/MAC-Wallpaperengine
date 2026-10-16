//
//  MotionBGsService.swift
//  WallpaperEngineCore
//
//  Lightweight, high-performance HTTP service for discovering, searching,
//  and fetching metadata from MotionBGs without excessive network overhead.
//

import Foundation
import OSLog

public enum MotionBGSError: LocalizedError, Sendable {
    case invalidURL
    case networkUnavailable
    case rateLimited
    case serverError(statusCode: Int)
    case parsingFailed
    case emptyResults
    case requestCancelled

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid MotionBGs URL."
        case .networkUnavailable:
            return "No internet connection. Please check your network connection."
        case .rateLimited:
            return "MotionBGs rate limit reached. Please wait a moment before trying again."
        case .serverError(let code):
            return "MotionBGs returned server error code: \(code)."
        case .parsingFailed:
            return "Failed to parse wallpaper metadata from MotionBGs."
        case .emptyResults:
            return "No wallpapers found matching your request."
        case .requestCancelled:
            return "Request was cancelled."
        }
    }
}

public actor MotionBGsService {
    public static let shared = MotionBGsService()

    private let session: URLSession
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "MotionBGsService")
    private let baseURL = URL(string: "https://motionbgs.com")!

    // Bounded in-memory metadata cache (max 50 entries, 15m TTL)
    private struct CacheEntry: Sendable {
        let items: [MotionBGsWallpaper]
        let timestamp: Date
    }
    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 900 // 15 minutes
    private let maxCacheEntries: Int = 50

    public init(session: URLSession? = nil) {
        if let customSession = session {
            self.session = customSession
        } else {
            let config = URLSessionConfiguration.default
            config.requestCachePolicy = .useProtocolCachePolicy
            config.timeoutIntervalForRequest = 10.0
            config.timeoutIntervalForResource = 20.0
            config.httpAdditionalHeaders = [
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            ]
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Discovery & Search

    public func fetchCatalog(category: MotionBGsCategory, page: Int = 1) async throws -> [MotionBGsWallpaper] {
        try Task.checkCancellation()

        let cacheKey = "category:\(category.rawValue):page:\(page)"
        if let entry = cache[cacheKey], Date().timeIntervalSince(entry.timestamp) < cacheTTL {
            return entry.items
        }

        let url: URL
        let path = category.pathComponent
        if path.isEmpty {
            if page == 1 {
                url = baseURL
            } else {
                url = baseURL.appendingPathComponent("\(page)/")
            }
        } else {
            if page == 1 {
                url = baseURL.appendingPathComponent("\(path)/")
            } else {
                url = baseURL.appendingPathComponent("\(path)/\(page)/")
            }
        }

        let items = try await fetchAndParseWallpapers(from: url)
        storeInCache(key: cacheKey, items: items)
        return items
    }

    public func search(query: String, page: Int = 1) async throws -> [MotionBGsWallpaper] {
        try Task.checkCancellation()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try await fetchCatalog(category: .all, page: page)
        }

        let cacheKey = "search:\(trimmed.lowercased()):page:\(page)"
        if let entry = cache[cacheKey], Date().timeIntervalSince(entry.timestamp) < cacheTTL {
            return entry.items
        }

        // Construct URL
        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: true)
        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmed)
        ]
        if page > 1 {
            components?.queryItems?.append(URLQueryItem(name: "p", value: String(page)))
        }

        guard let searchURL = components?.url else {
            throw MotionBGSError.invalidURL
        }

        let items = try await fetchAndParseWallpapers(from: searchURL)
        storeInCache(key: cacheKey, items: items)
        return items
    }

    // MARK: - Detail Extraction

    public func fetchDetail(for item: MotionBGsWallpaper) async throws -> MotionBGsWallpaper {
        try Task.checkCancellation()

        var updated = item

        do {
            let (data, response) = try await session.data(from: item.pageURL)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return item
            }
            guard let html = String(data: data, encoding: .utf8) else {
                return item
            }

            // Extract schema.org VideoObject JSON-LD (supports both quoted and unquoted script tags)
            let jsonPattern = "(?s)<script[^>]*application/ld\\+json[^>]*>(.*?)</script>"
            if let regex = try? NSRegularExpression(pattern: jsonPattern, options: []) {
                let nsHTML = html as NSString
                let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
                for match in matches {
                    guard match.numberOfRanges >= 2 else { continue }
                    let jsonText = nsHTML.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard jsonText.contains("VideoObject") else { continue }
                    if let jsonData = jsonText.data(using: .utf8),
                       let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        if let contentUrlStr = dict["contentUrl"] as? String, let cUrl = URL(string: contentUrlStr) {
                            updated.previewVideoURL = cUrl
                        }
                        if let width = dict["width"] as? Int {
                            updated.width = width
                        }
                        if let height = dict["height"] as? Int {
                            updated.height = height
                        }
                        if let durationStr = dict["duration"] as? String {
                            updated.durationSeconds = parseISO8601Duration(durationStr)
                        }
                        if let authorDict = dict["author"] as? [String: Any], let name = authorDict["name"] as? String {
                            updated.creator = name
                        } else if let authorStr = dict["author"] as? String {
                            updated.creator = authorStr
                        }
                        break
                    }
                }
            }

            // Extract tags
            let tagMatches = extractTags(from: html)
            if !tagMatches.isEmpty {
                updated.tags = tagMatches
            }

        } catch {
            logger.notice("Detail fetch fallback to synthesized metadata for \(item.slug): \(error.localizedDescription)")
        }

        return updated
    }

    // MARK: - Internal HTTP & Parsing Pipeline

    private func fetchAndParseWallpapers(from url: URL) async throws -> [MotionBGsWallpaper] {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch is CancellationError {
            throw MotionBGSError.requestCancelled
        } catch let urlError as URLError {
            if urlError.code == .cancelled {
                throw MotionBGSError.requestCancelled
            }
            if urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
                throw MotionBGSError.networkUnavailable
            }
            throw MotionBGSError.networkUnavailable
        } catch {
            throw MotionBGSError.networkUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MotionBGSError.networkUnavailable
        }

        if httpResponse.statusCode == 429 {
            throw MotionBGSError.rateLimited
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw MotionBGSError.serverError(statusCode: httpResponse.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw MotionBGSError.parsingFailed
        }

        let items = parseWallpapers(fromHTML: html)
        return items
    }

    public func parseWallpapers(fromHTML html: String) -> [MotionBGsWallpaper] {
        var results: [MotionBGsWallpaper] = []

        // Locate thumbnail container <div class=tmb>
        let searchArea: Substring
        if let tmbRange = html.range(of: "class=tmb") {
            searchArea = html[tmbRange.lowerBound...]
        } else {
            searchArea = html[...]
        }

        // Pattern matching cards: <a> tag with href and content
        let cardPattern = "<a\\s+([^>]*?)href=[\"']?(/[^\"'\\s>]+)[\"']?([^>]*?)>(.*?)</a>"
        guard let regex = try? NSRegularExpression(pattern: cardPattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }

        let nsString = String(searchArea) as NSString
        let matches = regex.matches(in: String(searchArea), range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard match.numberOfRanges >= 5 else { continue }
            let preAttrs = nsString.substring(with: match.range(at: 1))
            var slug = nsString.substring(with: match.range(at: 2))
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")
            let postAttrs = nsString.substring(with: match.range(at: 3))
            let body = nsString.substring(with: match.range(at: 4))

            // Ensure slug is clean path
            if slug.hasPrefix("/") {
                slug.removeFirst()
            }
            guard !slug.isEmpty, !slug.hasPrefix("tag:"), !slug.hasPrefix("page/"), !slug.hasPrefix("mobile/") else { continue }

            // Extract title from tag attributes if present
            var rawTitle = slug.replacingOccurrences(of: "-", with: " ").capitalized
            let allAttrs = preAttrs + " " + postAttrs
            if let titleRange = allAttrs.range(of: "title=[\"']([^\"']+)[\"']", options: .regularExpression) {
                let matched = allAttrs[titleRange]
                    .replacingOccurrences(of: "title=", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "'", with: "")
                rawTitle = String(matched)
            }

            // Extract thumbnail URL from img src or picture source
            var thumbURLStr = ""
            if let srcRange = body.range(of: "\\bsrc=[\"']?([^\"'\\s>]+)[\"']?", options: .regularExpression) {
                let matched = body[srcRange]
                    .replacingOccurrences(of: "src=", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "'", with: "")
                thumbURLStr = String(matched)
            }

            let fullThumbURL: URL
            if thumbURLStr.hasPrefix("http") {
                fullThumbURL = URL(string: thumbURLStr) ?? baseURL
            } else if thumbURLStr.hasPrefix("/") {
                fullThumbURL = baseURL.appendingPathComponent(String(thumbURLStr.dropFirst()))
            } else if !thumbURLStr.isEmpty {
                fullThumbURL = baseURL.appendingPathComponent(thumbURLStr)
            } else {
                fullThumbURL = baseURL.appendingPathComponent("media/\(slug).jpg")
            }

            // Extract media ID from thumbnail path: e.g. /media/10297/
            var mediaID = slug
            if let idRange = thumbURLStr.range(of: "media/(\\d+)/", options: .regularExpression) {
                let idMatch = thumbURLStr[idRange]
                    .replacingOccurrences(of: "media/", with: "")
                    .replacingOccurrences(of: "/", with: "")
                mediaID = String(idMatch)
            }

            // Extract resolution badge: <span class=frm> 4K </span>
            var resBadge = "4K"
            if let frmRange = body.range(of: "class=frm>\\s*([^<]+)", options: .regularExpression) {
                let frmMatch = body[frmRange]
                    .replacingOccurrences(of: "class=frm>", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !frmMatch.isEmpty {
                    resBadge = frmMatch
                }
            }

            // Extract clean title: <span class=ttl>Title</span>
            var cleanTitle = rawTitle
            if let ttlRange = body.range(of: "class=ttl>\\s*([^<]+)", options: .regularExpression) {
                let ttlMatch = body[ttlRange]
                    .replacingOccurrences(of: "class=ttl>", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !ttlMatch.isEmpty {
                    cleanTitle = ttlMatch
                }
            }

            // Clean up trailing "live wallpaper" if present in title
            if cleanTitle.lowercased().hasSuffix(" live wallpaper") {
                cleanTitle = String(cleanTitle.dropLast(" live wallpaper".count)).trimmingCharacters(in: .whitespaces)
            }

            let pageURL = baseURL.appendingPathComponent(slug)
            let download4K = URL(string: "https://motionbgs.com/dl/4k/\(mediaID)/")
            let downloadHD = URL(string: "https://motionbgs.com/dl/hd/\(mediaID)/")
            let previewVideo = URL(string: "https://motionbgs.com/media/\(mediaID)/\(slug).960x540.mp4")

            let wallpaper = MotionBGsWallpaper(
                id: mediaID,
                title: cleanTitle,
                slug: slug,
                thumbnailURL: fullThumbURL,
                previewVideoURL: previewVideo,
                resolution: resBadge,
                download4KURL: download4K,
                downloadHDURL: downloadHD,
                pageURL: pageURL,
                tags: []
            )

            results.append(wallpaper)
        }

        return results
    }

    private func extractTags(from html: String) -> [String] {
        var tags: [String] = []
        let pattern = "href=[\"']?/tag:([a-zA-Z0-9\\-_]+)/?[\"']?>\\s*([^<]+)</a>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsString = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let tagName = nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tagName.isEmpty && !tags.contains(tagName) {
                tags.append(tagName)
            }
        }
        return tags
    }

    private func parseISO8601Duration(_ str: String) -> Double? {
        // Handles formats like "PT12.4S", "PT1M30S", "PT1H5M30S"
        var text = str.uppercased().replacingOccurrences(of: "PT", with: "")
        var total: Double = 0.0
        var foundAny = false

        if let hRange = text.range(of: "H") {
            let hStr = text[..<hRange.lowerBound]
            if let h = Double(hStr) {
                total += h * 3600.0
                foundAny = true
            }
            text = String(text[hRange.upperBound...])
        }

        if let mRange = text.range(of: "M") {
            let mStr = text[..<mRange.lowerBound]
            if let m = Double(mStr) {
                total += m * 60.0
                foundAny = true
            }
            text = String(text[mRange.upperBound...])
        }

        let sStr = text.replacingOccurrences(of: "S", with: "")
        if let s = Double(sStr) {
            total += s
            foundAny = true
        }

        return foundAny ? total : nil
    }

    public var cachedEntriesCount: Int {
        cache.count
    }

    public func cachedItems(for key: String) -> [MotionBGsWallpaper]? {
        cache[key]?.items
    }

    public func storeCacheEntry(key: String, items: [MotionBGsWallpaper], timestamp: Date = Date()) {
        if cache.count >= maxCacheEntries {
            // Evict oldest
            if let oldestKey = cache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                cache.removeValue(forKey: oldestKey)
            }
        }
        cache[key] = CacheEntry(items: items, timestamp: timestamp)
    }

    private func storeInCache(key: String, items: [MotionBGsWallpaper]) {
        storeCacheEntry(key: key, items: items, timestamp: Date())
    }

    public func clearCache() {
        cache.removeAll()
    }
}

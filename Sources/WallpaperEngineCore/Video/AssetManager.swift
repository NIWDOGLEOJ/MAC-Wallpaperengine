//
//  AssetManager.swift
//  WallpaperEngineCore
//
//  Asynchronous video file validation, codec inspection, metadata extraction,
//  and security-scoped bookmark resolution for Milestone 2.
//

import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

/// Immutable, Sendable representation of a validated, playable video asset.
public struct VideoAsset: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    public let fileURL: URL
    public let title: String
    public let duration: CMTime
    public let naturalSize: CGSize
    public let codec: String
    public let bookmarkData: Data?

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        title: String,
        duration: CMTime = .zero,
        naturalSize: CGSize = .zero,
        codec: String = "unknown",
        bookmarkData: Data? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.title = title
        self.duration = duration
        self.naturalSize = naturalSize
        self.codec = codec
        self.bookmarkData = bookmarkData
    }
}

/// Protocol defining asynchronous media asset inspection, parsing, and caching.
public protocol AssetManaging: Actor {
    func inspectAsset(at url: URL) async throws -> VideoAsset
    func assign(url: URL, to displayID: DisplayID)
    func assignedURL(for displayID: DisplayID) -> URL?
    func allAssignments() -> [DisplayID: URL]
    func resolveBookmark(_ bookmarkData: Data) throws -> URL
    func generateThumbnail(for asset: VideoAsset, at time: CMTime) async throws -> CGImage
}

/// Dedicated background actor responsible for media file validation, container inspection, and caching.
public actor AssetManager: AssetManaging {
    private var assetCache: [URL: VideoAsset] = [:]
    private var displayAssignments: [DisplayID: URL] = [:]

    public static let supportedCodecs: Set<String> = [
        "avc1", // H.264 / AVC
        "hvc1", // HEVC / H.265 (preferred parameter sets in sample description)
        "hev1", // HEVC / H.265 (in-band parameter sets)
        "apch", // Apple ProRes 422 HQ
        "apcn", // Apple ProRes 422
        "apcs", // Apple ProRes 422 LT
        "apco", // Apple ProRes 422 Proxy
        "ap4h", // Apple ProRes 4444
        "av01"  // AV1
    ]

    public static let supportedExtensions: Set<String> = ["mp4", "mov", "m4v"]

    public init() {}

    public func assign(url: URL, to displayID: DisplayID) {
        displayAssignments[displayID] = url
    }

    public func assignedURL(for displayID: DisplayID) -> URL? {
        displayAssignments[displayID]
    }

    public func allAssignments() -> [DisplayID: URL] {
        displayAssignments
    }

    public func inspectAsset(at url: URL) async throws -> VideoAsset {
        if let cached = assetCache[url] {
            return cached
        }

        // 1. File existence check
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VideoEngineError.fileNotFound(url)
        }

        // 2. Truncation and zero-byte check
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw VideoEngineError.fileNotFound(url)
        }

        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard fileSize > 128 else {
            throw VideoEngineError.unreadableFormat("Zero-byte or truncated video file: \(url.lastPathComponent)")
        }

        // 3. Container format check
        let ext = url.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw VideoEngineError.unreadableFormat("Unsupported container format: .\(ext)")
        }

        // 4. Asynchronous asset property loading (Swift 6)
        let asset = AVURLAsset(url: url)
        let isPlayable: Bool
        do {
            isPlayable = try await asset.load(.isPlayable)
        } catch {
            throw VideoEngineError.assetNotPlayable(url)
        }
        guard isPlayable else {
            throw VideoEngineError.assetNotPlayable(url)
        }

        // 5. Video track existence check
        let videoTracks: [AVAssetTrack]
        do {
            videoTracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            throw VideoEngineError.assetNotPlayable(url)
        }
        guard let videoTrack = videoTracks.first else {
            throw VideoEngineError.noVideoTrack(url)
        }

        // 6. Geometry and duration validation
        let naturalSize = try await videoTrack.load(.naturalSize)
        let timeRange = try await videoTrack.load(.timeRange)
        let trackDuration = timeRange.duration

        guard trackDuration.isNumeric && trackDuration.seconds > 0.05 else {
            throw VideoEngineError.unreadableFormat("Invalid or negligible video duration")
        }

        // 7. Codec compatibility check
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        var codecName = "Unknown"
        if let firstFormat = formatDescriptions.first {
            let mediaSubtype = CMFormatDescriptionGetMediaSubType(firstFormat)
            codecName = fourCharCodeToString(mediaSubtype)
        }

        guard Self.supportedCodecs.contains(codecName.lowercased()) else {
            throw VideoEngineError.unreadableFormat("Unsupported hardware codec: \(codecName)")
        }

        let title = url.deletingPathExtension().lastPathComponent
        let videoAsset = VideoAsset(
            fileURL: url,
            title: title,
            duration: trackDuration,
            naturalSize: naturalSize,
            codec: codecName
        )

        assetCache[url] = videoAsset
        return videoAsset
    }

    public func resolveBookmark(_ bookmarkData: Data) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return url
    }

    public func generateThumbnail(for asset: VideoAsset, at time: CMTime = .zero) async throws -> CGImage {
        let urlAsset = AVURLAsset(url: asset.fileURL)
        let imageGenerator = AVAssetImageGenerator(asset: urlAsset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 400, height: 250)

        let (cgImage, _) = try await imageGenerator.image(at: time)
        return cgImage
    }

    private func fourCharCodeToString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

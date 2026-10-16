//
//  WallpaperPackageManager.swift
//  WallpaperEngineCore
//
//  Feature 15: Community wallpaper packaging and secure import/export engine.
//  Exports and validates self-contained .wepack bundles with SHA-256 integrity verification.
//

import CryptoKit
import Foundation
import OSLog

public struct WallpaperPackageManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var title: String
    public var author: String
    public var description: String
    public var version: String
    public var type: LibraryWallpaperType
    public var mainAssetFileName: String
    public var previewFileName: String?
    public var tags: [String]
    public var sha256Checksum: String

    public init(
        schemaVersion: Int = 1,
        title: String,
        author: String = "Community Creator",
        description: String = "",
        version: String = "1.0.0",
        type: LibraryWallpaperType,
        mainAssetFileName: String,
        previewFileName: String? = nil,
        tags: [String] = [],
        sha256Checksum: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.author = author
        self.description = description
        self.version = version
        self.type = type
        self.mainAssetFileName = mainAssetFileName
        self.previewFileName = previewFileName
        self.tags = tags
        self.sha256Checksum = sha256Checksum
    }
}

public enum PackageError: Error, LocalizedError, Sendable, Equatable {
    case invalidManifest
    case assetFileNotFound(String)
    case checksumMismatch
    case pathTraversalAttackDetected(String)
    case unsupportedSchemaVersion(Int)
    case assetSizeExceedsLimit(Int64, Int64)

    public var errorDescription: String? {
        switch self {
        case .invalidManifest: return "Invalid package manifest.json"
        case .assetFileNotFound(let file): return "Package asset missing: \(file)"
        case .checksumMismatch: return "Asset integrity check failed (SHA-256 mismatch)"
        case .pathTraversalAttackDetected(let p): return "Security error: invalid path traversal in package: \(p)"
        case .unsupportedSchemaVersion(let v): return "Unsupported package schema version: \(v)"
        case .assetSizeExceedsLimit(let current, let limit):
            return "Package asset size \(current) bytes exceeds maximum limit of \(limit) bytes"
        }
    }
}

public final class WallpaperPackageManager: @unchecked Sendable {
    public static let shared = WallpaperPackageManager()
    public static let maxPackageAssetSizeBytes: Int64 = 500 * 1024 * 1024 // 500 MB limit
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "PackageManager")
    private let fileManager = FileManager.default

    public init() {}

    /// Calculates SHA-256 in memory-bounded 64KB chunks to prevent unbounded memory spikes.
    public func computeStreamingSHA256(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 64 * 1024)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Exports a wallpaper and its metadata to a package directory bundle.
    public func exportPackage(
        title: String,
        author: String = "User",
        type: LibraryWallpaperType,
        assetURL: URL,
        previewURL: URL? = nil,
        destinationDirectory: URL
    ) throws -> URL {
        guard fileManager.fileExists(atPath: assetURL.path) else {
            throw PackageError.assetFileNotFound(assetURL.path)
        }

        let checksum = try computeStreamingSHA256(for: assetURL)

        let sanitizedTitle = title
            .replacingOccurrences(of: "..", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let packageDirName = "\(sanitizedTitle.isEmpty ? "wallpaper" : sanitizedTitle).wepack"
        let packageDir = destinationDirectory.appendingPathComponent(packageDirName, isDirectory: true)
        try fileManager.createDirectory(at: packageDir, withIntermediateDirectories: true)

        let targetAssetFileName = assetURL.lastPathComponent
        let targetAssetURL = packageDir.appendingPathComponent(targetAssetFileName)
        if fileManager.fileExists(atPath: targetAssetURL.path) {
            try? fileManager.removeItem(at: targetAssetURL)
        }
        try fileManager.copyItem(at: assetURL, to: targetAssetURL)

        var previewFileName: String? = nil
        if let pURL = previewURL, fileManager.fileExists(atPath: pURL.path) {
            let pName = "preview.\(pURL.pathExtension)"
            let targetPreview = packageDir.appendingPathComponent(pName)
            if fileManager.fileExists(atPath: targetPreview.path) {
                try? fileManager.removeItem(at: targetPreview)
            }
            try? fileManager.copyItem(at: pURL, to: targetPreview)
            previewFileName = pName
        }

        let manifest = WallpaperPackageManifest(
            schemaVersion: 1,
            title: title,
            author: author,
            type: type,
            mainAssetFileName: targetAssetFileName,
            previewFileName: previewFileName,
            sha256Checksum: checksum
        )

        let manifestData = try JSONEncoder().encode(manifest)
        let manifestURL = packageDir.appendingPathComponent("manifest.json")
        try manifestData.write(to: manifestURL, options: .atomic)

        logger.info("Exported wallpaper package to \(packageDir.path)")
        return packageDir
    }

    /// Validates and unpacks a .wepack package bundle with strict sandboxing and SHA-256 verification.
    public func importAndValidatePackage(at packageURL: URL) throws -> (manifest: WallpaperPackageManifest, assetURL: URL) {
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path),
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(WallpaperPackageManifest.self, from: manifestData) else {
            throw PackageError.invalidManifest
        }

        // 1. Schema version validation
        guard manifest.schemaVersion == 1 else {
            throw PackageError.unsupportedSchemaVersion(manifest.schemaVersion)
        }

        // 2. Path traversal security check for mainAssetFileName
        if manifest.mainAssetFileName.contains("..") ||
           manifest.mainAssetFileName.hasPrefix("/") ||
           manifest.mainAssetFileName.contains("\\") ||
           manifest.mainAssetFileName.contains("\0") {
            throw PackageError.pathTraversalAttackDetected(manifest.mainAssetFileName)
        }

        // 3. Path traversal security check for previewFileName
        if let preview = manifest.previewFileName {
            if preview.contains("..") || preview.hasPrefix("/") || preview.contains("\\") || preview.contains("\0") {
                throw PackageError.pathTraversalAttackDetected(preview)
            }
        }

        // 4. Validate asset existence and prevent symlink escape
        let assetURL = packageURL.appendingPathComponent(manifest.mainAssetFileName)
        guard fileManager.fileExists(atPath: assetURL.path) else {
            throw PackageError.assetFileNotFound(manifest.mainAssetFileName)
        }

        let canonicalPackagePath = packageURL.resolvingSymlinksInPath().standardizedFileURL.path
        let canonicalAssetPath = assetURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard canonicalAssetPath.hasPrefix(canonicalPackagePath) else {
            throw PackageError.pathTraversalAttackDetected(manifest.mainAssetFileName)
        }

        // 5. Bounded asset size limit check
        let attrs = try? fileManager.attributesOfItem(atPath: canonicalAssetPath)
        let fileSize = (attrs?[.size] as? Int64) ?? 0
        guard fileSize <= Self.maxPackageAssetSizeBytes else {
            throw PackageError.assetSizeExceedsLimit(fileSize, Self.maxPackageAssetSizeBytes)
        }

        // 6. Verify SHA-256 checksum if provided via memory-bounded streaming
        if !manifest.sha256Checksum.isEmpty {
            let calculated = try computeStreamingSHA256(for: assetURL)
            guard calculated.lowercased() == manifest.sha256Checksum.lowercased() else {
                logger.error("Package checksum mismatch! Expected \(manifest.sha256Checksum), got \(calculated)")
                throw PackageError.checksumMismatch
            }
        }

        logger.info("Successfully validated package: \(manifest.title) by \(manifest.author)")
        return (manifest, assetURL)
    }
}

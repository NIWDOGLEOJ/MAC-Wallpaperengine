//
//  MotionBGsDownloadManager.swift
//  WallpaperEngineCore
//
//  Manages downloading full-resolution MotionBGs video assets with live progress tracking,
//  cancellation, asset validation, local library persistence, desktop renderer application,
//  and seamless theme/widget color synchronization.
//

import AppKit
import AVFoundation
import Foundation
import OSLog

public enum DownloadState: Equatable, Sendable {
    case idle
    case downloading(progress: Double, bytesRead: Int64, totalBytes: Int64)
    case validating
    case applying
    case completed(fileURL: URL)
    case failed(error: String)
}

@MainActor
public final class MotionBGsDownloadManager: NSObject, ObservableObject {
    public static let shared = MotionBGsDownloadManager()

    @Published public private(set) var activeDownloads: [String: DownloadState] = [:]

    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var downloadContinuations: [String: CheckedContinuation<URL, Error>] = [:]
    private var taskItemMap: [Int: String] = [:] // Task identifier -> item ID
    private var session: URLSession!
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "MotionBGsDownloadManager")

    public var customWallpapersDirectory: URL? = nil

    public override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 300.0 // 5 minutes max for full 4K downloads
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        ]
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - Download & Apply Pipeline

    public func downloadAndApply(
        wallpaper: MotionBGsWallpaper,
        resolution: WallpaperDownloadResolution = .hd,
        displayID: CGDirectDisplayID? = nil,
        coordinator: AppCoordinatorProtocol?,
        libraryManager: WallpaperLibraryManager? = nil
    ) async throws {
        let itemID = wallpaper.id
        let resSuffix = resolution == .fourK ? "3840x2160" : "1920x1080"
        let filename = "\(wallpaper.slug).\(resSuffix).mp4"

        // Wallpapers destination directory
        let wallpapersDir = customWallpapersDirectory ?? ConfigPersistenceManager.defaultConfigDirectoryURL.appendingPathComponent("Wallpapers", isDirectory: true)
        try? fileManager.createDirectory(at: wallpapersDir, withIntermediateDirectories: true)
        let destinationURL = wallpapersDir.appendingPathComponent(filename)

        // 1. Check if file already exists locally and is valid (Zero Waste)
        if fileManager.fileExists(atPath: destinationURL.path),
           let attrs = try? fileManager.attributesOfItem(atPath: destinationURL.path),
           let size = attrs[.size] as? Int64, size > 1024 * 100 {
            logger.info("Reusing existing local wallpaper file at \(destinationURL.path)")
            activeDownloads[itemID] = .completed(fileURL: destinationURL)
            try await applyDownloadedWallpaper(
                at: destinationURL,
                wallpaper: wallpaper,
                displayID: displayID,
                coordinator: coordinator,
                libraryManager: libraryManager
            )
            return
        }

        // 2. Resolve download URL
        let downloadURL: URL
        if resolution == .fourK {
            downloadURL = wallpaper.download4KURL ?? URL(string: "https://motionbgs.com/dl/4k/\(wallpaper.id)/")!
        } else {
            downloadURL = wallpaper.downloadHDURL ?? URL(string: "https://motionbgs.com/dl/hd/\(wallpaper.id)/")!
        }

        // 3. Initiate download safely (cancel any prior in-flight task to prevent continuation leak)
        if let oldTask = downloadTasks.removeValue(forKey: itemID) {
            oldTask.cancel()
            taskItemMap.removeValue(forKey: oldTask.taskIdentifier)
        }
        if let oldCont = downloadContinuations.removeValue(forKey: itemID) {
            oldCont.resume(throwing: MotionBGSError.requestCancelled)
        }

        activeDownloads[itemID] = .downloading(progress: 0.0, bytesRead: 0, totalBytes: 0)

        let tempURL: URL
        do {
            tempURL = try await withCheckedThrowingContinuation { continuation in
                downloadContinuations[itemID] = continuation
                let task = session.downloadTask(with: downloadURL)
                downloadTasks[itemID] = task
                taskItemMap[task.taskIdentifier] = itemID
                task.resume()
            }
        } catch {
            activeDownloads[itemID] = .failed(error: error.localizedDescription)
            throw error
        }

        // 4. Validate downloaded file
        activeDownloads[itemID] = .validating
        guard fileManager.fileExists(atPath: tempURL.path) else {
            let err = "Downloaded file not found on disk."
            activeDownloads[itemID] = .failed(error: err)
            throw MotionBGSError.parsingFailed
        }

        let attrs = try fileManager.attributesOfItem(atPath: tempURL.path)
        guard let size = attrs[.size] as? Int64, size > 1024 * 10 else {
            try? fileManager.removeItem(at: tempURL)
            let err = "Downloaded file corrupted or zero-byte."
            activeDownloads[itemID] = .failed(error: err)
            throw MotionBGSError.parsingFailed
        }

        // Move to destination atomically
        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: tempURL, to: destinationURL)

        activeDownloads[itemID] = .completed(fileURL: destinationURL)

        // 5. Apply to renderer, library, and theme
        try await applyDownloadedWallpaper(
            at: destinationURL,
            wallpaper: wallpaper,
            displayID: displayID,
            coordinator: coordinator,
            libraryManager: libraryManager
        )
    }

    public func applyDownloadedWallpaper(
        at fileURL: URL,
        wallpaper: MotionBGsWallpaper,
        displayID: CGDirectDisplayID?,
        coordinator: AppCoordinatorProtocol?,
        libraryManager: WallpaperLibraryManager?
    ) async throws {
        // Record in MotionBGs recents
        MotionBGsFavoritesManager.shared.recordRecent(wallpaper: wallpaper)

        // Import into local WallpaperLibraryManager if available and record in library history
        if let lib = libraryManager {
            if let imported = try? await lib.importWallpaper(
                from: fileURL,
                type: .video,
                tags: wallpaper.tags.isEmpty ? ["MotionBGs", wallpaper.resolution] : wallpaper.tags,
                category: "MotionBGs"
            ) {
                lib.recordRecent(id: imported.id)
            }
        }

        // Apply via existing AppCoordinator video pipeline
        guard let coord = coordinator else {
            logger.notice("No active coordinator; wallpaper saved at \(fileURL.path)")
            return
        }

        try await coord.setVideo(url: fileURL, for: displayID)

        // Synchronize HUD widgets and theme appearance
        let targetID = displayID ?? coord.windowManager.managedWindows.keys.first ?? 1
        coord.syncWallpaperAccentColor(for: targetID)
        coord.appState?.updateActiveWallpaperAccentColor()
        coord.appState?.refreshDiscoveredVideos()
        coord.appState?.showToast("Applied MotionBGs wallpaper '\(wallpaper.title)'")
    }

    public func cancelDownload(itemID: String) {
        if let task = downloadTasks.removeValue(forKey: itemID) {
            task.cancel()
            taskItemMap.removeValue(forKey: task.taskIdentifier)
        }
        if let cont = downloadContinuations.removeValue(forKey: itemID) {
            cont.resume(throwing: MotionBGSError.requestCancelled)
        }
        activeDownloads[itemID] = .failed(error: "Download cancelled")
    }

    public func cancelAll() {
        for (itemID, task) in downloadTasks {
            task.cancel()
            if let cont = downloadContinuations.removeValue(forKey: itemID) {
                cont.resume(throwing: MotionBGSError.requestCancelled)
            }
        }
        downloadTasks.removeAll()
        taskItemMap.removeAll()
        activeDownloads.removeAll()
    }

    // MARK: - Internal MainActor Event Dispatchers

    func handleDownloadFinished(taskID: Int, tempFile: URL) {
        guard let itemID = taskItemMap[taskID],
              let continuation = downloadContinuations.removeValue(forKey: itemID) else {
            return
        }
        downloadTasks.removeValue(forKey: itemID)
        taskItemMap.removeValue(forKey: taskID)
        continuation.resume(returning: tempFile)
    }

    func handleDownloadProgress(taskID: Int, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let itemID = taskItemMap[taskID] else { return }
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
        activeDownloads[itemID] = .downloading(
            progress: progress,
            bytesRead: totalBytesWritten,
            totalBytes: totalBytesExpectedToWrite
        )
    }

    func handleDownloadFailed(taskID: Int, error: Error) {
        guard let itemID = taskItemMap[taskID],
              let continuation = downloadContinuations.removeValue(forKey: itemID) else {
            return
        }
        downloadTasks.removeValue(forKey: itemID)
        taskItemMap.removeValue(forKey: taskID)

        let isCancelled = (error as? URLError)?.code == .cancelled
        continuation.resume(throwing: isCancelled ? MotionBGSError.requestCancelled : error)
    }
}

// MARK: - URLSessionDownloadDelegate Conformance

extension MotionBGsDownloadManager: URLSessionDownloadDelegate {
    nonisolated public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        do {
            try FileManager.default.moveItem(at: location, to: tempFile)
            Task { @MainActor in
                self.handleDownloadFinished(taskID: downloadTask.taskIdentifier, tempFile: tempFile)
            }
        } catch {
            Task { @MainActor in
                self.handleDownloadFailed(taskID: downloadTask.taskIdentifier, error: error)
            }
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            self.handleDownloadProgress(
                taskID: downloadTask.taskIdentifier,
                totalBytesWritten: totalBytesWritten,
                totalBytesExpectedToWrite: totalBytesExpectedToWrite
            )
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            Task { @MainActor in
                self.handleDownloadFailed(taskID: task.taskIdentifier, error: error)
            }
        }
    }
}

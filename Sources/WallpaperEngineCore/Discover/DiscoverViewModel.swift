//
//  DiscoverViewModel.swift
//  WallpaperEngineCore
//
//  State coordinator for the native Discover section.
//  Coordinates debounced search, category filters, bounded pagination,
//  thumbnail concurrency & LRU bounds, detail previews, and offline favorites.
//

import AppKit
import AVFoundation
import Combine
import Foundation
import OSLog

@MainActor
public final class DiscoverViewModel: ObservableObject {
    @Published public var items: [MotionBGsWallpaper] = []
    @Published public var isLoading: Bool = false
    @Published public var isLoadingMore: Bool = false
    @Published public var searchQuery: String = ""
    @Published public var selectedCategory: MotionBGsCategory = .all
    @Published public var selectedFilter: DiscoverFilter = .all
    @Published public var selectedWallpaper: MotionBGsWallpaper? = nil
    @Published public var errorMessage: String? = nil
    @Published public var currentPage: Int = 1
    @Published public var hasMorePages: Bool = true

    // Download & Preview State
    @Published public var selectedResolution: WallpaperDownloadResolution = .hd
    @Published public var isDetailSheetPresented: Bool = false
    @Published public var isPlayingPreview: Bool = false
    @Published public var player: AVPlayer? = nil
    @Published public var thumbnailImages: [URL: NSImage] = [:]

    private var thumbnailTasks: [URL: Task<Void, Never>] = [:]
    private var thumbnailOrder: [URL] = []
    private let maxVisibleThumbnails = 60

    private let service: MotionBGsService
    public let favoritesManager: MotionBGsFavoritesManager
    public let downloadManager: MotionBGsDownloadManager
    private var searchTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "DiscoverViewModel")

    public init(
        service: MotionBGsService = .shared,
        favoritesManager: MotionBGsFavoritesManager = .shared,
        downloadManager: MotionBGsDownloadManager = .shared
    ) {
        self.service = service
        self.favoritesManager = favoritesManager
        self.downloadManager = downloadManager

        setupSearchDebounce()
    }

    // MARK: - Lifecycle

    public func onAppear() {
        if items.isEmpty && errorMessage == nil {
            loadInitialContent()
        }
    }

    public func teardown() {
        searchTask?.cancel()
        searchTask = nil
        paginationTask?.cancel()
        paginationTask = nil
        clearThumbnails()
        stopPreviewPlayback()
        downloadManager.cancelAll()
        logger.info("DiscoverViewModel torn down: cancelled searches, thumbnails, previews, and downloads.")
    }

    // MARK: - Data Loading

    public func loadInitialContent() {
        searchTask?.cancel()
        searchTask = nil
        paginationTask?.cancel()
        paginationTask = nil

        if selectedFilter == .favorites {
            self.items = favoritesManager.favorites
            self.isLoading = false
            self.hasMorePages = false
            return
        }
        if selectedFilter == .recents {
            self.items = favoritesManager.recents
            self.isLoading = false
            self.hasMorePages = false
            return
        }

        self.isLoading = true
        self.errorMessage = nil
        self.currentPage = 1
        self.hasMorePages = true

        searchTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let fetched: [MotionBGsWallpaper]
                if !self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    fetched = try await self.service.search(query: self.searchQuery, page: 1)
                } else {
                    fetched = try await self.service.fetchCatalog(category: self.selectedCategory, page: 1)
                }

                if Task.isCancelled { return }

                self.items = fetched
                self.isLoading = false
                self.hasMorePages = fetched.count >= 20
            } catch is CancellationError {
                // Cancelled cleanly
            } catch {
                if Task.isCancelled { return }
                self.isLoading = false
                self.errorMessage = error.localizedDescription
                // Graceful fallback to offline favorites or recents if catalog fails
                if self.items.isEmpty {
                    self.items = self.favoritesManager.favorites
                }
            }
        }
    }

    public func loadNextPageIfNeeded(currentItem: MotionBGsWallpaper) {
        guard !isLoading, !isLoadingMore, hasMorePages else { return }
        guard let index = items.firstIndex(where: { $0.id == currentItem.id }) else { return }

        // Trigger loading when user is 6 items from the end
        let thresholdIndex = max(0, items.count - 6)
        if index >= thresholdIndex {
            loadNextPage()
        }
    }

    private func loadNextPage() {
        guard !isLoadingMore, hasMorePages else { return }
        guard selectedFilter == .all else { return }

        self.isLoadingMore = true
        let nextPage = currentPage + 1

        paginationTask?.cancel()
        paginationTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let fetched: [MotionBGsWallpaper]
                if !self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    fetched = try await self.service.search(query: self.searchQuery, page: nextPage)
                } else {
                    fetched = try await self.service.fetchCatalog(category: self.selectedCategory, page: nextPage)
                }

                if Task.isCancelled { return }

                if fetched.isEmpty {
                    self.hasMorePages = false
                } else {
                    let existingIDs = Set(self.items.map { $0.id })
                    let newItems = fetched.filter { !existingIDs.contains($0.id) }
                    if newItems.isEmpty {
                        self.hasMorePages = false
                    } else {
                        self.items.append(contentsOf: newItems)
                        self.currentPage = nextPage
                        self.hasMorePages = fetched.count >= 20
                    }
                }
                self.isLoadingMore = false
            } catch {
                if Task.isCancelled { return }
                self.isLoadingMore = false
            }
        }
    }

    // MARK: - Thumbnails

    public func loadThumbnail(for url: URL, targetSize: CGSize = CGSize(width: 364, height: 205)) {
        if thumbnailImages[url] != nil { return }
        if thumbnailTasks[url] != nil { return }

        thumbnailTasks[url] = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let loaded = await MotionBGsThumbnailCache.shared.image(for: url, targetSize: targetSize)
            if !Task.isCancelled, let img = loaded {
                // Bound active thumbnail dictionary (LRU)
                if self.thumbnailOrder.count >= self.maxVisibleThumbnails {
                    let oldest = self.thumbnailOrder.removeFirst()
                    self.thumbnailImages.removeValue(forKey: oldest)
                }
                self.thumbnailImages[url] = img
                self.thumbnailOrder.append(url)
            }
            self.thumbnailTasks.removeValue(forKey: url)
        }
    }

    public func cancelThumbnail(for url: URL) {
        thumbnailTasks.removeValue(forKey: url)?.cancel()
        thumbnailTasks.removeValue(forKey: url)
        MotionBGsThumbnailCache.shared.cancel(for: url)
    }

    public func clearThumbnails() {
        for (_, t) in thumbnailTasks {
            t.cancel()
        }
        thumbnailTasks.removeAll()
        thumbnailImages.removeAll()
        thumbnailOrder.removeAll()
    }

    // MARK: - Actions

    public func selectCategory(_ category: MotionBGsCategory) {
        guard selectedCategory != category || selectedFilter != .all else { return }
        selectedCategory = category
        selectedFilter = .all
        searchQuery = ""
        loadInitialContent()
    }

    public func selectFilter(_ filter: DiscoverFilter) {
        guard selectedFilter != filter else { return }
        selectedFilter = filter
        loadInitialContent()
    }

    public func openDetail(for wallpaper: MotionBGsWallpaper) {
        stopPreviewPlayback()
        self.selectedWallpaper = wallpaper
        self.selectedResolution = .hd
        self.isDetailSheetPresented = true

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let enriched = try? await self.service.fetchDetail(for: wallpaper) {
                if self.selectedWallpaper?.id == wallpaper.id {
                    self.selectedWallpaper = enriched
                }
            }
        }
    }

    public func togglePreviewPlayback() {
        if isPlayingPreview {
            stopPreviewPlayback()
        } else {
            guard let previewURL = selectedWallpaper?.previewVideoURL else { return }
            let p = AVPlayer(url: previewURL)
            p.isMuted = true // Mute preview by default to prevent desktop audio disruption
            self.player = p
            self.isPlayingPreview = true
            p.play()
        }
    }

    public func stopPreviewPlayback() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        isPlayingPreview = false
    }

    public func toggleFavorite(for wallpaper: MotionBGsWallpaper) {
        favoritesManager.toggleFavorite(wallpaper: wallpaper)
        if let idx = items.firstIndex(where: { $0.id == wallpaper.id }) {
            items[idx].isFavorite = favoritesManager.isFavorite(id: wallpaper.id)
        }
        if selectedFilter == .favorites {
            self.items = favoritesManager.favorites
        }
    }

    public func isFavorite(id: String) -> Bool {
        favoritesManager.isFavorite(id: id)
    }

    // MARK: - Private Helpers

    private func setupSearchDebounce() {
        $searchQuery
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.loadInitialContent()
            }
            .store(in: &cancellables)
    }
}

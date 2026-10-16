//
//  DiscoverViews.swift
//  WallpaperEngineCore
//
//  Native SwiftUI user interface for discovering, searching, previewing,
//  and applying MotionBGs wallpapers. Built strictly without @State macros
//  to guarantee 100% compatibility with standalone macOS Command Line Tools.
//

import AppKit
import AVFoundation
import AVKit
import SwiftUI

// MARK: - Async Thumbnail View

@MainActor
public struct AsyncThumbnailView: View {
    public let url: URL
    @ObservedObject public var viewModel: DiscoverViewModel
    public let targetSize: CGSize

    public init(url: URL, viewModel: DiscoverViewModel, targetSize: CGSize = CGSize(width: 364, height: 205)) {
        self.url = url
        self.viewModel = viewModel
        self.targetSize = targetSize
    }

    public var body: some View {
        ZStack {
            if let img = viewModel.thumbnailImages[url] {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 26))
                            .foregroundColor(.secondary.opacity(0.4))
                    )
            }
        }
        .frame(height: 150)
        .clipped()
        .onAppear {
            viewModel.loadThumbnail(for: url, targetSize: targetSize)
        }
        .onDisappear {
            viewModel.cancelThumbnail(for: url)
        }
    }
}

// MARK: - Discover Card View

@MainActor
public struct DiscoverCardView: View {
    public let wallpaper: MotionBGsWallpaper
    @ObservedObject public var viewModel: DiscoverViewModel
    @ObservedObject public var state: AppState

    public var body: some View {
        let isFavorite = viewModel.isFavorite(id: wallpaper.id)
        let downloadState = viewModel.downloadManager.activeDownloads[wallpaper.id]

        VStack(alignment: .leading, spacing: 10) {
            // Thumbnail with badges
            ZStack(alignment: .topTrailing) {
                AsyncThumbnailView(url: wallpaper.thumbnailURL, viewModel: viewModel)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 6) {
                    Text(wallpaper.resolution)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .clipShape(Capsule())

                    Button(action: {
                        viewModel.toggleFavorite(for: wallpaper)
                    }) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isFavorite ? .red : .white)
                            .padding(6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(wallpaper.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                HStack {
                    Text(wallpaper.resolution == "4K" ? "3840×2160 UHD" : "1920×1080 FHD")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("MP4")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            Divider()

            // Quick Actions
            HStack {
                Button(action: {
                    viewModel.openDetail(for: wallpaper)
                }) {
                    Text("Preview")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)

                Spacer()

                if let state = downloadState {
                    switch state {
                    case .downloading(let progress, _, _):
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(width: 80)
                    case .validating, .applying:
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 80)
                    case .completed:
                        Label("Applied", systemImage: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                    case .failed:
                        Button(action: { applyQuick() }) {
                            Text("Retry")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    case .idle:
                        applyButton
                    }
                } else {
                    applyButton
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            viewModel.openDetail(for: wallpaper)
        }
    }

    private var applyButton: some View {
        Button(action: { applyQuick() }) {
            Label("Apply", systemImage: "arrow.down.circle.fill")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.borderedProminent)
    }

    private func applyQuick() {
        Task { @MainActor in
            do {
                try await viewModel.downloadManager.downloadAndApply(
                    wallpaper: wallpaper,
                    resolution: .hd,
                    displayID: state.selectedDisplayID,
                    coordinator: state.coordinator,
                    libraryManager: state.coordinator?.libraryManager
                )
            } catch {
                state.showToast("Download failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Discover Detail Sheet View

@MainActor
public struct DiscoverDetailView: View {
    public let wallpaper: MotionBGsWallpaper
    @ObservedObject public var viewModel: DiscoverViewModel
    @ObservedObject public var state: AppState

    public var body: some View {
        let downloadState = viewModel.downloadManager.activeDownloads[wallpaper.id]
        let isFavorite = viewModel.isFavorite(id: wallpaper.id)

        VStack(spacing: 0) {
            // Top Modal Header Bar
            HStack {
                Text(wallpaper.title)
                    .font(.title3.bold())
                    .lineLimit(1)

                Spacer()

                Button("Done") {
                    viewModel.isDetailSheetPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Preview Stage
                    ZStack {
                        if viewModel.isPlayingPreview, let pl = viewModel.player {
                            VideoPlayer(player: pl)
                                .frame(height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        } else {
                            AsyncThumbnailView(url: wallpaper.thumbnailURL, viewModel: viewModel, targetSize: CGSize(width: 720, height: 405))
                                .frame(height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    Button(action: { viewModel.togglePreviewPlayback() }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "play.circle.fill")
                                                .font(.system(size: 20))
                                            Text("Play Video Preview")
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(.ultraThickMaterial)
                                        .clipShape(Capsule())
                                        .shadow(radius: 6)
                                    }
                                    .buttonStyle(.plain)
                                )
                        }

                        // Close Video Player Button overlay
                        if viewModel.isPlayingPreview {
                            VStack {
                                HStack {
                                    Spacer()
                                    Button(action: { viewModel.stopPreviewPlayback() }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(.white.opacity(0.85))
                                            .padding(12)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Spacer()
                            }
                        }
                    }

                    // Metadata Specs Grid
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Wallpaper Specifications")
                            .font(.headline)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                            specItem(title: "Resolution", value: wallpaper.resolutionFormatted, icon: "tv")
                            specItem(title: "Format", value: "MP4 Video", icon: "film")
                            specItem(title: "Hardware Accel", value: "Apple Silicon HW", icon: "cpu")
                            specItem(title: "Loop Duration", value: wallpaper.durationSeconds != nil ? String(format: "%.1f s", wallpaper.durationSeconds!) : "Seamless", icon: "repeat")
                            specItem(title: "Creator", value: wallpaper.creator ?? "MotionBGs Artist", icon: "person.crop.circle")
                            specItem(title: "Source", value: "MotionBGs.com", icon: "globe")
                        }
                    }
                    .padding(16)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Download Resolution Selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select Resolution to Apply:")
                            .font(.subheadline.bold())

                        Picker("Resolution", selection: $viewModel.selectedResolution) {
                            Text("Full HD (1080p) - Fast & Lightweight").tag(WallpaperDownloadResolution.hd)
                            if wallpaper.resolution == "4K" {
                                Text("4K UHD (2160p) - Ultra High Definition").tag(WallpaperDownloadResolution.fourK)
                            }
                        }
                        .pickerStyle(.radioGroup)
                    }

                    // Download Progress (if active)
                    if let dState = downloadState {
                        downloadStatusSection(for: dState)
                    }

                    Divider()

                    // Action Controls
                    HStack(spacing: 14) {
                        Button(action: {
                            viewModel.toggleFavorite(for: wallpaper)
                        }) {
                            Label(isFavorite ? "Favorited" : "Favorite", systemImage: isFavorite ? "heart.fill" : "heart")
                                .foregroundColor(isFavorite ? .red : .primary)
                        }
                        .buttonStyle(.bordered)

                        Button(action: {
                            NSWorkspace.shared.open(wallpaper.pageURL)
                        }) {
                            Label("View on MotionBGs", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button(action: { applyWallpaper() }) {
                            Label("Apply Wallpaper", systemImage: "arrow.down.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isApplying(downloadState))
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 640, minHeight: 600)
        .onDisappear {
            viewModel.stopPreviewPlayback()
        }
    }

    private func specItem(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
        }
    }

    private func downloadStatusSection(for dState: DownloadState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch dState {
            case .downloading(let progress, let bytesRead, let totalBytes):
                HStack {
                    Text("Downloading: \(Int(progress * 100))%")
                        .font(.caption.bold())
                    Spacer()
                    if totalBytes > 0 {
                        let readMB = Double(bytesRead) / (1024 * 1024)
                        let totalMB = Double(totalBytes) / (1024 * 1024)
                        Text(String(format: "%.1f / %.1f MB", readMB, totalMB))
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                    Button("Cancel") {
                        viewModel.downloadManager.cancelDownload(itemID: wallpaper.id)
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear)

            case .validating:
                HStack {
                    ProgressView().scaleEffect(0.6)
                    Text("Validating video file...")
                        .font(.caption)
                }

            case .applying:
                HStack {
                    ProgressView().scaleEffect(0.6)
                    Text("Applying to desktop & synchronizing widget colors...")
                        .font(.caption)
                }

            case .completed:
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Applied successfully!")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }

            case .failed(let err):
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                    Text("Error: \(err)")
                        .font(.caption)
                        .foregroundColor(.red)
                }

            case .idle:
                EmptyView()
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func isApplying(_ dState: DownloadState?) -> Bool {
        guard let d = dState else { return false }
        switch d {
        case .downloading, .validating, .applying: return true
        default: return false
        }
    }

    private func applyWallpaper() {
        viewModel.stopPreviewPlayback()
        Task { @MainActor in
            do {
                try await viewModel.downloadManager.downloadAndApply(
                    wallpaper: wallpaper,
                    resolution: viewModel.selectedResolution,
                    displayID: state.selectedDisplayID,
                    coordinator: state.coordinator,
                    libraryManager: state.coordinator?.libraryManager
                )
                viewModel.isDetailSheetPresented = false
            } catch {
                state.showToast("Failed to apply wallpaper: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Main Discover Section View

@MainActor
public struct DiscoverView: View {
    @ObservedObject public var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var viewModel: DiscoverViewModel {
        state.discoverViewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Controls Bar (Search, Category, Filter)
            VStack(alignment: .leading, spacing: 14) {
                // Header & Target Display Selector
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Discover MotionBGs")
                            .font(.system(size: 24, weight: .bold, design: .rounded))

                        Text("Browse thousands of ultra-fast 4K and Full HD animated wallpapers.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Target Display Selector
                    Menu {
                        Button("All Connected Displays") {
                            state.selectedDisplayID = nil
                        }
                        Divider()
                        ForEach(state.displays) { disp in
                            Button(disp.name + (disp.isMain ? " (Main)" : "")) {
                                state.selectedDisplayID = disp.displayID
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "display")
                            Text(targetDisplayName)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .menuStyle(.borderlessButton)
                }

                // Search Bar & Filter Picker
                HStack(spacing: 12) {
                    // Search Input
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)

                        TextField("Search MotionBGs live wallpapers...", text: Binding(
                            get: { viewModel.searchQuery },
                            set: { viewModel.searchQuery = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))

                        if !viewModel.searchQuery.isEmpty {
                            Button(action: {
                                viewModel.searchQuery = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )

                    // Filter Mode Picker
                    Picker("Filter", selection: Binding(
                        get: { viewModel.selectedFilter },
                        set: { viewModel.selectFilter($0) }
                    )) {
                        ForEach(DiscoverFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }

                // Category Pills (only active when exploring)
                if viewModel.selectedFilter == .all {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(MotionBGsCategory.allCases) { category in
                                Button(action: { viewModel.selectCategory(category) }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: category.iconName)
                                            .font(.system(size: 10))
                                        Text(category.rawValue)
                                            .font(.system(size: 12, weight: viewModel.selectedCategory == category ? .semibold : .regular))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        viewModel.selectedCategory == category
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.primary.opacity(0.04)
                                    )
                                    .foregroundColor(viewModel.selectedCategory == category ? .accentColor : .primary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Main Content Area
            ZStack {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading wallpapers from MotionBGs...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)

                        Text(error)
                            .font(.headline)

                        Button(action: { viewModel.loadInitialContent() }) {
                            Text("Retry Connection")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.dashed")
                            .font(.system(size: 38))
                            .foregroundColor(.secondary)

                        Text(viewModel.selectedFilter == .favorites ? "No favorite wallpapers yet." : "No wallpapers found.")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(.linear)
                        }

                        ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 20)], spacing: 20) {
                            ForEach(viewModel.items) { item in
                                DiscoverCardView(
                                    wallpaper: item,
                                    viewModel: viewModel,
                                    state: state
                                )
                                .onAppear {
                                    viewModel.loadNextPageIfNeeded(currentItem: item)
                                }
                            }
                        }
                        .padding(28)

                        if viewModel.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .padding(.vertical, 16)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.teardown()
        }
        .sheet(isPresented: Binding(
            get: { viewModel.isDetailSheetPresented },
            set: { viewModel.isDetailSheetPresented = $0 }
        )) {
            if let selected = viewModel.selectedWallpaper {
                DiscoverDetailView(
                    wallpaper: selected,
                    viewModel: viewModel,
                    state: state
                )
            }
        }
    }

    private var targetDisplayName: String {
        guard let id = state.selectedDisplayID else { return "All Displays" }
        return state.displays.first(where: { $0.displayID == id })?.name ?? "Display \(id)"
    }
}

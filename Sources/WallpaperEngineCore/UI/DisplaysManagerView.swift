//
//  DisplaysManagerView.swift
//  WallpaperEngineCore
//
//  Multi-monitor routing and layout canvas providing independent per-display
//  wallpaper assignment, resolution / refresh-rate detection, and layout synchronization.
//

import AppKit
import SwiftUI

@MainActor
public struct DisplaysManagerView: View {
    @ObservedObject public var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Displays & Multi-Screen")
                            .font(.system(size: 26, weight: .bold, design: .rounded))

                        Text("Manage per-display wallpaper assignment or synchronize all connected screens.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        state.selectedDisplayID = nil
                        state.applyShader(preset: state.activeShaderPreset, displayID: nil)
                    }) {
                        Label("Sync Wallpaper to All", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Displays Canvas
                displaysCanvasCard

                // Selected Display Information & Routing
                selectedDisplayRoutingCard
            }
            .padding(28)
        }
    }

    // MARK: - Displays Canvas Card

    private var displaysCanvasCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Connected Monitors (\(state.displays.count))", systemImage: "display.2")
                .font(.headline)

            HStack(spacing: 20) {
                ForEach(state.displays) { disp in
                    displayTile(for: disp)
                }
            }
            .padding(.vertical, 8)
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func displayTile(for disp: DisplayInfo) -> some View {
        let isSelected = state.selectedDisplayID == disp.displayID

        return Button(action: {
            state.selectedDisplayID = disp.displayID
        }) {
            VStack(spacing: 10) {
                // Screen Bezel
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                        .frame(width: 180, height: 110)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                        )

                    VStack(spacing: 4) {
                        Image(systemName: "display")
                            .font(.system(size: 28))
                            .foregroundColor(isSelected ? .accentColor : .secondary)

                        if disp.isMain {
                            Text("MAIN DISPLAY")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }
                }

                VStack(spacing: 2) {
                    Text(disp.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    Text("\(Int(disp.bounds.width)) × \(Int(disp.bounds.height))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)

                    if disp.refreshRate > 0 {
                        Text("\(Int(disp.refreshRate)) Hz ProMotion")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selected Display Routing Card

    private var selectedDisplayRoutingCard: some View {
        let currentID = state.selectedDisplayID
        let currentDisp = state.displays.first(where: { $0.displayID == currentID })
        let active = state.activeWallpaper(for: currentID)

        return VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Display Assignment: \(currentDisp?.name ?? "All Displays")", systemImage: "slider.horizontal.2.square")
                        .font(.headline)

                    Text("Choose which wallpaper engine to route to this specific screen. Different screens can render different procedural shaders or video streams simultaneously.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // Section 1: Procedural Shaders
            VStack(alignment: .leading, spacing: 10) {
                Text("Procedural Metal Shaders")
                    .font(.subheadline.bold())

                HStack(spacing: 12) {
                    ForEach(ProceduralShaderPreset.allCases) { preset in
                        let isSelected = active == .shader(preset)

                        Button(action: {
                            state.applyShader(preset: preset, displayID: currentID)
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "sparkles")
                                    .font(.system(size: 16))
                                    .foregroundColor(isSelected ? .green : .accentColor)
                                Text(preset.displayName)
                                    .font(.caption.weight(isSelected ? .bold : .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Section 2: Library Videos
            if !state.discoveredVideos.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Library Videos")
                        .font(.subheadline.bold())

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 12)], spacing: 12) {
                        ForEach(state.discoveredVideos) { videoItem in
                            let isSelected = active == .video(path: videoItem.url.path)

                            Button(action: {
                                state.applyVideo(url: videoItem.url, displayID: currentID)
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "film.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(isSelected ? .green : .teal)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(videoItem.title)
                                            .font(.caption.weight(isSelected ? .bold : .medium))
                                            .lineLimit(1)
                                        Text(videoItem.resolution)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(isSelected ? Color.teal.opacity(0.15) : Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isSelected ? Color.teal : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Divider()

            // Section 3: File Selectors
            HStack(spacing: 12) {
                Button(action: { selectVideoFile(for: currentID) }) {
                    Label("Choose Video File...", systemImage: "film")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)

                Button(action: { selectPhotoFile(for: currentID) }) {
                    Label("Choose Photo (3D Parallax)...", systemImage: "photo")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func selectVideoFile(for displayID: CGDirectDisplayID?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.title = "Select Video Wallpaper"
        if panel.runModal() == .OK, let url = panel.url {
            state.applyVideo(url: url, displayID: displayID)
        }
    }

    private func selectPhotoFile(for displayID: CGDirectDisplayID?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff]
        panel.title = "Select 2D Photo for 3D Parallax"
        if panel.runModal() == .OK, let url = panel.url {
            state.applyParallax(url: url, displayID: displayID)
        }
    }
}

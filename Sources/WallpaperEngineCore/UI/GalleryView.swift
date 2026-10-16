//
//  GalleryView.swift
//  WallpaperEngineCore
//
//  Visual card gallery to discover, preview, and immediately apply
//  live procedural shaders, AI 3D parallax photos, and looping video wallpapers.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public struct GalleryView: View {
    @ObservedObject public var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Banner
                headerView

                // Category Filter Bar
                categoryFilterBar

                // Cards Grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 20)], spacing: 20) {
                    if state.galleryCategory == .all || state.galleryCategory == .shaders {
                        ForEach(ProceduralShaderPreset.allCases) { preset in
                            shaderCard(for: preset)
                        }
                    }

                    if state.galleryCategory == .all || state.galleryCategory == .videos {
                        ForEach(state.discoveredVideos) { videoItem in
                            discoveredVideoCard(for: videoItem)
                        }
                        videoPickerCard
                    }

                    if state.galleryCategory == .all || state.galleryCategory == .parallax {
                        parallaxCard
                    }

                    if state.galleryCategory == .all || state.galleryCategory == .custom {
                        customShaderCard
                    }
                }
            }
            .padding(28)
        }
        .sheet(isPresented: $state.showingCustomShaderSheet) {
            customShaderSheet
        }
    }

    // MARK: - Header View

    private var targetDisplayName: String {
        guard let id = state.selectedDisplayID else { return "All Displays" }
        return state.displays.first(where: { $0.displayID == id })?.name ?? "Display \(id)"
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Wallpaper Gallery")
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                Text("Choose from real-time GPU procedural shaders, AI 3D parallax photo scenes, or hardware-accelerated looping videos.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Display Selector & Quick Controls
            HStack(spacing: 12) {
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

                Button(action: { state.togglePlayback() }) {
                    Label(state.isPlaybackPaused ? "Resume" : "Pause", systemImage: state.isPlaybackPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(state.isPlaybackPaused ? .green : .orange)

                Button(action: { state.toggleAudioReactive() }) {
                    Image(systemName: "waveform")
                        .foregroundColor(state.isAudioReactive ? .accentColor : .secondary)
                }
                .help(state.isAudioReactive ? "Audio Reactive: Active" : "Audio Reactive: Disabled")
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Category Filter Bar

    private var categoryFilterBar: some View {
        HStack(spacing: 8) {
            ForEach(GalleryCategory.allCases) { category in
                Button(action: { state.galleryCategory = category }) {
                    Text(category.rawValue)
                        .font(.system(size: 13, weight: state.galleryCategory == category ? .semibold : .regular))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            state.galleryCategory == category
                                ? Color.accentColor.opacity(0.18)
                                : Color.primary.opacity(0.04)
                        )
                        .foregroundColor(state.galleryCategory == category ? .accentColor : .primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Shader Preset Card

    private func shaderCard(for preset: ProceduralShaderPreset) -> some View {
        let isCurrentlyActive = state.activeWallpaper(for: state.selectedDisplayID) == .shader(preset)

        return VStack(alignment: .leading, spacing: 12) {
            // Live / Styled Card Banner
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(presetGradient(for: preset))
                    .frame(height: 150)
                    .overlay(
                        VStack {
                            Image(systemName: presetIcon(for: preset))
                                .font(.system(size: 44))
                                .foregroundColor(.white.opacity(0.85))
                                .shadow(radius: 6)
                        }
                    )

                if isCurrentlyActive {
                    Text("ACTIVE")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(10)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(preset.displayName)
                        .font(.headline)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                        Text("Metal GPU")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                }

                Text(presetDescription(for: preset))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    badgeView(text: "Audio-Reactive", icon: "waveform")
                    badgeView(text: "60/120 FPS", icon: "speedometer")
                }
                .padding(.top, 4)
            }

            Divider()

            HStack {
                Button(action: {
                    state.activeShaderPreset = preset
                    state.selectedTab = .studio
                }) {
                    Text("Preview")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: {
                    state.applyShader(preset: preset, displayID: state.selectedDisplayID)
                }) {
                    Label(isCurrentlyActive ? "Applied" : "Apply", systemImage: isCurrentlyActive ? "checkmark" : "arrow.up.forward.app")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isCurrentlyActive ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isCurrentlyActive ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            state.applyShader(preset: preset, displayID: state.selectedDisplayID)
        }
    }

    // MARK: - Discovered Looping Video Card

    private func discoveredVideoCard(for item: WallpaperVideoItem) -> some View {
        let isCurrentlyActive = state.activeWallpaper(for: state.selectedDisplayID) == .video(path: item.url.path)

        return VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Color.indigo.opacity(0.7), Color.teal.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 150)
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "film.stack.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.9))
                            Text(item.resolution)
                                .font(.caption2.bold())
                                .foregroundColor(.white.opacity(0.85))
                        }
                    )

                if isCurrentlyActive {
                    Text("ACTIVE")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(10)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 10))
                        Text(item.fileSizeFormatted)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                }

                Text(item.filename)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    badgeView(text: item.resolution, icon: "tv")
                    badgeView(text: "AVFoundation HW", icon: "cpu")
                }
                .padding(.top, 4)
            }

            Divider()

            HStack {
                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }) {
                    Text("Reveal")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: {
                    state.applyVideo(url: item.url, displayID: state.selectedDisplayID)
                }) {
                    Label(isCurrentlyActive ? "Applied" : "Apply", systemImage: isCurrentlyActive ? "checkmark" : "arrow.up.forward.app")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isCurrentlyActive ? Color.teal : Color.primary.opacity(0.08), lineWidth: isCurrentlyActive ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            state.applyVideo(url: item.url, displayID: state.selectedDisplayID)
        }
    }

    // MARK: - Video Import Picker Card

    private var videoPickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Color.blue.opacity(0.2), Color.teal.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 150)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 38))
                                .foregroundColor(.secondary)
                            Text("Import Custom Video")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                        }
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Select from Disk...")
                    .font(.headline)

                Text("Import any 4K/1080p MP4 or MOV file into your desktop wallpaper engine.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    badgeView(text: "MP4 / MOV", icon: "play.rectangle")
                    badgeView(text: "Zero Overhead", icon: "leaf")
                }
                .padding(.top, 4)
            }

            Divider()

            Button(action: { selectVideoFile() }) {
                Label("Browse Files...", systemImage: "folder.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            selectVideoFile()
        }
    }

    // MARK: - Parallax Card

    private var parallaxCard: some View {
        let isCurrentlyActive: Bool = {
            if case .parallax = state.activeWallpaper(for: state.selectedDisplayID) { return true }
            return false
        }()

        return VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 150)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo.stack.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.9))
                            Text("Depth Anything V2")
                                .font(.caption2.bold())
                                .foregroundColor(.white.opacity(0.8))
                        }
                    )

                if isCurrentlyActive {
                    Text("ACTIVE")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(10)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("AI 3D Parallax Photo")
                    .font(.headline)

                Text("Turns any regular 2D photo into an interactive 3D scene displaced by real-time depth estimation.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    badgeView(text: "CoreML", icon: "cpu")
                    badgeView(text: "Head/Mouse Track", icon: "cursorarrow.motionlines")
                }
                .padding(.top, 4)
            }

            Divider()

            Button(action: { selectParallaxPhoto() }) {
                Label(isCurrentlyActive ? "Change Photo..." : "Select Photo...", systemImage: "plus.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isCurrentlyActive ? Color.purple : Color.primary.opacity(0.08), lineWidth: isCurrentlyActive ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            selectParallaxPhoto()
        }
    }

    // MARK: - Custom Shader Card

    private var customShaderCard: some View {
        let isCurrentlyActive: Bool = {
            if case .customShader = state.activeWallpaper(for: state.selectedDisplayID) { return true }
            return false
        }()

        return VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Color.orange.opacity(0.6), Color.pink.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 150)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "curlybraces")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.9))
                            Text("Shadertoy / MSL")
                                .font(.caption2.bold())
                                .foregroundColor(.white.opacity(0.8))
                        }
                    )

                if isCurrentlyActive {
                    Text("ACTIVE")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(10)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Custom Shader Importer")
                    .font(.headline)

                Text("Import your own Shadertoy GLSL snippet or raw Metal Shading Language with live auto-wrapping.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    badgeView(text: "Live Compile", icon: "checkmark.seal")
                    badgeView(text: "iAudio Uniforms", icon: "waveform.badge.plus")
                }
                .padding(.top, 4)
            }

            Divider()

            HStack {
                Button(action: { selectShaderFile() }) {
                    Text("Browse...")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: { state.showingCustomShaderSheet = true }) {
                    Text("Write / Paste Code")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isCurrentlyActive ? Color.orange : Color.primary.opacity(0.08), lineWidth: isCurrentlyActive ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            state.showingCustomShaderSheet = true
        }
    }

    // MARK: - Helpers

    private func badgeView(text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.05))
        .foregroundColor(.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func presetGradient(for preset: ProceduralShaderPreset) -> LinearGradient {
        switch preset {
        case .aurora:
            return LinearGradient(colors: [Color.green.opacity(0.7), Color.teal.opacity(0.8), Color.purple.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .starfield:
            return LinearGradient(colors: [Color.black, Color.blue.opacity(0.6), Color.purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gradientFlow:
            return LinearGradient(colors: [Color.orange.opacity(0.7), Color.pink.opacity(0.7), Color.purple.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .cyberpunkGrid:
            return LinearGradient(colors: [Color.purple.opacity(0.8), Color.black, Color.cyan.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .bokeh:
            return LinearGradient(colors: [Color.pink.opacity(0.6), Color.yellow.opacity(0.6), Color.purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func presetIcon(for preset: ProceduralShaderPreset) -> String {
        switch preset {
        case .aurora: return "sparkles"
        case .starfield: return "star.fill"
        case .gradientFlow: return "paintpalette.fill"
        case .cyberpunkGrid: return "grid"
        case .bokeh: return "circle.hexagongrid.fill"
        }
    }

    private func presetDescription(for preset: ProceduralShaderPreset) -> String {
        switch preset {
        case .aurora:
            return "Vibrant northern lights curtain with glowing curtains of atmospheric ionization."
        case .starfield:
            return "Hyperspace 3D warp-speed galactic star travel with volumetric speed trails."
        case .gradientFlow:
            return "Silk-smooth flowing liquid neon gradient with organic noise transitions."
        case .cyberpunkGrid:
            return "Retro-futuristic 80s synthwave horizon grid with neon sunset perspective lines."
        case .bokeh:
            return "Floating optical out-of-focus light spheres with soft organic blending."
        }
    }

    // MARK: - File Pickers

    private func selectParallaxPhoto() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff]
        panel.title = "Select 2D Photo for 3D Parallax"

        if panel.runModal() == .OK, let url = panel.url {
            state.applyParallax(url: url, displayID: state.selectedDisplayID)
        }
    }

    private func selectVideoFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.title = "Select Video Wallpaper"

        if panel.runModal() == .OK, let url = panel.url {
            state.applyVideo(url: url, displayID: state.selectedDisplayID)
        }
    }

    private func selectShaderFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "metal") ?? .plainText,
            UTType(filenameExtension: "frag") ?? .plainText,
            UTType(filenameExtension: "glsl") ?? .plainText,
            UTType(filenameExtension: "shadertoy") ?? .plainText,
            .plainText
        ]
        panel.title = "Select Metal or Shadertoy File"

        if panel.runModal() == .OK, let url = panel.url {
            state.applyShaderFile(url: url, displayID: state.selectedDisplayID)
        }
    }

    // MARK: - Custom Shader Sheet

    private var customShaderSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Custom Shader Importer")
                    .font(.title2.bold())

                Spacer()

                Button("Cancel") {
                    state.showingCustomShaderSheet = false
                }
                .keyboardShortcut(.cancelAction)
            }

            Text("Enter a Shadertoy mainImage(...) or native Metal MSL fragment shader function. Available uniforms: iResolution, iTime, iTimeDelta, iMouse, iAudio, iBass, iMid, iTreble, iAmplitude.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $state.customShaderDraft)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if let error = state.compileErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()

                Button("Compile & Apply to Desktop") {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("custom_shader_\(UUID().uuidString).metal")
                    do {
                        try state.customShaderDraft.write(to: tempURL, atomically: true, encoding: .utf8)
                        state.applyShaderFile(url: tempURL, displayID: state.selectedDisplayID)
                        state.showingCustomShaderSheet = false
                    } catch {
                        state.compileErrorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 550, minHeight: 450)
    }
}

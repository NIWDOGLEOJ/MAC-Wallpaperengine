//
//  SettingsAboutView.swift
//  WallpaperEngineCore
//
//  About and settings dashboard displaying engine version, architecture stack,
//  configuration file location, and open-source project links.
//

import AppKit
import SwiftUI

@MainActor
public struct SettingsAboutView: View {
    @ObservedObject public var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // App Branding Hero
                heroCard

                // Architecture Stack
                architectureCard

                // Configuration Storage
                storageCard
            }
            .padding(28)
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [.accentColor, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 80, height: 80)

                Image(systemName: "sparkles.tv")
                    .font(.system(size: 40))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("MAC-Wallpaperengine")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Text("High-Performance Native macOS Live Wallpaper Engine")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Text("Version 1.2.0 (Build 453)")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)

                    Link(destination: URL(string: "https://github.com/NIWDOGLEOJ/MAC-Wallpaperengine")!) {
                        Label("GitHub Repository", systemImage: "link")
                            .font(.caption.bold())
                    }
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Architecture Card

    private var architectureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Native Technologies & Architecture", systemImage: "cpu.fill")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                techRow(tech: "Swift 6", desc: "100% strict concurrency safety across actors and background threads")
                Divider()
                techRow(tech: "Apple Metal", desc: "Hardware-accelerated procedural shaders, MTKView, and 3D vertex mesh displacement")
                Divider()
                techRow(tech: "Accelerate vDSP", desc: "1024-point complex FFT audio frequency decomposition into 16 equalizer bands")
                Divider()
                techRow(tech: "ScreenCaptureKit", desc: "Zero-latency system audio output tap with organic 120 BPM rhythmic fallback")
                Divider()
                techRow(tech: "CoreML", desc: "Depth Anything V2 monocular depth estimation for AI 3D parallax photo scenes")
                Divider()
                techRow(tech: "AppKit & IOKit", desc: "kCGDesktopWindowLevelKey anchoring, space persistence, and power observers")
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

    private func techRow(tech: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(tech)
                .font(.subheadline.bold())
                .frame(width: 140, alignment: .leading)

            Text(desc)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Storage Card

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Configuration & Local Persistence", systemImage: "externaldrive.fill")
                .font(.headline)

            let path = ("~/.config/WallpaperEngineCore/config.json" as NSString).expandingTildeInPath

            VStack(alignment: .leading, spacing: 6) {
                Text("Configuration File:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(path)
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button(action: {
                    let folderURL = URL(fileURLWithPath: path).deletingLastPathComponent()
                    NSWorkspace.shared.open(folderURL)
                }) {
                    Label("Reveal in Finder", systemImage: "folder")
                }

                Spacer()

                Button("Reset Configuration to Defaults") {
                    state.config = EngineConfig.default
                    state.coordinator?.updateConfig { cfg in
                        cfg = EngineConfig.default
                    }
                    state.showToast("Configuration reset to default settings")
                }
                .foregroundColor(.red)
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
}

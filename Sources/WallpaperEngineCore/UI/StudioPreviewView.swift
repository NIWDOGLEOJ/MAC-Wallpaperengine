//
//  StudioPreviewView.swift
//  WallpaperEngineCore
//
//  Full interactive live stage previewing procedural shaders, audio reactions,
//  and speed adjustments before applying them to the desktop.
//

import AppKit
import SwiftUI

@MainActor
public struct StudioPreviewView: View {
    @ObservedObject public var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Main Live Viewport
            ZStack(alignment: .bottom) {
                // Live interactive Metal shader rendering view
                LiveShaderPreviewRepresentable(
                    preset: state.activeShaderPreset,
                    customSource: nil,
                    speed: state.previewSpeed,
                    audioSpectrum: state.isAudioPreviewActive ? state.audioSpectrum : nil,
                    isPaused: state.isPausedLocally
                )
                .ignoresSafeArea()

                // Floating Glassmorphic Control Overlay
                controlBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            state.previewSpeed = state.shaderSpeed
            state.isAudioPreviewActive = state.isAudioReactive
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 20) {
            // Play / Pause Local Preview
            Button(action: { state.isPausedLocally.toggle() }) {
                Image(systemName: state.isPausedLocally ? "play.fill" : "pause.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(state.isPausedLocally ? "Resume preview animation" : "Pause preview animation")

            // Preset Picker
            Picker("", selection: $state.activeShaderPreset) {
                ForEach(ProceduralShaderPreset.allCases, id: \.self) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)

            Divider()
                .frame(height: 24)

            // Speed Multiplier Slider
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.needle")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Slider(value: $state.previewSpeed, in: 0.1...3.0, step: 0.1) {
                    Text("Speed")
                }
                .frame(width: 100)

                Text(String(format: "%.1fx", state.previewSpeed))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .leading)
            }

            Divider()
                .frame(height: 24)

            // Audio-Reactive Toggle with mini visualizer icon
            Button(action: { state.isAudioPreviewActive.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .foregroundColor(state.isAudioPreviewActive ? .accentColor : .secondary)
                    Text("Audio Reactive")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(state.isAudioPreviewActive ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            // Target Monitor Selector
            Menu {
                Button("All Displays") {
                    state.selectedDisplayID = nil
                }
                Divider()
                ForEach(state.displays) { disp in
                    Button(disp.name) {
                        state.selectedDisplayID = disp.displayID
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "display")
                    Text(targetDisplayName)
                        .font(.caption.weight(.medium))
                }
            }
            .frame(maxWidth: 160)

            // Main Apply Button
            Button(action: {
                state.setShaderSpeed(state.previewSpeed)
                if state.isAudioReactive != state.isAudioPreviewActive {
                    state.toggleAudioReactive()
                }
                state.applyShader(preset: state.activeShaderPreset, displayID: state.selectedDisplayID)
            }) {
                Label("Set as Wallpaper", systemImage: "arrow.up.forward.app.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 6)
        )
    }

    private var targetDisplayName: String {
        guard let id = state.selectedDisplayID else { return "All Displays" }
        return state.displays.first(where: { $0.displayID == id })?.name ?? "Display \(id)"
    }
}

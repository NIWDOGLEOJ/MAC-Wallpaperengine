//
//  AppMainView.swift
//  WallpaperEngineCore
//
//  Master NavigationSplitView layout coordinating the translucent sidebar,
//  detail views, live status toolbar, and floating toast notifications.
//

import AppKit
import SwiftUI

@MainActor
public struct AppMainView: View {
    @ObservedObject public var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        NavigationSplitView {
            // Sidebar
            List(NavigationTab.allCases, selection: $state.selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.title, systemImage: tab.iconName)
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
            .listStyle(.sidebar)
        } detail: {
            // Detail View Stage
            ZStack(alignment: .bottom) {
                Group {
                    switch state.selectedTab {
                    case .gallery:
                        GalleryView(state: state)
                    case .studio:
                        StudioPreviewView(state: state)
                    case .audio:
                        AudioVisualizerView(state: state)
                    case .hud:
                        DesktopHUDStudioView(state: state)
                    case .displays:
                        DisplaysManagerView(state: state)
                    case .performance:
                        PerformanceView(state: state)
                    case .settings:
                        SettingsAboutView(state: state)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Toast Notification Banner
                if let message = state.toastMessage {
                    toastBanner(message: message)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Quick Play/Pause
                Button(action: { state.togglePlayback() }) {
                    Image(systemName: state.isPlaybackPaused ? "play.fill" : "pause.fill")
                        .foregroundColor(state.isPlaybackPaused ? .green : .primary)
                }
                .help(state.isPlaybackPaused ? "Resume Wallpaper Playback" : "Pause Wallpaper Playback")

                // Quick Audio Reactive Toggle
                Button(action: { state.toggleAudioReactive() }) {
                    Image(systemName: "waveform")
                        .foregroundColor(state.isAudioReactive ? .accentColor : .secondary)
                }
                .help(state.isAudioReactive ? "Audio Reactive: Active" : "Audio Reactive: Disabled")

                // FPS & Power Status Pill
                HStack(spacing: 8) {
                    Circle()
                        .fill(state.isPlaybackPaused ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)

                    Text("\(state.telemetry.fps) FPS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Toast Banner

    private func toastBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

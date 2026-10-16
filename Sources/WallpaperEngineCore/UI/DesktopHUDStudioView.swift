//
//  DesktopHUDStudioView.swift
//  WallpaperEngineCore
//
//  WYSIWYG visual configurator for the glassmorphic desktop HUD & widget overlay,
//  including interactive screen anchor placement and widget customization toggles.
//

import AppKit
import SwiftUI

@MainActor
public struct DesktopHUDStudioView: View {
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
                        Text("Desktop HUD & Widgets")
                            .font(.system(size: 26, weight: .bold, design: .rounded))

                        Text("Glassmorphic desktop overlay with live clock, system stats, music card, and audio visualizer. 100% event passthrough behind icons.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("Enable Desktop HUD", isOn: Binding(
                        get: { state.config.hudConfig.isEnabled },
                        set: { val in
                            state.updateHUDConfig { $0.isEnabled = val }
                        }
                    ))
                    .toggleStyle(.switch)
                }

                // Interactive WYSIWYG Screen Anchor Mockup
                screenAnchorMockupCard

                // Widget Toggles & Scale Customizer
                widgetOptionsCard
            }
            .padding(28)
        }
    }

    // MARK: - Interactive Screen Anchor Mockup

    private var screenAnchorMockupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Desktop Placement & Anchor", systemImage: "macwindow.badge.plus")
                    .font(.headline)

                Spacer()

                Text("Click any corner to reposition the live HUD")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Visual Screen Canvas
            ZStack {
                // Mock Display Bezel
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.85))
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(maxHeight: 260)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 2)
                    )

                // Simulated Desktop Wallpaper inside bezel
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [.indigo.opacity(0.4), .purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(8)

                // Interactive Anchor Target Hotspots
                VStack {
                    HStack {
                        anchorButton(position: .topLeft, label: "Top Left")
                        Spacer()
                        anchorButton(position: .topCenter, label: "Top Center")
                        Spacer()
                        anchorButton(position: .topRight, label: "Top Right")
                    }
                    Spacer()
                    HStack {
                        anchorButton(position: .bottomLeft, label: "Bottom Left")
                        Spacer()
                        anchorButton(position: .bottomRight, label: "Bottom Right")
                    }
                }
                .padding(24)

                // Mini Animated HUD Card representation at selected position
                miniHUDPreview
                    .padding(18)
            }
            .frame(maxWidth: .infinity)

            // Dynamic Wallpaper Color & Theme Sync Banner
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(state.activeWallpaperAccentColor))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                    .shadow(color: Color(state.activeWallpaperAccentColor).opacity(0.6), radius: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Dynamic Wallpaper Accent Synchronized")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Widget spectrum, telemetry badges, and accents adapt in real time to the active wallpaper. Theme syncs with macOS Light/Dark preferences.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 12))
                    Text("macOS Auto-Sync")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.08))
                .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func anchorButton(position: EngineConfig.HUDConfig.HUDPosition, label: String) -> some View {
        let isSelected = state.config.hudConfig.position == position

        return Button(action: {
            state.updateHUDConfig { $0.position = position }
        }) {
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color(state.activeWallpaperAccentColor) : Color.primary.opacity(0.25))
                .foregroundColor(.white)
                .clipShape(Capsule())
                .shadow(radius: isSelected ? 4 : 0)
        }
        .buttonStyle(.plain)
    }

    // Mini preview card rendered on top of the mockup
    private var miniHUDPreview: some View {
        let pos = state.config.hudConfig.position
        let accent = Color(state.activeWallpaperAccentColor)

        return GeometryReader { geo in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Circle().fill(accent).frame(width: 5, height: 5)
                    Text("10:42 PM")
                        .font(.system(size: 9, weight: .bold))
                }

                HStack(spacing: 4) {
                    Text("CPU: 18%").font(.system(size: 7)).foregroundColor(accent)
                    Text("RAM: 8.4GB").font(.system(size: 7)).foregroundColor(.secondary)
                }

                if state.config.hudConfig.showNowPlaying {
                    Text("♪ Starboy - The Weeknd")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(accent)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accent.opacity(0.35), lineWidth: 1)
            )
            .shadow(radius: 6)
            .frame(width: 110)
            .position(miniHUDCoordinates(for: pos, in: geo.size))
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: pos)
        }
    }

    private func miniHUDCoordinates(for pos: EngineConfig.HUDConfig.HUDPosition, in size: CGSize) -> CGPoint {
        let marginX: CGFloat = 65
        let marginY: CGFloat = 35

        switch pos {
        case .topLeft: return CGPoint(x: marginX, y: marginY)
        case .topCenter: return CGPoint(x: size.width / 2.0, y: marginY)
        case .topRight: return CGPoint(x: size.width - marginX, y: marginY)
        case .bottomLeft: return CGPoint(x: marginX, y: size.height - marginY)
        case .bottomRight: return CGPoint(x: size.width - marginX, y: size.height - marginY)
        }
    }

    // MARK: - Widget Options Card

    private var widgetOptionsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Widget Components & Appearance", systemImage: "checklist")
                .font(.headline)

            VStack(spacing: 12) {
                widgetToggleRow(title: "Time & Clock", subtitle: "Live hour, minute, and second display", isOn: Binding(
                    get: { state.config.hudConfig.showClock },
                    set: { val in state.updateHUDConfig { $0.showClock = val } }
                ))

                Divider()

                widgetToggleRow(title: "Date Display", subtitle: "Current weekday, month, and day", isOn: Binding(
                    get: { state.config.hudConfig.showDate },
                    set: { val in state.updateHUDConfig { $0.showDate = val } }
                ))

                Divider()

                widgetToggleRow(title: "System Hardware Telemetry", subtitle: "Mach host CPU %, physical RAM, and live rendering FPS", isOn: Binding(
                    get: { state.config.hudConfig.showSystemStats },
                    set: { val in state.updateHUDConfig { $0.showSystemStats = val } }
                ))

                Divider()

                widgetToggleRow(title: "Now Playing Card", subtitle: "Currently playing track from Spotify and Apple Music", isOn: Binding(
                    get: { state.config.hudConfig.showNowPlaying },
                    set: { val in state.updateHUDConfig { $0.showNowPlaying = val } }
                ))

                Divider()

                widgetToggleRow(title: "16-Band Audio Visualizer", subtitle: "Live equalizer spectrum bars pulsing behind desktop icons", isOn: Binding(
                    get: { state.config.hudConfig.showAudioVisualizer },
                    set: { val in state.updateHUDConfig { $0.showAudioVisualizer = val } }
                ))
            }

            Divider()

            // Scale Slider
            HStack {
                Text("HUD Card Scale")
                    .font(.subheadline)

                Spacer()

                Slider(value: Binding(
                    get: { Double(state.config.hudConfig.scale) },
                    set: { val in state.updateHUDConfig { $0.scale = Float(val) } }
                ), in: 0.8...1.5, step: 0.05)
                .frame(width: 160)

                Text(String(format: "%.0f%%", state.config.hudConfig.scale * 100))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 44, alignment: .trailing)
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

    private func widgetToggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
        }
    }
}

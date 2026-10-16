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

                // Dynamic Wallpaper Theme Studio
                wallpaperThemeStudioCard

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
        let theme = state.activeWallpaperTheme
        let accent = theme.accentSwiftUIColor
        let surface = theme.surfaceSwiftUIColor.opacity(state.config.hudConfig.themeSettings.backgroundOpacity)
        let border = theme.borderSwiftUIColor
        let textPri = theme.textPrimarySwiftUIColor
        let textSec = theme.textSecondarySwiftUIColor

        return GeometryReader { geo in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Circle().fill(accent).frame(width: 5, height: 5)
                    Text("10:42 PM")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(textPri)
                }

                HStack(spacing: 3) {
                    Text("CPU: 18%").font(.system(size: 6)).foregroundColor(accent)
                    Text("GPU: 24%").font(.system(size: 6)).foregroundColor(accent)
                    Text("RAM: 8.4G").font(.system(size: 6)).foregroundColor(textSec)
                }

                if state.config.hudConfig.showNowPlaying {
                    Text("♪ Starboy - The Weeknd")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(accent)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(border, lineWidth: 1)
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

                widgetToggleRow(title: "System Hardware Telemetry", subtitle: "Mach host CPU %, Apple GPU load %, physical RAM, and live rendering FPS", isOn: Binding(
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

    // MARK: - Dynamic Wallpaper Theme Studio Card

    private var wallpaperThemeStudioCard: some View {
        let theme = state.activeWallpaperTheme
        let settings = state.config.hudConfig.themeSettings

        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Dynamic Wallpaper Theme Studio", systemImage: "paintpalette.fill")
                    .font(.headline)
                    .foregroundColor(theme.accentSwiftUIColor)

                Spacer()

                // WCAG AA Badge
                HStack(spacing: 5) {
                    Image(systemName: theme.contrastRatio >= 4.5 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(theme.contrastRatio >= 4.5 ? theme.successSwiftUIColor : theme.warningSwiftUIColor)
                        .font(.system(size: 11))
                    Text("WCAG AA \(String(format: "%.1f:1", theme.contrastRatio))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    Text(theme.isDark ? "• Dark" : "• Light")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(theme.surfaceSwiftUIColor.opacity(0.6))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(theme.borderSwiftUIColor, lineWidth: 1))
            }

            Text("Intelligent color extraction adapting widget background, borders, text, and spectrum to any active wallpaper.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Live Semantic Palette Swatches
            HStack(spacing: 8) {
                paletteSwatch(name: "Primary", color: theme.primarySwiftUIColor)
                paletteSwatch(name: "Secondary", color: theme.secondarySwiftUIColor)
                paletteSwatch(name: "Accent", color: theme.accentSwiftUIColor)
                paletteSwatch(name: "Surface", color: theme.surfaceSwiftUIColor)
                paletteSwatch(name: "Border", color: theme.borderSwiftUIColor)
                paletteSwatch(name: "Text", color: theme.textPrimarySwiftUIColor)
            }
            .padding(.vertical, 4)

            Divider()

            // Mode Selector
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Adaptation Mode")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { state.config.hudConfig.themeSettings.mode },
                        set: { newMode in state.updateThemeSettings { $0.mode = newMode } }
                    )) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }

                Text(settings.mode.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Surface Appearance & Accent Vibrancy
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Surface Tone")
                        .font(.subheadline.weight(.medium))
                    Picker("", selection: Binding(
                        get: { state.config.hudConfig.themeSettings.appearancePreference },
                        set: { newPref in state.updateThemeSettings { $0.appearancePreference = newPref } }
                    )) {
                        ForEach(AppearancePreference.allCases) { pref in
                            Text(pref.rawValue).tag(pref)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Accent Intensity")
                        .font(.subheadline.weight(.medium))
                    Picker("", selection: Binding(
                        get: { state.config.hudConfig.themeSettings.accentIntensity },
                        set: { newInt in state.updateThemeSettings { $0.accentIntensity = newInt } }
                    )) {
                        ForEach(AccentIntensity.allCases) { intensity in
                            Text(intensity.rawValue).tag(intensity)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // Background Glass Opacity Slider
            HStack {
                Text("Glass Surface Opacity")
                    .font(.subheadline)
                Spacer()
                Slider(value: Binding(
                    get: { state.config.hudConfig.themeSettings.backgroundOpacity },
                    set: { val in state.updateThemeSettings { $0.backgroundOpacity = val } }
                ), in: 0.20...1.00, step: 0.05)
                .frame(width: 160)

                Text(String(format: "%.0f%%", state.config.hudConfig.themeSettings.backgroundOpacity * 100))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 44, alignment: .trailing)
            }

            // Live Sampling Interval Slider (Mode B)
            if settings.mode == .liveAdaptive || settings.mode == .automatic {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Video Sampling Interval")
                            .font(.subheadline)
                        Text("Cadence for sampling video frames without GPU stalls")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Slider(value: Binding(
                        get: { state.config.hudConfig.themeSettings.liveUpdateInterval },
                        set: { val in state.updateThemeSettings { $0.liveUpdateInterval = val } }
                    ), in: 1.0...10.0, step: 0.5)
                    .frame(width: 160)

                    Text(String(format: "%.1fs", state.config.hudConfig.themeSettings.liveUpdateInterval))
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 44, alignment: .trailing)
                }
            }

            Divider()

            // Palette Lock & Reset Buttons
            HStack(spacing: 16) {
                Toggle("Lock Current Palette", isOn: Binding(
                    get: { state.config.hudConfig.themeSettings.isLocked },
                    set: { locked in
                        if locked {
                            state.lockCurrentTheme()
                        } else {
                            state.resetThemeToAutomatic()
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.subheadline)

                Spacer()

                Button(action: {
                    state.resetThemeToAutomatic()
                }) {
                    Label("Reset to Wallpaper Auto", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
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

    private func paletteSwatch(name: String, color: Color) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: color.opacity(0.3), radius: 3, x: 0, y: 1)

            Text(name)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

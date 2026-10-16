//
//  PerformanceView.swift
//  WallpaperEngineCore
//
//  Hardware telemetry dashboard and power management controls
//  governing frame rates, battery throttling, and sleep/occlusion rules.
//

import AppKit
import SwiftUI

@MainActor
public struct PerformanceView: View {
    @ObservedObject public var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Performance & Power")
                        .font(.system(size: 26, weight: .bold, design: .rounded))

                    Text("Fine-tune rendering frame rates and automatic power saving rules for battery life and efficiency.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Live Hardware Telemetry
                liveTelemetryCard

                // Engine Architecture & GPU Acceleration (CPU-Only 0% GPU option)
                engineArchitectureCard

                // Target Frame Rate Card
                frameRateCard

                // Intelligent Power Rules Card
                powerRulesCard
            }
            .padding(28)
        }
    }

    // MARK: - Live Hardware Telemetry Card

    private var liveTelemetryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Live Hardware Telemetry", systemImage: "gauge.with.needle.fill")
                .font(.headline)

            HStack(spacing: 14) {
                // Rendering FPS
                telemetryGauge(
                    title: "Rendering Frame Rate",
                    valueString: "\(state.telemetry.fps) FPS",
                    subtitle: state.telemetry.fps >= 100 ? "ProMotion High Refresh" : "Standard 60Hz Refresh",
                    color: .green
                )

                // Host CPU %
                telemetryGauge(
                    title: "Host CPU Usage",
                    valueString: String(format: "%.1f%%", state.telemetry.cpuPercentage),
                    subtitle: "Mach host thread probe",
                    color: .blue
                )

                // Apple GPU %
                telemetryGauge(
                    title: "Apple GPU Usage",
                    valueString: String(format: "%.1f%%", state.telemetry.gpuPercentage),
                    subtitle: "IOKit accelerator pipe",
                    color: .orange
                )

                // Host Physical RAM
                telemetryGauge(
                    title: "Physical RAM Used",
                    valueString: String(format: "%.1f GB", state.telemetry.ramUsedGB),
                    subtitle: String(format: "of %.1f GB Total (%.0f%%)", state.telemetry.ramTotalGB, state.telemetry.ramPercentage),
                    color: .purple
                )
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

    private func telemetryGauge(title: String, valueString: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(valueString)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(color)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Engine Architecture & Hardware Acceleration Card

    private var engineArchitectureCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Engine Architecture & GPU Acceleration", systemImage: "cpu.fill")
                    .font(.headline)

                Spacer()

                if state.config.useCPUOnlyEngine {
                    HStack(spacing: 5) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("0% GPU Guaranteed • Ultra-Lightweight")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("Metal GPU Accelerated")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            Text("Choose between pure software CPU rendering (strictly 0% GPU load with < 1.5% CPU footprint) or hardware Metal GPU acceleration.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                // CPU-Only Button
                Button(action: {
                    state.setCPUOnlyEngine(true)
                }) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "leaf.fill")
                                .foregroundColor(state.config.useCPUOnlyEngine ? .green : .secondary)
                            Text("CPU-Only Mode (0% GPU)")
                                .font(.system(size: 13, weight: .bold))
                            Spacer()
                            if state.config.useCPUOnlyEngine {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        Text("100% software Core Graphics rendering. Completely bypasses GPU, MTKView, and hardware shaders. Uses < 1.5% CPU on Apple Silicon.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                    .padding(14)
                    .background(state.config.useCPUOnlyEngine ? Color.green.opacity(0.1) : Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(state.config.useCPUOnlyEngine ? Color.green : Color.primary.opacity(0.08), lineWidth: state.config.useCPUOnlyEngine ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)

                // GPU Metal Button
                Button(action: {
                    state.setCPUOnlyEngine(false)
                }) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(!state.config.useCPUOnlyEngine ? .orange : .secondary)
                            Text("Metal GPU Mode")
                                .font(.system(size: 13, weight: .bold))
                            Spacer()
                            if !state.config.useCPUOnlyEngine {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                        Text("Hardware-accelerated Metal shading language and CoreAnimation pipeline for full rasterization.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                    .padding(14)
                    .background(!state.config.useCPUOnlyEngine ? Color.orange.opacity(0.1) : Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(!state.config.useCPUOnlyEngine ? Color.orange : Color.primary.opacity(0.08), lineWidth: !state.config.useCPUOnlyEngine ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
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

    // MARK: - Target Frame Rate Card

    private var frameRateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Target Frame Rate", systemImage: "speedometer")
                .font(.headline)

            Text("Specifies the maximum display refresh rate for procedural shaders and video playback. On ProMotion displays (120Hz), wallpaper engine renders up to 120 FPS smoothly.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                fpsButton(fps: 30, label: "30 FPS\nPower Saver")
                fpsButton(fps: 60, label: "60 FPS\nStandard")
                fpsButton(fps: 120, label: "120 FPS\nProMotion")
                fpsButton(fps: 144, label: "144 FPS\nHigh Refresh")
                fpsButton(fps: 240, label: "240 FPS\nUltra Refresh")
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

    private func fpsButton(fps: Int, label: String) -> some View {
        let isSelected = state.config.targetFrameRate == fps

        return Button(action: {
            state.setTargetFrameRate(fps)
        }) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Color.accentColor : Color.primary.opacity(0.04))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Intelligent Power Rules Card

    private var powerRulesCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Intelligent Power & Environment Rules", systemImage: "bolt.batteryblock.fill")
                .font(.headline)

            VStack(spacing: 12) {
                ruleToggleRow(
                    title: "Pause on Battery Power",
                    subtitle: "Immediately suspends rendering when disconnecting from AC power adapter",
                    isOn: Binding(
                        get: { state.config.pauseOnBattery },
                        set: { val in state.updatePowerConfig { $0.pauseOnBattery = val } }
                    )
                )

                Divider()

                ruleToggleRow(
                    title: "Throttle on Battery Power",
                    subtitle: "Reduces rendering frame rate to 30 FPS when running on battery to conserve charge",
                    isOn: Binding(
                        get: { state.config.throttleOnBattery },
                        set: { val in state.updatePowerConfig { $0.throttleOnBattery = val } }
                    )
                )

                Divider()

                ruleToggleRow(
                    title: "Pause on Low Power Mode",
                    subtitle: "Automatically pauses rendering when macOS Low Power Mode is activated",
                    isOn: Binding(
                        get: { state.config.pauseOnLowPowerMode },
                        set: { val in state.updatePowerConfig { $0.pauseOnLowPowerMode = val } }
                    )
                )

                Divider()

                ruleToggleRow(
                    title: "Pause on Screen Lock",
                    subtitle: "Suspends playback when Mac is locked (com.apple.screenIsLocked)",
                    isOn: Binding(
                        get: { state.config.pauseOnScreenLock },
                        set: { val in state.updatePowerConfig { $0.pauseOnScreenLock = val } }
                    )
                )

                Divider()

                ruleToggleRow(
                    title: "Pause on Display Sleep",
                    subtitle: "Suspends GPU rendering immediately when displays power down",
                    isOn: Binding(
                        get: { state.config.pauseOnDisplaySleep },
                        set: { val in state.updatePowerConfig { $0.pauseOnDisplaySleep = val } }
                    )
                )

                Divider()

                ruleToggleRow(
                    title: "Pause when Desktop is Occluded",
                    subtitle: "Zero GPU usage when full-screen applications or windows completely cover the desktop",
                    isOn: Binding(
                        get: { state.config.pauseWhenOccluded },
                        set: { val in state.updatePowerConfig { $0.pauseWhenOccluded = val } }
                    )
                )
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

    private func ruleToggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
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

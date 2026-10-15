//
//  AudioVisualizerView.swift
//  WallpaperEngineCore
//
//  Dedicated audio-reactive monitor showcasing live 16-band FFT decomposition,
//  Now Playing media cards (Spotify & Apple Music), and shader uniform parameter telemetry.
//

import AppKit
import SwiftUI

@MainActor
public struct AudioVisualizerView: View {
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
                        Text("Audio Reactive Visualizer")
                            .font(.system(size: 26, weight: .bold, design: .rounded))

                        Text("Captures system audio output via ScreenCaptureKit and decomposes it into 16 frequency bands via Accelerate vDSP FFT.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("Enable Reactive Pulses", isOn: Binding(
                        get: { state.isAudioReactive },
                        set: { _ in state.toggleAudioReactive() }
                    ))
                    .toggleStyle(.switch)
                }

                // Now Playing Media Card
                nowPlayingCard

                // 16-Band Live Spectrum Analyzer
                spectrumCard

                // Live Audio Uniform Parameters
                uniformsTelemetryCard
            }
            .padding(28)
        }
    }

    // MARK: - Now Playing Card

    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Currently Playing Media", systemImage: "music.note")
                    .font(.headline)

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(state.nowPlaying.isPlaying ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)

                    Text(state.nowPlaying.source)
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
            }

            HStack(spacing: 16) {
                // Album Art Placeholder
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "music.note.list")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.85))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.nowPlaying.title.isEmpty ? "No active audio stream detected" : state.nowPlaying.title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)

                    Text(state.nowPlaying.artist.isEmpty ? "Launch Spotify or Apple Music to drive visualizer" : "\(state.nowPlaying.artist) • \(state.nowPlaying.album)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if state.nowPlaying.duration > 0 {
                        ProgressView(value: state.nowPlaying.playbackPosition, total: state.nowPlaying.duration)
                            .progressViewStyle(.linear)
                            .padding(.top, 4)
                    }
                }

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

    // MARK: - Spectrum Card

    private var spectrumCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("16-Band Equalizer Spectrum", systemImage: "chart.bar.xaxis")
                    .font(.headline)

                Spacer()

                Text("vDSP 1024-pt FFT @ 48 kHz")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Real-Time Animated Equalizer Bars
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<min(16, state.audioSpectrum.bands.count), id: \.self) { index in
                    let value = CGFloat(state.audioSpectrum.bands[index])
                    VStack {
                        Spacer()

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [Color.cyan, Color.purple, Color.pink],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(height: max(6, value * 140))
                            .animation(.easeOut(duration: 0.08), value: value)

                        Text("\(index + 1)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 160)
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

    // MARK: - Uniforms Telemetry Card

    private var uniformsTelemetryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Shader Uniform Parameters", systemImage: "slider.horizontal.3")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                uniformGauge(label: "iBass (Kick / 808 / Sub)", value: state.audioSpectrum.bass, color: .purple)
                uniformGauge(label: "iMid (Vocals / Melody)", value: state.audioSpectrum.mid, color: .blue)
                uniformGauge(label: "iTreble (Hi-Hat / Air)", value: state.audioSpectrum.treble, color: .cyan)
                uniformGauge(label: "iAmplitude (Total RMS Energy)", value: state.audioSpectrum.amplitude, color: .green)
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

    private func uniformGauge(label: String, value: Float, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundColor(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(1.0, max(0.0, value))))
                        .animation(.easeOut(duration: 0.08), value: value)
                }
            }
            .frame(height: 8)
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

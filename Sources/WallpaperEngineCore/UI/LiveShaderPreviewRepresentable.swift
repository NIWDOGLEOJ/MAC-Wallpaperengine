//
//  LiveShaderPreviewRepresentable.swift
//  WallpaperEngineCore
//
//  SwiftUI NSViewRepresentable wrapper that embeds an interactive
//  ShaderWallpaperView inside any SwiftUI view hierarchy.
//

import AppKit
import Foundation
import SwiftUI

@MainActor
public struct LiveShaderPreviewRepresentable: NSViewRepresentable {
    public let preset: ProceduralShaderPreset?
    public let customSource: String?
    public let speed: Float
    public let audioSpectrum: AudioSpectrumData?
    public let isPaused: Bool

    public init(
        preset: ProceduralShaderPreset? = .aurora,
        customSource: String? = nil,
        speed: Float = 1.0,
        audioSpectrum: AudioSpectrumData? = nil,
        isPaused: Bool = false
    ) {
        self.preset = preset
        self.customSource = customSource
        self.speed = speed
        self.audioSpectrum = audioSpectrum
        self.isPaused = isPaused
    }

    public func makeNSView(context: Context) -> ShaderWallpaperView {
        let view = ShaderWallpaperView(frame: .zero)
        applyConfiguration(to: view)
        return view
    }

    public func updateNSView(_ nsView: ShaderWallpaperView, context: Context) {
        applyConfiguration(to: nsView)
    }

    private func applyConfiguration(to view: ShaderWallpaperView) {
        if let custom = customSource, !custom.isEmpty {
            if view.currentSourcePath != custom {
                try? view.loadShader(source: custom)
            }
        } else if let p = preset {
            if view.currentPreset != p {
                try? view.loadPreset(p)
            }
        }

        view.setSpeed(speed)

        if let spectrum = audioSpectrum {
            view.updateAudio(spectrum: spectrum)
        }

        if isPaused {
            view.pause()
        } else {
            view.resume()
        }
    }
}

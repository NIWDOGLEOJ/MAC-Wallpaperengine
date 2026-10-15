//
//  AudioSpectrumData.swift
//  WallpaperEngineCore
//
//  Real-time audio spectrum telemetry and frequency band decomposition
//  for audio-reactive shaders and glassmorphic desktop visualizer widgets.
//

import Foundation
import simd

/// Decomposed audio frequency energy and spectrum telemetry.
public struct AudioSpectrumData: Sendable, Equatable {
    /// Normalized sub-bass & bass energy (approx 20 Hz - 250 Hz), range: 0.0 ... 1.0.
    public var bass: Float

    /// Normalized midrange energy (approx 250 Hz - 4,000 Hz), range: 0.0 ... 1.0.
    public var mid: Float

    /// Normalized high-frequency energy (approx 4,000 Hz - 16,000 Hz), range: 0.0 ... 1.0.
    public var treble: Float

    /// Overall RMS audio amplitude / energy volume, range: 0.0 ... 1.0.
    public var amplitude: Float

    /// 16 discrete logarithmic frequency bands for equalizer bars, each in range 0.0 ... 1.0.
    public var bands: [Float]

    /// Raw root-mean-square amplitude before auto-gain scaling.
    public var rawRMS: Float

    /// Returns a 16-byte aligned SIMD4 vector `(bass, mid, treble, amplitude)`
    /// suitable for direct streaming into Metal constant buffer uniforms.
    public var asSIMD4: SIMD4<Float> {
        SIMD4<Float>(bass, mid, treble, amplitude)
    }

    public static let silent = AudioSpectrumData(
        bass: 0.0,
        mid: 0.0,
        treble: 0.0,
        amplitude: 0.0,
        bands: Array(repeating: 0.0, count: 16),
        rawRMS: 0.0
    )

    public init(
        bass: Float = 0.0,
        mid: Float = 0.0,
        treble: Float = 0.0,
        amplitude: Float = 0.0,
        bands: [Float] = Array(repeating: 0.0, count: 16),
        rawRMS: Float = 0.0
    ) {
        self.bass = max(0.0, min(1.0, bass))
        self.mid = max(0.0, min(1.0, mid))
        self.treble = max(0.0, min(1.0, treble))
        self.amplitude = max(0.0, min(1.0, amplitude))
        if bands.count == 16 {
            self.bands = bands.map { max(0.0, min(1.0, $0)) }
        } else {
            var padded = bands.prefix(16).map { max(0.0, min(1.0, $0)) }
            while padded.count < 16 { padded.append(0.0) }
            self.bands = padded
        }
        self.rawRMS = rawRMS
    }
}

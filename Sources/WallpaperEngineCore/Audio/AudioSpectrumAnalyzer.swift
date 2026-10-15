//
//  AudioSpectrumAnalyzer.swift
//  WallpaperEngineCore
//
//  Hardware-accelerated Fast Fourier Transform (FFT) spectrum analyzer
//  using Apple Accelerate vDSP for real-time audio reactivity.
//

import Accelerate
import Foundation
import simd

public final class AudioSpectrumAnalyzer: @unchecked Sendable {
    private let lock = NSLock()

    public let fftSize: Int
    private let log2n: vDSP_Length
    private let halfSize: Int
    private let fftSetup: FFTSetup

    private var window: [Float]
    private let realp: UnsafeMutablePointer<Float>
    private let imagp: UnsafeMutablePointer<Float>
    private var splitComplex: DSPSplitComplex

    // Ballistics & Temporal Smoothing
    private var smoothedBands: [Float]
    private var smoothedBass: Float = 0.0
    private var smoothedMid: Float = 0.0
    private var smoothedTreble: Float = 0.0
    private var smoothedAmplitude: Float = 0.0

    // Auto Gain Control
    private var peakEnvelope: Float = 0.05
    private let sampleRate: Float

    public init(fftSize: Int = 1024, sampleRate: Float = 48000.0) {
        self.fftSize = fftSize
        self.sampleRate = sampleRate
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.halfSize = fftSize / 2

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("Failed to allocate Accelerate FFTSetup")
        }
        self.fftSetup = setup

        // Initialize Hann window
        var win = [Float](repeating: 0.0, count: fftSize)
        vDSP_hann_window(&win, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.window = win

        self.realp = UnsafeMutablePointer<Float>.allocate(capacity: halfSize)
        self.realp.initialize(repeating: 0.0, count: halfSize)
        self.imagp = UnsafeMutablePointer<Float>.allocate(capacity: halfSize)
        self.imagp.initialize(repeating: 0.0, count: halfSize)
        self.splitComplex = DSPSplitComplex(realp: realp, imagp: imagp)

        self.smoothedBands = [Float](repeating: 0.0, count: 16)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
        realp.deinitialize(count: halfSize)
        realp.deallocate()
        imagp.deinitialize(count: halfSize)
        imagp.deallocate()
    }

    /// Processes an incoming batch of PCM Float32 audio samples and returns
    /// normalized frequency band and energy telemetry.
    public func process(samples: [Float]) -> AudioSpectrumData {
        guard samples.count >= fftSize else {
            return lock.withLock {
                AudioSpectrumData(
                    bass: smoothedBass * 0.9,
                    mid: smoothedMid * 0.9,
                    treble: smoothedTreble * 0.9,
                    amplitude: smoothedAmplitude * 0.9,
                    bands: smoothedBands.map { $0 * 0.9 },
                    rawRMS: 0.0
                )
            }
        }

        // 1. Calculate raw RMS volume
        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(min(samples.count, fftSize)))

        // 2. Apply Hann Windowing
        var windowed = [Float](repeating: 0.0, count: fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        return lock.withLock {
            // 3. Pack into Split Complex buffer
            windowed.withUnsafeBytes { rawBuffer in
                let complexPtr = rawBuffer.bindMemory(to: DSPComplex.self)
                vDSP_ctoz(complexPtr.baseAddress!, 2, &splitComplex, 1, vDSP_Length(halfSize))
            }

            // 4. Perform In-Place Real FFT
            vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

            // 5. Compute Squared Magnitudes
            var magnitudes = [Float](repeating: 0.0, count: halfSize)
            vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))

            // Scale factor: 1.0 / (2 * fftSize)
            var scale = 1.0 / Float(2 * fftSize)
            vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfSize))

            // 6. Partition into 16 Logarithmic Frequency Bands
            // Bin resolution = sampleRate / fftSize (e.g. 48000 / 1024 = 46.875 Hz per bin)
            let rawBands = compute16Bands(magnitudes: magnitudes)

            // Dynamic Auto Gain Control envelope follower
            let currentPeak = max(rawBands.max() ?? 0.001, rms * 2.0)
            if currentPeak > peakEnvelope {
                peakEnvelope = peakEnvelope * 0.7 + currentPeak * 0.3
            } else {
                peakEnvelope = max(0.01, peakEnvelope * 0.985)
            }

            let normalizedBands = rawBands.map { val in
                min(1.0, max(0.0, sqrt(val / peakEnvelope)))
            }

            // 7. Aggregate Musical Energy Bands
            // Sub-bass & Bass: Bands 0..3 (approx 20 Hz - 250 Hz)
            let bassEnergy = (normalizedBands[0...3].reduce(0, +) / 4.0) * 1.2
            // Midrange: Bands 4..9 (approx 250 Hz - 4000 Hz)
            let midEnergy = normalizedBands[4...9].reduce(0, +) / 6.0
            // Treble: Bands 10..15 (approx 4000 Hz - 16000 Hz)
            let trebleEnergy = (normalizedBands[10...15].reduce(0, +) / 6.0) * 1.1

            let normalizedRMS = min(1.0, max(0.0, rms / (peakEnvelope * 0.5)))

            // 8. Ballistics: Fast Attack (0.85), Smooth Exponential Decay (0.15)
            applyBallistics(to: &smoothedBass, target: bassEnergy)
            applyBallistics(to: &smoothedMid, target: midEnergy)
            applyBallistics(to: &smoothedTreble, target: trebleEnergy)
            applyBallistics(to: &smoothedAmplitude, target: normalizedRMS)

            for i in 0..<16 {
                applyBallistics(to: &smoothedBands[i], target: normalizedBands[i])
            }

            return AudioSpectrumData(
                bass: smoothedBass,
                mid: smoothedMid,
                treble: smoothedTreble,
                amplitude: smoothedAmplitude,
                bands: smoothedBands,
                rawRMS: rms
            )
        }
    }

    private func compute16Bands(magnitudes: [Float]) -> [Float] {
        var bands = [Float](repeating: 0.0, count: 16)

        // Logarithmic bin intervals across halfSize (512 bins)
        // Band edges approximately map to 31Hz, 63Hz, 125Hz, 250Hz, 500Hz, 1kHz, 2kHz, 4kHz, 8kHz, 16kHz
        let binRanges: [(Int, Int)] = [
            (1, 2),     // Band 0: Sub-bass ~30-60Hz
            (2, 4),     // Band 1: Bass ~60-120Hz
            (4, 7),     // Band 2: Punch ~120-200Hz
            (7, 11),    // Band 3: Low mid ~200-350Hz
            (11, 16),   // Band 4: Mid ~350-500Hz
            (16, 24),   // Band 5: Mid ~500-750Hz
            (24, 35),   // Band 6: Mid ~750-1100Hz
            (35, 50),   // Band 7: Upper mid ~1.1k-1.6kHz
            (50, 70),   // Band 8: Presence ~1.6k-2.3kHz
            (70, 100),  // Band 9: Presence ~2.3k-3.3kHz
            (100, 140), // Band 10: High mid ~3.3k-4.6kHz
            (140, 190), // Band 11: Highs ~4.6k-6.2kHz
            (190, 250), // Band 12: Highs ~6.2k-8.2kHz
            (250, 320), // Band 13: Brilliance ~8.2k-10.5kHz
            (320, 400), // Band 14: Air ~10.5k-13kHz
            (400, 511)  // Band 15: Super air ~13k-16.7kHz
        ]

        for (idx, range) in binRanges.enumerated() {
            let start = min(range.0, halfSize - 1)
            let end = min(range.1, halfSize - 1)
            var sum: Float = 0.0
            var count: Float = 0.0
            for i in start...end {
                sum += magnitudes[i]
                count += 1.0
            }
            bands[idx] = count > 0 ? (sum / count) : 0.0
        }

        return bands
    }

    private func applyBallistics(to current: inout Float, target: Float) {
        if target > current {
            current = current * 0.15 + target * 0.85 // Immediate Attack
        } else {
            current = current * 0.82 + target * 0.18 // Smooth Exponential Decay
        }
    }
}

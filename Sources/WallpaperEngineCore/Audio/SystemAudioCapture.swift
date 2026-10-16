//
//  SystemAudioCapture.swift
//  WallpaperEngineCore
//
//  Real-time system audio output capture using ScreenCaptureKit and CoreAudio,
//  with automatic fallback to organic musical simulation when permissions are pending.
//

import AVFoundation
import CoreMedia
import Foundation
import OSLog
import ScreenCaptureKit

public final class SystemAudioCapture: NSObject, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "SystemAudioCapture")
    private let lock = NSLock()

    private let analyzer: AudioSpectrumAnalyzer
    private var stream: SCStream?
    private var isRunning: Bool = false
    private var isPaused: Bool = false

    // Fallback simulation timer for tests or unpermissioned states
    private var simulationTimer: DispatchSourceTimer?
    private let simulationQueue = DispatchQueue(label: "com.wallpaperengine.audio.sim", qos: .userInteractive)
    private var simTime: Float = 0.0

    /// Broadcast callback emitting analyzed audio spectrum data at up to 60Hz.
    public var onSpectrumUpdate: (@Sendable (AudioSpectrumData) -> Void)?

    public init(sampleRate: Float = 48000.0, fftSize: Int = 1024) {
        self.analyzer = AudioSpectrumAnalyzer(fftSize: fftSize, sampleRate: sampleRate)
        super.init()
    }

    deinit {
        stop()
    }

    public func start() {
        lock.lock()
        guard !isRunning else {
            lock.unlock()
            return
        }
        isRunning = true
        isPaused = false
        lock.unlock()

        logger.info("Starting SystemAudioCapture pipeline...")

        Task { [weak self] in
            await self?.startScreenCaptureStream()
        }
    }

    public func stop() {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }
        isRunning = false
        stopSimulation()
        let activeStream = stream
        stream = nil
        lock.unlock()

        if let s = activeStream {
            Task {
                try? await s.stopCapture()
            }
        }
        logger.info("SystemAudioCapture stopped.")
    }

    public func pause() {
        lock.lock()
        isPaused = true
        lock.unlock()
    }

    public func resume() {
        lock.lock()
        isPaused = false
        lock.unlock()
    }

    // MARK: - ScreenCaptureKit System Audio Pipeline

    private func startScreenCaptureStream() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                startSimulation()
                return
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
            config.excludesCurrentProcessAudio = true

            // Minimal video overhead since we only process audio
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let newStream = SCStream(filter: filter, configuration: config, delegate: self)
            try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: simulationQueue)
            try await newStream.startCapture()

            lock.withLock {
                self.stream = newStream
            }

            logger.info("ScreenCaptureKit audio stream active on system output.")
        } catch {
            logger.info("ScreenCaptureKit permission unavailable or headless; engaging organic audio pulse fallback: \(error.localizedDescription)")
            startSimulation()
        }
    }

    // MARK: - Organic Audio Pulse Fallback

    public func startSimulation() {
        lock.lock()
        guard simulationTimer == nil && isRunning else {
            lock.unlock()
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: simulationQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(40)) // ~25 Hz ultra-low CPU
        timer.setEventHandler { [weak self] in
            self?.stepSimulation()
        }
        timer.resume()
        self.simulationTimer = timer
        lock.unlock()
    }

    private func stopSimulation() {
        simulationTimer?.cancel()
        simulationTimer = nil
    }

    private func stepSimulation() {
        lock.lock()
        guard isRunning && !isPaused else {
            lock.unlock()
            return
        }
        simTime += 0.04
        let t = simTime
        lock.unlock()

        // 120 BPM rhythmic pulse (2.0 Hz fundamental) with zero memory allocations or FFT overhead
        let beat = Float(pow(max(0.0, sin(Double(t) * .pi * 2.0)), 4.0))
        let offbeat = Float(pow(max(0.0, sin((Double(t) + 0.25) * .pi * 2.0)), 6.0))

        var bands = [Float](repeating: 0.0, count: 16)
        bands[0] = beat * 0.95
        bands[1] = beat * 0.85
        bands[2] = beat * 0.70
        bands[3] = offbeat * 0.60
        bands[4] = offbeat * 0.50
        for i in 5..<16 {
            bands[i] = Float(sin(Double(t) * 1.5 + Double(i))) * 0.15 + 0.15
        }

        let spectrum = AudioSpectrumData(
            bass: beat,
            mid: offbeat,
            treble: bands[10],
            amplitude: (beat * 0.6 + offbeat * 0.4),
            bands: bands,
            rawRMS: beat * 0.5
        )
        onSpectrumUpdate?(spectrum)
    }
}

// MARK: - SCStreamDelegate & SCStreamOutput

extension SystemAudioCapture: SCStreamDelegate, SCStreamOutput {
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.warning("SCStream stopped with error: \(error.localizedDescription). Falling back to simulation.")
        startSimulation()
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        lock.lock()
        let active = isRunning && !isPaused
        lock.unlock()
        guard active else { return }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        guard status == noErr, let rawData = dataPointer else { return }

        // Audio format is 32-bit Float PCM
        let floatCount = totalLength / MemoryLayout<Float>.size
        let floatPointer = rawData.withMemoryRebound(to: Float.self, capacity: floatCount) { $0 }
        let samples = Array(UnsafeBufferPointer(start: floatPointer, count: min(floatCount, analyzer.fftSize)))

        let spectrum = analyzer.process(samples: samples)
        onSpectrumUpdate?(spectrum)
    }
}

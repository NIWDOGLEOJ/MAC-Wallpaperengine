import AVFoundation
import Foundation
import os
import simd
import Vision

/// Tracks the user's face position via the built-in FaceTime / webcam using Apple's Vision framework,
/// mapping head movements to natural 3D parallax perspective shifts.
public final class VisionHeadTrackingDriver: NSObject, ParallaxTrackingDriver, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "VisionHeadTrackingDriver")
    private let lock = NSLock()

    // Configuration
    public var sensitivity: Float = 1.4
    public var smoothingFactor: Float = 0.12
    public var invertX: Bool = true // Invert so looking left reveals what is behind foreground objects on the right
    public var invertY: Bool = false

    // State
    private var _targetOffset: SIMD2<Float> = .zero
    private var _currentOffset: SIMD2<Float> = .zero
    private var isRunning: Bool = false
    public private(set) var isCameraAvailable: Bool = false

    private var captureSession: AVCaptureSession?
    private let captureQueue = DispatchQueue(label: "com.wallpaperengine.parallax.vision", qos: .userInteractive)
    private var sequenceHandler = VNSequenceRequestHandler()

    public var onOffsetUpdate: (@Sendable (SIMD2<Float>) -> Void)?

    public var currentOffset: SIMD2<Float> {
        lock.lock()
        defer { lock.unlock() }
        return _currentOffset
    }

    public override init() {
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
        lock.unlock()

        logger.info("Initializing VisionHeadTrackingDriver...")

        captureQueue.async { [weak self] in
            self?.setupCaptureSession()
        }
    }

    public func stop() {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }
        isRunning = false
        lock.unlock()

        logger.info("Stopping VisionHeadTrackingDriver")

        captureQueue.async { [weak self] in
            if let session = self?.captureSession, session.isRunning {
                session.stopRunning()
            }
            self?.captureSession = nil
        }
    }

    /// Manually update target offset (useful for synthetic testing or manual positioning)
    public func setTarget(x: Float, y: Float) {
        lock.lock()
        _targetOffset = SIMD2<Float>(
            max(-1.0, min(1.0, x)),
            max(-1.0, min(1.0, y))
        )
        let delta = _targetOffset - _currentOffset
        _currentOffset += delta * smoothingFactor
        let newOffset = _currentOffset
        let callback = onOffsetUpdate
        lock.unlock()
        callback?(newOffset)
    }

    private func setupCaptureSession() {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard authStatus == .authorized || authStatus == .notDetermined else {
            logger.warning("Camera access not authorized (\(String(describing: authStatus))). Head tracking inactive.")
            return
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) ??
                          AVCaptureDevice.default(for: .video) else {
            logger.warning("No camera device found for head tracking.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            let session = AVCaptureSession()
            session.sessionPreset = .vga640x480 // Low resolution is ideal for fast face detection with minimal CPU

            if session.canAddInput(input) {
                session.addInput(input)
            }

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: captureQueue)

            if session.canAddOutput(output) {
                session.addOutput(output)
            }

            self.captureSession = session
            self.isCameraAvailable = true
            session.startRunning()
            logger.info("Vision head tracking camera capture session running.")
        } catch {
            logger.error("Failed to initialize capture session: \(error.localizedDescription)")
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceRectanglesRequest { [weak self] (req, err) in
            guard let self = self, err == nil,
                  let results = req.results as? [VNFaceObservation],
                  let primaryFace = results.first else {
                return
            }

            self.processFaceObservation(primaryFace)
        }

        try? sequenceHandler.perform([request], on: pixelBuffer)
    }

    private func processFaceObservation(_ face: VNFaceObservation) {
        // Vision bounding box is in normalized coordinates (0,0 bottom-left to 1,1 top-right)
        let box = face.boundingBox
        let faceCenterX = Float(box.midX)
        let faceCenterY = Float(box.midY)

        // Map [0.0, 1.0] -> [-1.0, 1.0]
        var normX = (faceCenterX - 0.5) * 2.0 * sensitivity
        var normY = (faceCenterY - 0.5) * 2.0 * sensitivity

        if invertX { normX = -normX }
        if invertY { normY = -normY }

        lock.lock()
        _targetOffset = SIMD2<Float>(
            max(-1.0, min(1.0, normX)),
            max(-1.0, min(1.0, normY))
        )

        // Apply smooth low-pass interpolation
        let delta = _targetOffset - _currentOffset
        _currentOffset += delta * smoothingFactor
        let newOffset = _currentOffset
        let callback = onOffsetUpdate
        lock.unlock()

        callback?(newOffset)
    }
}

//
//  ShaderWallpaperView.swift
//  WallpaperEngineCore
//
//  AppKit NSView hosting an MTKView for real-time procedural and imported
//  Metal / Shadertoy wallpaper rendering behind desktop icons.
//

import AppKit
import Foundation
import MetalKit
import os

@MainActor
public final class ShaderWallpaperView: NSView {
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "ShaderWallpaperView")

    private var mtkView: MTKView?
    public private(set) var renderer: MetalShaderRenderer?
    private final class EventMonitorToken: @unchecked Sendable {
        private var monitor: Any?

        init(monitor: Any?) {
            self.monitor = monitor
        }

        func stop() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        deinit {
            stop()
        }
    }

    private var monitorToken: EventMonitorToken?

    public var currentPreset: ProceduralShaderPreset?
    public var currentSourcePath: String?

    public var speed: Float {
        get { renderer?.speed ?? 1.0 }
        set { renderer?.setSpeed(newValue) }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        guard let device = MTLCreateSystemDefaultDevice() else {
            logger.error("Failed to initialize system default Metal device.")
            return
        }

        let mtk = MTKView(frame: bounds, device: device)
        mtk.autoresizingMask = [.width, .height]
        mtk.colorPixelFormat = .bgra8Unorm
        mtk.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        mtk.preferredFramesPerSecond = 60
        mtk.isPaused = false
        mtk.enableSetNeedsDisplay = false

        guard let rend = MetalShaderRenderer(device: device) else {
            logger.error("Failed to initialize MetalShaderRenderer.")
            return
        }

        mtk.delegate = rend
        addSubview(mtk)

        self.mtkView = mtk
        self.renderer = rend

        setupMouseTracking()
    }

    private func setupMouseTracking() {
        let rend = self.renderer
        let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            guard let self = self, let rend = rend else { return }
            let windowLoc = event.locationInWindow
            let viewSize = self.bounds.size
            if viewSize.width > 0 && viewSize.height > 0 {
                let normX = Float(windowLoc.x)
                let normY = Float(windowLoc.y)
                rend.updateMouse(normalizedPos: SIMD2<Float>(normX, normY), isDown: event.type != .mouseMoved)
            }
        }
        self.monitorToken = EventMonitorToken(monitor: monitor)
    }

    // MARK: - Public API

    /// Loads a built-in procedural preset.
    public func loadPreset(_ preset: ProceduralShaderPreset) throws {
        guard let rend = renderer else { return }
        try rend.loadPreset(preset)
        self.currentPreset = preset
        self.currentSourcePath = nil
        logger.info("Loaded procedural preset: \(preset.displayName)")
    }

    /// Loads custom Metal or Shadertoy shader source.
    public func loadShader(source: String) throws {
        guard let rend = renderer else { return }
        try rend.loadShader(source: source)
        self.currentPreset = nil
        self.currentSourcePath = nil
        logger.info("Loaded custom shader source (\(source.count) characters)")
    }

    /// Loads custom shader source from a local file (.metal, .frag, .glsl, .shadertoy, .txt).
    public func loadShader(from fileURL: URL) throws {
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        try loadShader(source: source)
        self.currentSourcePath = fileURL.path
        logger.info("Loaded shader from file: \(fileURL.lastPathComponent)")
    }

    /// Updates playback speed multiplier.
    public func setSpeed(_ speed: Float) {
        renderer?.setSpeed(speed)
    }

    /// Sets the target frame rate (e.g. 60, 120, 144, 30).
    public func setTargetFrameRate(_ fps: Int) {
        mtkView?.preferredFramesPerSecond = max(1, fps)
    }

    /// Pauses rendering to achieve 0% GPU usage.
    public func pause() {
        mtkView?.isPaused = true
        renderer?.pause()
    }

    /// Resumes rendering.
    public func resume() {
        renderer?.resume()
        mtkView?.isPaused = false
    }
}

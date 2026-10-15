//
//  MetalShaderRenderer.swift
//  WallpaperEngineCore
//
//  Hardware-accelerated Metal renderer executing procedural and imported
//  Shadertoy shaders at native refresh rates with zero CPU overhead.
//

import AppKit
import Foundation
import Metal
import MetalKit
import os

public enum ShaderCompilationError: Error, LocalizedError {
    case libraryCreationFailed(String)
    case missingFunction(String)
    case pipelineCreationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .libraryCreationFailed(let msg):
            return "Metal shader library compilation failed: \(msg)"
        case .missingFunction(let fn):
            return "Required shader function '\(fn)' not found in library"
        case .pipelineCreationFailed(let msg):
            return "Render pipeline state creation failed: \(msg)"
        }
    }
}

public final class MetalShaderRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "MetalShaderRenderer")
    private let lock = NSLock()

    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?

    // Time & Playback Tracking
    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var lastFrameTime: CFTimeInterval = CACurrentMediaTime()
    private var accumulatedTime: Float = 0.0
    private var frameCounter: UInt32 = 0
    private var isPaused: Bool = false
    public var speed: Float = 1.0

    // Uniforms
    private var currentMouse: SIMD4<Float> = .zero
    private var customParams: SIMD4<Float> = SIMD4<Float>(1.0, 0.0, 0.0, 0.0)

    public init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let dev = device, let queue = dev.makeCommandQueue() else {
            return nil
        }
        self.device = dev
        self.commandQueue = queue
        super.init()
    }

    // MARK: - Shader Compilation & Hot Reloading

    /// Compiles and hot-swaps a procedural or imported Shadertoy Metal shader.
    public func loadShader(source: String) throws {
        let preparedSource = ShadertoyCompatibility.prepareSource(source)

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: preparedSource, options: nil)
        } catch {
            logger.error("Failed to compile shader source: \(error.localizedDescription)")
            throw ShaderCompilationError.libraryCreationFailed(error.localizedDescription)
        }

        guard let vertexFunction = library.makeFunction(name: "proceduralVertexShader") else {
            throw ShaderCompilationError.missingFunction("proceduralVertexShader")
        }

        guard let fragmentFunction = library.makeFunction(name: "proceduralFragmentShader") else {
            throw ShaderCompilationError.missingFunction("proceduralFragmentShader")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        let newPipeline: MTLRenderPipelineState
        do {
            newPipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            logger.error("Failed to create render pipeline: \(error.localizedDescription)")
            throw ShaderCompilationError.pipelineCreationFailed(error.localizedDescription)
        }

        lock.lock()
        self.pipelineState = newPipeline
        lock.unlock()

        logger.info("Procedural shader successfully compiled and active.")
    }

    /// Loads a built-in procedural preset.
    public func loadPreset(_ preset: ProceduralShaderPreset) throws {
        try loadShader(source: preset.metalSource)
    }

    // MARK: - State & Controls

    public func pause() {
        lock.lock()
        isPaused = true
        lock.unlock()
    }

    public func resume() {
        lock.lock()
        isPaused = false
        lastFrameTime = CACurrentMediaTime()
        lock.unlock()
    }

    public func setSpeed(_ newSpeed: Float) {
        lock.lock()
        speed = max(0.01, newSpeed)
        lock.unlock()
    }

    public func updateMouse(normalizedPos: SIMD2<Float>, isDown: Bool) {
        lock.lock()
        currentMouse.x = normalizedPos.x
        currentMouse.y = normalizedPos.y
        if isDown {
            currentMouse.z = normalizedPos.x
            currentMouse.w = normalizedPos.y
        }
        lock.unlock()
    }

    public func setCustomParam(index: Int, value: Float) {
        lock.lock()
        if index >= 0 && index < 4 {
            customParams[index] = value
        }
        lock.unlock()
    }

    public func updateAudio(spectrum: AudioSpectrumData) {
        lock.lock()
        customParams = spectrum.asSIMD4
        lock.unlock()
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Automatically handled by view.drawableSize in draw
    }

    public func draw(in view: MTKView) {
        lock.lock()
        let paused = isPaused
        guard !paused, let pipeline = pipelineState else {
            lock.unlock()
            return
        }

        let now = CACurrentMediaTime()
        let delta = Float(now - lastFrameTime)
        lastFrameTime = now

        accumulatedTime += delta * speed
        frameCounter &+= 1

        let drawableSize = view.drawableSize
        let res = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))

        let nowCalendar = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let dateVec = SIMD4<Float>(
            Float(nowCalendar.year ?? 2026),
            Float(nowCalendar.month ?? 1),
            Float(nowCalendar.day ?? 1),
            Float((nowCalendar.hour ?? 0) * 3600 + (nowCalendar.minute ?? 0) * 60 + (nowCalendar.second ?? 0))
        )

        var uniforms = ShaderUniforms(
            resolution: res,
            time: accumulatedTime,
            timeDelta: delta,
            mouse: currentMouse,
            date: dateVec,
            customParams: customParams,
            frameIndex: frameCounter,
            speed: speed,
            pad1: 0.0,
            pad2: 0.0
        )
        lock.unlock()

        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        renderEncoder.setRenderPipelineState(pipeline)
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 0)

        // Draw full-screen single triangle
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

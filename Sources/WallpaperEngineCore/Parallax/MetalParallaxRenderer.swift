import AppKit
import Metal
import MetalKit
import os
import simd

public struct ParallaxUniforms {
    public var pointerOffset: SIMD2<Float>
    public var depthIntensity: Float
    public var focalDepth: Float
    public var zoom: Float
    public var aspectRatio: Float

    public init(
        pointerOffset: SIMD2<Float> = .zero,
        depthIntensity: Float = 0.04,
        focalDepth: Float = 0.5,
        zoom: Float = 1.06,
        aspectRatio: Float = 1.0
    ) {
        self.pointerOffset = pointerOffset
        self.depthIntensity = depthIntensity
        self.focalDepth = focalDepth
        self.zoom = zoom
        self.aspectRatio = aspectRatio
    }
}

/// Metal renderer responsible for executing 3D raymarched depth-displacement parallax shaders
/// at native display refresh rates (60/120 Hz) with near-zero CPU footprint.
public final class MetalParallaxRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "MetalParallaxRenderer")
    private let lock = NSLock()

    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var samplerState: MTLSamplerState?

    private var colorTexture: MTLTexture?
    private var depthTexture: MTLTexture?

    public var uniforms: ParallaxUniforms = ParallaxUniforms()

    public static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    struct ParallaxUniforms {
        float2 pointerOffset;
        float depthIntensity;
        float focalDepth;
        float zoom;
        float aspectRatio;
    };

    vertex VertexOut parallaxVertex(uint vertexID [[vertex_id]]) {
        VertexOut out;
        float2 positions[6] = {
            float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
            float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0)
        };
        float2 uvs[6] = {
            float2(0.0, 1.0), float2(1.0, 1.0), float2(0.0, 0.0),
            float2(0.0, 0.0), float2(1.0, 1.0), float2(1.0, 0.0)
        };
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = uvs[vertexID];
        return out;
    }

    fragment float4 parallaxFragment(VertexOut in [[stage_in]],
                                     texture2d<float> colorTexture [[texture(0)]],
                                     texture2d<float> depthTexture [[texture(1)]],
                                     sampler s [[sampler(0)]],
                                     constant ParallaxUniforms &u [[buffer(0)]]) {
        // Correct aspect ratio and apply slight overscan zoom to eliminate edge border clipping
        float2 uv = (in.uv - 0.5) / u.zoom + 0.5;

        // Sample initial depth disparity
        float rawDepth = depthTexture.sample(s, uv).r;
        float depthDelta = rawDepth - u.focalDepth;
        float2 sampleUV = uv - u.pointerOffset * depthDelta * u.depthIntensity;

        // 4-step iterative relief refinement to eliminate perspective occlusion tears
        for (int i = 0; i < 4; i++) {
            float d = depthTexture.sample(s, sampleUV).r;
            float newDelta = d - u.focalDepth;
            sampleUV = uv - u.pointerOffset * newDelta * u.depthIntensity;
        }

        sampleUV = clamp(sampleUV, float2(0.001), float2(0.999));
        return colorTexture.sample(s, sampleUV);
    }
    """

    public init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let dev = device, let queue = dev.makeCommandQueue() else {
            return nil
        }
        self.device = dev
        self.commandQueue = queue
        super.init()

        setupPipeline()
    }

    private func setupPipeline() {
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let vertexFunction = library.makeFunction(name: "parallaxVertex"),
                  let fragmentFunction = library.makeFunction(name: "parallaxFragment") else {
                logger.error("Failed to find shader functions in Metal library.")
                return
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)

            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.minFilter = .linear
            samplerDescriptor.magFilter = .linear
            samplerDescriptor.sAddressMode = .clampToEdge
            samplerDescriptor.tAddressMode = .clampToEdge
            self.samplerState = device.makeSamplerState(descriptor: samplerDescriptor)

            logger.info("MetalParallaxRenderer pipeline initialized successfully.")
        } catch {
            logger.error("Failed to build Metal parallax pipeline: \(error.localizedDescription)")
        }
    }

    /// Sets the color image texture and depth map texture to render.
    public func setTextures(color: MTLTexture, depth: MTLTexture) {
        lock.lock()
        self.colorTexture = color
        self.depthTexture = depth
        lock.unlock()
    }

    /// Updates the normalized parallax offset vector.
    public func updateOffset(_ offset: SIMD2<Float>) {
        lock.lock()
        self.uniforms.pointerOffset = offset
        lock.unlock()
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        lock.lock()
        if size.height > 0 {
            self.uniforms.aspectRatio = Float(size.width / size.height)
        }
        lock.unlock()
    }

    public func draw(in view: MTKView) {
        lock.lock()
        guard let pipeline = pipelineState,
              let sampler = samplerState,
              let colorTex = colorTexture,
              let depthTex = depthTexture,
              let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            lock.unlock()
            return
        }

        var currentUniforms = uniforms
        lock.unlock()

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(colorTex, index: 0)
        encoder.setFragmentTexture(depthTex, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&currentUniforms, length: MemoryLayout<ParallaxUniforms>.size, index: 0)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

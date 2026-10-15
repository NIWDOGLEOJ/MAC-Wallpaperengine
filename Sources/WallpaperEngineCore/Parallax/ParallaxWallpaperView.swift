import AppKit
import Metal
import MetalKit
import os

/// High-performance AppKit view hosting the Metal-rendered 3D parallax photo scene.
/// Embeds inside a `DesktopWindow` to present interactive depth wallpapers beneath desktop icons.
public final class ParallaxWallpaperView: NSView {
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "ParallaxWallpaperView")

    private var mtkView: MTKView?
    private var renderer: MetalParallaxRenderer?
    private var activeDriver: ParallaxTrackingDriver?
    private let depthEstimator = DepthEstimator()

    public private(set) var isReady: Bool = false

    public init(frame: NSRect, device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        super.init(frame: frame)
        setupMetal(device: device)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMetal(device: MTLCreateSystemDefaultDevice())
    }

    private func setupMetal(device: MTLDevice?) {
        guard let dev = device, let rend = MetalParallaxRenderer(device: dev) else {
            logger.error("Failed to initialize Metal device or renderer for parallax scene.")
            return
        }

        self.renderer = rend

        let metalView = MTKView(frame: bounds, device: dev)
        metalView.delegate = rend
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.preferredFramesPerSecond = 60
        metalView.autoresizingMask = [.width, .height]
        metalView.enableSetNeedsDisplay = false
        metalView.isPaused = false

        addSubview(metalView)
        self.mtkView = metalView
    }

    /// Loads a 2D photograph from disk, infers its depth map using DepthAnythingV2,
    /// and uploads both textures to Metal for interactive 3D rendering.
    public func loadPhoto(from url: URL) async throws {
        guard let dev = renderer?.device else { return }

        logger.info("Processing photo for 3D parallax scene: \(url.path)")

        // 1. Load Color Texture
        let textureLoader = MTKTextureLoader(device: dev)
        let colorTexture = try await textureLoader.newTexture(
            URL: url,
            options: [
                .SRGB: false,
                .generateMipmaps: false
            ]
        )

        // 2. Estimate Depth Map via DepthAnythingV2 CoreML
        let depthBox = try await depthEstimator.estimateDepth(forImageAt: url, device: dev)
        let depthTexture = depthBox.texture

        // 3. Bind to Renderer
        self.renderer?.setTextures(color: colorTexture, depth: depthTexture)
        self.isReady = true
        logger.info("3D Parallax Photo Scene successfully loaded and active.")
    }

    /// Attaches an active tracking driver (mouse pointer or webcam head tracking) to drive the 3D perspective tilt.
    public func attachDriver(_ driver: ParallaxTrackingDriver) {
        self.activeDriver?.stop()
        self.activeDriver = driver

        let rend = self.renderer
        driver.onOffsetUpdate = { offset in
            rend?.updateOffset(offset)
        }

        driver.start()
        logger.info("Attached parallax tracking driver: \(String(describing: type(of: driver)))")
    }

    /// Pauses rendering to eliminate GPU consumption when display is sleeping or occluded.
    public func pause() {
        mtkView?.isPaused = true
    }

    /// Resumes active rendering.
    public func resume() {
        mtkView?.isPaused = false
    }

    /// Dynamically throttles rendering frame rate (e.g. 30 FPS on battery, 60/120 FPS on AC power).
    public func setTargetFrameRate(_ fps: Int) {
        mtkView?.preferredFramesPerSecond = max(10, min(120, fps))
    }

    deinit {
        activeDriver?.stop()
    }
}

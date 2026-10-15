import AppKit
import CoreGraphics
import CoreML
import CoreVideo
import CryptoKit
import Foundation
import Metal
import os

/// Hardware-accelerated depth estimation using the Depth Anything V2 Small (Float16) CoreML model.
/// Analyzes 2D photographic images and produces high-resolution disparity/depth maps for 3D parallax rendering.
public actor DepthEstimator {
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "DepthEstimator")

    public static let targetInputWidth = 518
    public static let targetInputHeight = 392

    private var loadedModel: MLModel?
    private var modelURL: URL?

    public init(customModelURL: URL? = nil) {
        self.modelURL = customModelURL ?? Self.discoverModelURL()
    }

    /// Discovers the DepthAnythingV2 model from standard search locations.
    public static func discoverModelURL() -> URL? {
        let candidates: [URL] = [
            Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlmodelc"),
            Bundle.main.resourceURL?.appendingPathComponent("DepthAnythingV2SmallF16.mlmodelc"),
            Bundle.main.resourceURL?.appendingPathComponent("Models/DepthAnythingV2SmallF16.mlmodelc"),
            URL(fileURLWithPath: "Resources/Models/DepthAnythingV2SmallF16.mlmodelc"),
            URL(fileURLWithPath: "/Applications/Walyro.app/Contents/Resources/DepthAnythingV2SmallF16.mlmodelc"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/WallpaperEngine/Models/DepthAnythingV2SmallF16.mlmodelc")
        ].compactMap { $0 }

        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// Preloads the CoreML model into memory on Neural Engine / GPU compute units.
    public func preload() throws {
        _ = try getOrLoadModel()
    }

    private func getOrLoadModel() throws -> MLModel {
        if let model = loadedModel {
            return model
        }

        guard let url = modelURL, FileManager.default.fileExists(atPath: url.path) else {
            throw DepthEstimationError.modelNotFound(modelURL?.path ?? "unknown")
        }

        logger.info("Loading DepthAnythingV2 CoreML model from \(url.path)...")
        let config = MLModelConfiguration()
        config.computeUnits = .all

        let model = try MLModel(contentsOf: url, configuration: config)
        self.loadedModel = model
        logger.info("DepthAnythingV2 CoreML model ready on Apple Silicon compute units.")
        return model
    }

/// Sendable wrapper around MTLTexture to allow safe boundary crossing in Swift 6 concurrency.
public struct MetalTextureBox: @unchecked Sendable {
    public let texture: MTLTexture
    public init(_ texture: MTLTexture) {
        self.texture = texture
    }
}

    /// Estimates the depth map for a given image file, utilizing disk caching when available.
    public func estimateDepth(forImageAt imageURL: URL, device: MTLDevice) async throws -> MetalTextureBox {
        let cacheKey = try computeCacheKey(for: imageURL)
        if let cachedTexture = try loadCachedDepthTexture(cacheKey: cacheKey, device: device) {
            logger.info("Loaded cached depth map for \(imageURL.lastPathComponent)")
            return MetalTextureBox(cachedTexture)
        }

        guard let nsImage = NSImage(contentsOf: imageURL),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw DepthEstimationError.invalidImageSource(imageURL.path)
        }

        return try await estimateDepth(from: cgImage, cacheKey: cacheKey, device: device)
    }

    /// Estimates depth from a CGImage and returns an MTLTexture containing 16-bit float depth values.
    public func estimateDepth(from cgImage: CGImage, cacheKey: String? = nil, device: MTLDevice) async throws -> MetalTextureBox {
        let model = try getOrLoadModel()

        // 1. Resize input image to 518x392 CVPixelBuffer
        let inputBuffer = try createScaledPixelBuffer(from: cgImage, width: Self.targetInputWidth, height: Self.targetInputHeight)

        // 2. Perform inference
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: inputBuffer)
        ])

        let prediction = try model.prediction(from: provider)

        guard let depthPixelBuffer = prediction.featureValue(for: "depth")?.imageBufferValue else {
            throw DepthEstimationError.missingOutputFeature("depth")
        }

        // 3. Convert CVPixelBuffer to Metal Texture
        let texture = try createMetalTexture(from: depthPixelBuffer, device: device)

        // 4. Save to disk cache if key provided
        if let key = cacheKey {
            saveDepthCache(pixelBuffer: depthPixelBuffer, cacheKey: key)
        }

        return MetalTextureBox(texture)
    }

    // MARK: - PixelBuffer & Texture Conversion

    private func createScaledPixelBuffer(from cgImage: CGImage, width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attrs,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw DepthEstimationError.pixelBufferAllocationFailed(Int(status))
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw DepthEstimationError.pixelBufferAllocationFailed(-1)
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            throw DepthEstimationError.pixelBufferAllocationFailed(-2)
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private func createMetalTexture(from depthBuffer: CVPixelBuffer, device: MTLDevice) throws -> MTLTexture {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else {
            throw DepthEstimationError.textureCreationFailed
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw DepthEstimationError.textureCreationFailed
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: baseAddress,
            bytesPerRow: bytesPerRow
        )

        return texture
    }

    // MARK: - Disk Caching

    private func cacheDirectory() -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/WallpaperEngine/depth")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func computeCacheKey(for imageURL: URL) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: imageURL.path)
        let modDate = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? Int64) ?? 0
        let keyString = "\(imageURL.path)_\(size)_\(modDate)"
        let digest = SHA256.hash(data: Data(keyString.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func loadCachedDepthTexture(cacheKey: String, device: MTLDevice) throws -> MTLTexture? {
        let fileURL = cacheDirectory().appendingPathComponent("\(cacheKey).bin")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let data = try Data(contentsOf: fileURL)
        let expectedBytes = Self.targetInputWidth * Self.targetInputHeight * 2 // 16-bit float = 2 bytes per pixel
        guard data.count == expectedBytes else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r16Float,
            width: Self.targetInputWidth,
            height: Self.targetInputHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        data.withUnsafeBytes { rawBuffer in
            if let ptr = rawBuffer.baseAddress {
                texture.replace(
                    region: MTLRegionMake2D(0, 0, Self.targetInputWidth, Self.targetInputHeight),
                    mipmapLevel: 0,
                    withBytes: ptr,
                    bytesPerRow: Self.targetInputWidth * 2
                )
            }
        }

        return texture
    }

    private func saveDepthCache(pixelBuffer: CVPixelBuffer, cacheKey: String) {
        let fileURL = cacheDirectory().appendingPathComponent("\(cacheKey).bin")

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let data = Data(bytes: base, count: bytesPerRow * height)

        try? data.write(to: fileURL, options: .atomic)
    }
}

public enum DepthEstimationError: Error, LocalizedError {
    case modelNotFound(String)
    case invalidImageSource(String)
    case pixelBufferAllocationFailed(Int)
    case missingOutputFeature(String)
    case textureCreationFailed

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "DepthAnythingV2 CoreML model could not be found at: \(path)"
        case .invalidImageSource(let path):
            return "Failed to load image source at: \(path)"
        case .pixelBufferAllocationFailed(let code):
            return "Failed to allocate CVPixelBuffer (code \(code))"
        case .missingOutputFeature(let name):
            return "Model did not produce expected output feature '\(name)'"
        case .textureCreationFailed:
            return "Failed to create Metal texture from depth buffer"
        }
    }
}

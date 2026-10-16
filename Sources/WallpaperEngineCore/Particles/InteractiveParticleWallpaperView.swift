//
//  InteractiveParticleWallpaperView.swift
//  WallpaperEngineCore
//
//  Feature 4.C & 4.D: Native interactive particle wallpaper engine.
//  Uses hardware-accelerated CAEmitterLayer for Rain, Snow, and Ambient Fireflies.
//  Zero CPU rasterization, zero per-frame allocations, and instant pause/resume.
//

import AppKit
import CoreGraphics
import Foundation
import QuartzCore

public enum ParticleSceneType: String, Codable, CaseIterable, Sendable {
    case rain = "Rain"
    case snow = "Snow"
    case ambientFireflies = "Ambient Fireflies"
}

@MainActor
public final class InteractiveParticleWallpaperView: NSView {
    public var sceneType: ParticleSceneType = .rain {
        didSet {
            resetParticles()
        }
    }

    public var isInteractive: Bool = true
    public var particleSpeed: Float = 1.0 {
        didSet {
            if !isPaused {
                emitterLayer.speed = max(0.1, particleSpeed)
            }
        }
    }
    public var particleDensity: Int = 100 {
        didSet {
            resetParticles()
        }
    }
    public var targetFrameRate: Int = 60

    public private(set) var isPaused: Bool = false
    private let emitterLayer = CAEmitterLayer()
    private var mouseLocation: CGPoint = .zero
    private var mouseMonitor: Any?

    // Reusable static particle textures generated once
    private static let rainTexture: CGImage = {
        let size = CGSize(width: 4, height: 18)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 0.8))
        ctx.fill(CGRect(x: 1, y: 0, width: 2, height: 18))
        return ctx.makeImage()!
    }()

    private static let snowTexture: CGImage = {
        let size = CGSize(width: 12, height: 12)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: 1, y: 1, width: 10, height: 10))
        return ctx.makeImage()!
    }()

    private static let fireflyTexture: CGImage = {
        let size = CGSize(width: 16, height: 16)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 0.4))
        ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: 16, height: 16))
        ctx.setFillColor(CGColor(red: 1.0, green: 0.95, blue: 0.6, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: 4, y: 4, width: 8, height: 8))
        return ctx.makeImage()!
    }()

    public init(frame frameRect: NSRect, sceneType: ParticleSceneType = .rain) {
        self.sceneType = sceneType
        super.init(frame: frameRect)
        setupLayer()
        resetParticles()
        setupMouseMonitoring()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
        resetParticles()
        setupMouseMonitoring()
    }

    deinit {
        // Cleanup handled in removeFromSuperview
    }

    private func setupLayer() {
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        autoresizingMask = [.width, .height]
        layer?.backgroundColor = NSColor.black.cgColor

        emitterLayer.frame = bounds
        emitterLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(emitterLayer)
    }

    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        emitterLayer.frame = bounds
        updateEmitterGeometry()
        CATransaction.commit()
    }

    private func updateEmitterGeometry() {
        let width = bounds.width > 0 ? bounds.width : 1920
        let height = bounds.height > 0 ? bounds.height : 1080

        switch sceneType {
        case .rain:
            emitterLayer.emitterShape = .line
            emitterLayer.emitterPosition = CGPoint(x: width * 0.5, y: height + 10)
            emitterLayer.emitterSize = CGSize(width: width * 1.2, height: 1)
        case .snow:
            emitterLayer.emitterShape = .line
            emitterLayer.emitterPosition = CGPoint(x: width * 0.5, y: height + 10)
            emitterLayer.emitterSize = CGSize(width: width * 1.2, height: 1)
        case .ambientFireflies:
            emitterLayer.emitterShape = .rectangle
            emitterLayer.emitterPosition = CGPoint(x: width * 0.5, y: height * 0.5)
            emitterLayer.emitterSize = CGSize(width: width, height: height)
        }
    }

    private func setupMouseMonitoring() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self = self, self.isInteractive, !self.isPaused else { return }
                if let window = self.window {
                    let pointInWindow = window.convertPoint(fromScreen: event.locationInWindow)
                    self.mouseLocation = self.convert(pointInWindow, from: nil)
                    self.applyInteractiveRepulsion()
                }
            }
        }
    }

    private func applyInteractiveRepulsion() {
        guard isInteractive, !isPaused else { return }
        if sceneType == .ambientFireflies {
            // Deflect emitter position toward cursor
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let width = bounds.width > 0 ? bounds.width : 1920
            let height = bounds.height > 0 ? bounds.height : 1080
            let targetX = (width * 0.5 + mouseLocation.x) * 0.5
            let targetY = (height * 0.5 + mouseLocation.y) * 0.5
            emitterLayer.emitterPosition = CGPoint(x: targetX, y: targetY)
            CATransaction.commit()
        }
    }

    public func resetParticles() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        updateEmitterGeometry()
        let count = max(20, min(500, particleDensity))
        let height = bounds.height > 0 ? bounds.height : 1080

        let cell = CAEmitterCell()
        cell.speed = 1.0

        switch sceneType {
        case .rain:
            cell.birthRate = Float(count) * 1.5
            cell.lifetime = Float(height / 400.0) + 1.0
            cell.velocity = CGFloat(600 * particleSpeed)
            cell.velocityRange = 150
            cell.emissionLongitude = .pi // Falling downwards
            cell.emissionRange = 0.05
            cell.contents = Self.rainTexture
            cell.color = CGColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 0.7)
            cell.scale = 1.0
            cell.scaleRange = 0.3

        case .snow:
            cell.birthRate = Float(count) * 0.6
            cell.lifetime = Float(height / 45.0) + 2.0
            cell.velocity = CGFloat(65 * particleSpeed)
            cell.velocityRange = 30
            cell.emissionLongitude = .pi
            cell.emissionRange = 0.3
            cell.spin = 0.5
            cell.spinRange = 1.0
            cell.contents = Self.snowTexture
            cell.color = CGColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 0.85)
            cell.scale = 0.6
            cell.scaleRange = 0.4

        case .ambientFireflies:
            cell.birthRate = Float(count) * 0.15
            cell.lifetime = 6.0
            cell.lifetimeRange = 3.0
            cell.velocity = CGFloat(18 * particleSpeed)
            cell.velocityRange = 12
            cell.emissionRange = .pi * 2
            cell.contents = Self.fireflyTexture
            cell.color = CGColor(red: 1.0, green: 0.9, blue: 0.4, alpha: 0.75)
            cell.scale = 0.7
            cell.scaleRange = 0.3
            cell.alphaSpeed = -0.06
        }

        emitterLayer.emitterCells = [cell]
        emitterLayer.speed = isPaused ? 0.0 : max(0.1, particleSpeed)
        CATransaction.commit()
    }

    public func startRenderLoop() {
        guard !isPaused else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        emitterLayer.birthRate = 1.0
        emitterLayer.speed = max(0.1, particleSpeed)
        CATransaction.commit()
    }

    public func stopRenderLoop() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        emitterLayer.birthRate = 0.0
        CATransaction.commit()
    }

    public func pause() {
        guard !isPaused else { return }
        isPaused = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        emitterLayer.speed = 0.0
        emitterLayer.birthRate = 0.0
        CATransaction.commit()
    }

    public func resume() {
        guard isPaused else { return }
        isPaused = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        emitterLayer.speed = max(0.1, particleSpeed)
        emitterLayer.birthRate = 1.0
        CATransaction.commit()
    }

    public func setTargetFrameRate(_ fps: Int) {
        self.targetFrameRate = max(1, fps)
        if !isPaused {
            let normalizedSpeed = Float(min(60, targetFrameRate)) / 60.0 * particleSpeed
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            emitterLayer.speed = max(0.1, normalizedSpeed)
            CATransaction.commit()
        }
    }

    public override func removeFromSuperview() {
        stopRenderLoop()
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        super.removeFromSuperview()
    }
}

//
//  ShaderUniforms.swift
//  WallpaperEngineCore
//
//  Uniform buffer layout conforming to 16-byte Metal SIMD alignment
//  for real-time procedural and imported Shadertoy shaders.
//

import Foundation
import simd

/// Memory layout conforming strictly to 16-byte Metal SIMD alignment.
/// Total size: 80 bytes (5 x 16-byte vectors).
public struct ShaderUniforms: Sendable, Equatable {
    public var resolution: SIMD2<Float>      // offset 0, size 8
    public var time: Float                   // offset 8, size 4
    public var timeDelta: Float              // offset 12, size 4
    public var mouse: SIMD4<Float>           // offset 16, size 16 (x, y, clickX, clickY)
    public var date: SIMD4<Float>            // offset 32, size 16 (year, month, day, seconds)
    public var customParams: SIMD4<Float>    // offset 48, size 16 (speed, p1, p2, p3)
    public var frameIndex: UInt32            // offset 64, size 4
    public var speed: Float                  // offset 68, size 4
    public var pad1: Float                   // offset 72, size 4
    public var pad2: Float                   // offset 76, size 4

    public init(
        resolution: SIMD2<Float> = SIMD2<Float>(1920, 1080),
        time: Float = 0.0,
        timeDelta: Float = 1.0 / 60.0,
        mouse: SIMD4<Float> = .zero,
        date: SIMD4<Float> = .zero,
        customParams: SIMD4<Float> = SIMD4<Float>(1.0, 0.0, 0.0, 0.0),
        frameIndex: UInt32 = 0,
        speed: Float = 1.0,
        pad1: Float = 0.0,
        pad2: Float = 0.0
    ) {
        self.resolution = resolution
        self.time = time
        self.timeDelta = timeDelta
        self.mouse = mouse
        self.date = date
        self.customParams = customParams
        self.frameIndex = frameIndex
        self.speed = speed
        self.pad1 = pad1
        self.pad2 = pad2
    }
}

//
//  ShaderTests.swift
//  WallpaperEngineCoreTests
//
//  Unit and integration test suite for Real-Time Metal Procedural Shaders:
//  - ShaderUniforms memory alignment and layout
//  - Shadertoy compatibility wrapper and syntax auto-detection
//  - ProceduralShaderPreset compilation and lookup
//  - MetalShaderRenderer runtime compilation and hot-swapping
//  - CommandLineOptions shader flags
//  - EngineConfig shader serialization and backward compatibility
//

import CoreGraphics
import Foundation
import Metal
@testable import WallpaperEngineCore

@MainActor
public struct ShaderTests {
    public static func runAllTests() async {
        let runner = TestRunner.shared

        await runner.runSuite("Suite: Real-Time Metal Procedural Shaders") {

            // Test 1: ShaderUniforms Memory Layout and Alignment
            runner.test("ShaderUniforms is 80 bytes and 16-byte aligned for Metal constant buffer") {
                let size = MemoryLayout<ShaderUniforms>.size
                let stride = MemoryLayout<ShaderUniforms>.stride
                let alignment = MemoryLayout<ShaderUniforms>.alignment

                try assertEqual(size, 80, "ShaderUniforms struct size must be exactly 80 bytes")
                try assertEqual(stride, 80, "ShaderUniforms struct stride must be exactly 80 bytes")
                try assertEqual(alignment, 16, "ShaderUniforms struct alignment must be 16 bytes")

                var uniforms = ShaderUniforms()
                uniforms.resolution = SIMD2<Float>(1920, 1080)
                uniforms.time = 42.5
                uniforms.timeDelta = 0.016
                uniforms.mouse = SIMD4<Float>(100, 200, 1, 0)
                uniforms.date = SIMD4<Float>(2026, 10, 15, 1200)
                uniforms.customParams = SIMD4<Float>(1, 2, 3, 4)
                uniforms.frameIndex = 120
                uniforms.speed = 1.5

                try assertEqual(uniforms.resolution.x, 1920, "Resolution X stored")
                try assertEqual(uniforms.time, 42.5, "Time stored")
                try assertEqual(uniforms.speed, 1.5, "Speed stored")
                try assertEqual(uniforms.frameIndex, 120, "Frame index stored")
            }

            // Test 2: Shadertoy Wrapper Transformation
            runner.test("ShadertoyCompatibility wraps standard mainImage into valid Metal shader") {
                let glsl = """
                void mainImage(out vec4 fragColor, in vec2 fragCoord) {
                    vec2 uv = fragCoord / iResolution.xy;
                    fragColor = vec4(uv.x, uv.y, 0.5 + 0.5 * sin(iTime), 1.0);
                }
                """
                let msl = ShadertoyCompatibility.wrapShadertoy(glsl)

                try assertTrue(msl.contains("#include <metal_stdlib>"), "Contains metal standard library")
                try assertTrue(msl.contains("struct ShaderUniforms"), "Contains ShaderUniforms definition")
                try assertTrue(msl.contains("vertex VertexOut proceduralVertexShader"), "Contains vertex shader")
                try assertTrue(msl.contains("fragment float4 proceduralFragmentShader"), "Contains fragment entrypoint")
                try assertTrue(msl.contains("mainImage(fragColor, fragCoord)"), "Calls user mainImage")
            }

            // Test 3: Shader Syntax Auto-Detection
            runner.test("ShadertoyCompatibility prepareSource correctly identifies Shadertoy vs MSL") {
                let shadertoyCode = "void mainImage(out vec4 fragColor, in vec2 fragCoord) { fragColor = vec4(1.0); }"
                let nativeMSL = """
                #include <metal_stdlib>
                using namespace metal;
                vertex float4 myVert() { return float4(0); }
                fragment float4 myFrag() { return float4(1); }
                """
                let fragmentOnlyMSL = """
                fragment float4 customFrag(VertexOut in [[stage_in]]) {
                    return float4(1.0, 0.0, 0.0, 1.0);
                }
                """

                let preparedShadertoy = ShadertoyCompatibility.prepareSource(shadertoyCode)
                try assertTrue(preparedShadertoy.contains("proceduralFragmentShader"), "Wrapped Shadertoy fragment")

                let preparedNative = ShadertoyCompatibility.prepareSource(nativeMSL)
                try assertEqual(preparedNative, nativeMSL, "Native MSL left untouched")

                let preparedFragOnly = ShadertoyCompatibility.prepareSource(fragmentOnlyMSL)
                try assertTrue(preparedFragOnly.contains("proceduralVertexShader"), "Wrapped MSL with vertex shader")
            }

            // Test 4: Procedural Preset Lookup and Aliases
            runner.test("ProceduralShaderPreset resolves all presets and fuzzy aliases") {
                try assertEqual(ProceduralShaderPreset.allCases.count, 5, "Exactly 5 built-in presets")

                try assertEqual(ProceduralShaderPreset(nameOrKey: "aurora"), .aurora, "aurora matched")
                try assertEqual(ProceduralShaderPreset(nameOrKey: "Aurora Borealis"), .aurora, "Aurora Borealis display name matched")
                try assertEqual(ProceduralShaderPreset(nameOrKey: "starfield"), .starfield, "starfield matched")
                try assertEqual(ProceduralShaderPreset(nameOrKey: "warp"), .starfield, "warp keyword matched")
                try assertEqual(ProceduralShaderPreset(nameOrKey: "gradientFlow"), .gradientFlow, "gradientFlow matched")
                try assertEqual(ProceduralShaderPreset(nameOrKey: "flow"), .gradientFlow, "flow keyword matched")
                try assertEqual(ProceduralShaderPreset(nameOrKey: "cyberpunkGrid"), .cyberpunkGrid, "cyberpunkGrid matched")
                try assertEqual(ProceduralShaderPreset(nameOrKey: "synthwave"), .cyberpunkGrid, "synth keyword matched")
                try assertEqual(ProceduralShaderPreset(nameOrKey: "bokeh"), .bokeh, "bokeh matched")
                try assertTrue(ProceduralShaderPreset(nameOrKey: "nonexistent") == nil, "nonexistent returns nil")
            }

            // Test 5: Metal Compilation of All 5 Built-in Presets
            runner.test("All 5 built-in procedural presets compile to Metal pipeline without error") {
                guard let device = MTLCreateSystemDefaultDevice() else {
                    print("Skipping Metal compilation test: No Metal device available on this host.")
                    return
                }

                for preset in ProceduralShaderPreset.allCases {
                    let source = preset.metalSource
                    do {
                        let library = try device.makeLibrary(source: source, options: nil)
                        let vert = library.makeFunction(name: "proceduralVertexShader")
                        let frag = library.makeFunction(name: "proceduralFragmentShader")
                        try assertTrue(vert != nil, "\(preset.displayName) has vertex function")
                        try assertTrue(frag != nil, "\(preset.displayName) has fragment function")
                    } catch {
                        throw TestFailure("Preset '\(preset.displayName)' failed Metal compilation: \(error.localizedDescription)")
                    }
                }
            }

            // Test 6: MetalShaderRenderer Lifecycle, Hot-Swapping and Error Handling
            runner.test("MetalShaderRenderer compiles presets, Shadertoy source and surfaces invalid syntax errors") {
                guard let renderer = MetalShaderRenderer() else {
                    print("Skipping MetalShaderRenderer test: No Metal device.")
                    return
                }

                // 1. Load preset
                try renderer.loadPreset(.aurora)

                // 2. Load custom Shadertoy snippet
                let customShadertoy = """
                void mainImage(out vec4 fragColor, in vec2 fragCoord) {
                    vec2 p = fragCoord / iResolution.xy;
                    fragColor = vec4(p.x, p.y, sin(iTime), 1.0);
                }
                """
                try renderer.loadShader(source: customShadertoy)

                // 3. Set speed multiplier
                renderer.setSpeed(2.0)
                try assertEqual(renderer.speed, 2.0, "Speed updated to 2.0")

                // 4. Intentionally broken shader syntax
                let brokenCode = "this is completely invalid MSL code that cannot compile"
                var errorDidThrow = false
                do {
                    try renderer.loadShader(source: brokenCode)
                } catch {
                    errorDidThrow = true
                }
                try assertTrue(errorDidThrow, "Invalid shader source threw compilation error")
            }

            // Test 7: CommandLineOptions Shader Flags Parsing
            runner.test("CLI flags parse --shader and --shader-speed accurately") {
                let args1 = [
                    "wallpaper_app",
                    "--shader", "cyberpunkGrid",
                    "--shader-speed", "1.75"
                ]
                let opts1 = CommandLineOptions.parse(arguments: args1)
                try assertEqual(opts1.shaderName, "cyberpunkGrid", "shaderName parsed")
                try assertEqual(opts1.shaderSpeed, 1.75, "shaderSpeed parsed")

                var config = EngineConfig.default
                opts1.apply(to: &config)
                try assertEqual(config.shaderName, "cyberpunkGrid", "config shaderName updated")
                try assertEqual(config.shaderSpeed, 1.75, "config shaderSpeed updated")

                // Inline syntax and path syntax
                let args2 = [
                    "wallpaper_app",
                    "--shader=/Users/test/shader.metal",
                    "--shader-speed=0.5"
                ]
                let opts2 = CommandLineOptions.parse(arguments: args2)
                try assertEqual(opts2.shaderPath, "/Users/test/shader.metal", "shaderPath parsed")
                try assertEqual(opts2.shaderSpeed, 0.5, "shaderSpeed parsed")
            }

            // Test 8: EngineConfig Serialization and Backward Compatibility
            runner.test("EngineConfig preserves shader properties and maintains backwards compatibility") {
                var config = EngineConfig.default
                config.shaderName = "starfield"
                config.shaderPath = "/path/to/my_shader.frag"
                config.shaderSpeed = 1.25

                let encoder = JSONEncoder()
                let data = try encoder.encode(config)

                let decoder = JSONDecoder()
                let decoded = try decoder.decode(EngineConfig.self, from: data)

                try assertEqual(decoded.shaderName, "starfield", "Decoded shaderName matches")
                try assertEqual(decoded.shaderPath, "/path/to/my_shader.frag", "Decoded shaderPath matches")
                try assertEqual(decoded.shaderSpeed, 1.25, "Decoded shaderSpeed matches")

                // Legacy config JSON without any shader fields
                let legacyJSON = """
                {
                    "isPaused": false,
                    "targetFrameRate": 60,
                    "throttledFrameRate": 30,
                    "pauseOnBattery": false,
                    "pauseOnLowPowerMode": true,
                    "pauseOnDisplaySleep": true,
                    "pauseOnScreenLock": true,
                    "pauseWhenOccluded": true
                }
                """
                let legacyDecoded = try decoder.decode(EngineConfig.self, from: legacyJSON.data(using: .utf8)!)
                try assertTrue(legacyDecoded.shaderName == nil, "Legacy config has nil shaderName")
                try assertTrue(legacyDecoded.shaderPath == nil, "Legacy config has nil shaderPath")
                try assertEqual(legacyDecoded.shaderSpeed, 1.0, "Legacy config has default 1.0 shaderSpeed")
            }
        }
    }
}

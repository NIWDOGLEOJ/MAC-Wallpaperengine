//
//  ShadertoyCompatibility.swift
//  WallpaperEngineCore
//
//  Provides a Metal Shading Language (MSL) compatibility layer for importing
//  standard Shadertoy GLSL shaders and custom Metal shaders with zero dependencies.
//

import Foundation

public enum ShaderType: Sendable {
    case nativeMetal
    case shadertoy
}

public struct ShadertoyCompatibility: Sendable {

    /// Standard full-screen vertex shader (using single triangle technique) and uniform definitions.
    public static let standardHeader = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    struct ShaderUniforms {
        simd_float2 resolution;
        float time;
        float timeDelta;
        simd_float4 mouse;
        simd_float4 date;
        simd_float4 customParams;
        uint32_t frameIndex;
        float speed;
        float pad1;
        float pad2;
    };

    vertex VertexOut proceduralVertexShader(uint vertexID [[vertex_id]]) {
        float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        float2 uvs[3] = {
            float2(0.0, 0.0),
            float2(2.0, 0.0),
            float2(0.0, 2.0)
        };

        VertexOut out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = uvs[vertexID];
        return out;
    }
    """

    /// GLSL to MSL compatibility bridge for standard Shadertoy types and math functions.
    public static let shadertoyBridge = """
    // GLSL Type Aliases
    typedef float2 vec2;
    typedef float3 vec3;
    typedef float4 vec4;
    typedef int2 ivec2;
    typedef int3 ivec3;
    typedef int4 ivec4;
    typedef bool2 bvec2;
    typedef bool3 bvec3;
    typedef bool4 bvec4;
    typedef float2x2 mat2;
    typedef float3x3 mat3;
    typedef float4x4 mat4;

    // GLSL Math Functions & Overloads
    static inline float mod(float x, float y) { return fmod(x, y); }
    static inline float2 mod(float2 x, float2 y) { return fmod(x, y); }
    static inline float3 mod(float3 x, float3 y) { return fmod(x, y); }
    static inline float4 mod(float4 x, float4 y) { return fmod(x, y); }
    static inline float2 mod(float2 x, float y) { return fmod(x, float2(y)); }
    static inline float3 mod(float3 x, float y) { return fmod(x, float3(y)); }
    static inline float4 mod(float4 x, float y) { return fmod(x, float4(y)); }

    static inline float atan(float y, float x) { return atan2(y, x); }
    static inline float2 atan(float2 y, float2 x) { return atan2(y, x); }
    static inline float3 atan(float3 y, float3 x) { return atan2(y, x); }
    static inline float4 atan(float4 y, float4 x) { return atan2(y, x); }

    #define dFdx(x) dfdx(x)
    #define dFdy(x) dfdy(x)
    """

    /// Determines the input shader type.
    public static func detectType(source: String) -> ShaderType {
        if source.contains("mainImage(") || source.contains("mainImage (") {
            return .shadertoy
        }
        return .nativeMetal
    }

    /// Prepares complete, compilable Metal Shading Language source code.
    public static func prepareSource(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = detectType(source: trimmed)

        switch type {
        case .shadertoy:
            return wrapShadertoy(trimmed)
        case .nativeMetal:
            return wrapNativeMetal(trimmed)
        }
    }

    /// Wraps a Shadertoy GLSL fragment snippet inside the Metal pipeline harness.
    public static func wrapShadertoy(_ glslCode: String) -> String {
        // Clean common GLSL directives that MSL rejects
        var sanitized = glslCode
            .replacingOccurrences(of: "#version", with: "//#version")
            .replacingOccurrences(of: "precision highp float;", with: "//precision")
            .replacingOccurrences(of: "precision mediump float;", with: "//precision")
            .replacingOccurrences(of: "precision lowp float;", with: "//precision")

        // Map GLSL function parameter qualifiers to Metal Shading Language:
        // 1. inout <type> <param> -> thread <type> &<param>
        sanitized = sanitized.replacingOccurrences(
            of: "\\binout\\s+([a-zA-Z0-9_]+)\\s+([a-zA-Z0-9_]+)",
            with: "thread $1 &$2",
            options: .regularExpression
        )
        // 2. out <type> <param> -> thread <type> &<param>
        sanitized = sanitized.replacingOccurrences(
            of: "\\bout\\s+([a-zA-Z0-9_]+)\\s+([a-zA-Z0-9_]+)",
            with: "thread $1 &$2",
            options: .regularExpression
        )
        // 3. in <type> <param> -> <type> <param>
        sanitized = sanitized.replacingOccurrences(
            of: "\\bin\\s+([a-zA-Z0-9_]+)\\b",
            with: "$1",
            options: .regularExpression
        )

        return """
        \(standardHeader)

        \(shadertoyBridge)

        struct ShadertoySandbox {
            constant ShaderUniforms &uniforms;
            vec3 iResolution;
            float iTime;
            float iTimeDelta;
            int iFrame;
            vec4 iMouse;
            vec4 iDate;

            ShadertoySandbox(constant ShaderUniforms &u) :
                uniforms(u),
                iResolution(vec3(u.resolution.x, u.resolution.y, u.resolution.x / u.resolution.y)),
                iTime(u.time * u.speed),
                iTimeDelta(u.timeDelta),
                iFrame(int(u.frameIndex)),
                iMouse(u.mouse),
                iDate(u.date) {}

            // --- User Shadertoy Source ---
            \(sanitized)
            // -----------------------------
        };

        fragment float4 proceduralFragmentShader(
            VertexOut in [[stage_in]],
            constant ShaderUniforms &uniforms [[buffer(0)]]
        ) {
            ShadertoySandbox sandbox(uniforms);

            // Flip Y coordinate so (0,0) matches Shadertoy's bottom-left origin
            vec2 fragCoord = vec2(in.position.x, uniforms.resolution.y - in.position.y);
            vec4 fragColor = vec4(0.0, 0.0, 0.0, 1.0);

            sandbox.mainImage(fragColor, fragCoord);
            return fragColor;
        }
        """
    }

    /// Wraps custom Metal source code, supplying standard vertex shader and uniforms if needed.
    public static func wrapNativeMetal(_ metalCode: String) -> String {
        var result = metalCode

        let hasVertex = result.contains("proceduralVertexShader") || result.contains("vertex ") || result.contains("[[vertex]]")
        let hasFragment = result.contains("proceduralFragmentShader") || result.contains("fragment ") || result.contains("[[fragment]]")

        if hasVertex && hasFragment {
            if !result.contains("<metal_stdlib>") {
                return "#include <metal_stdlib>\nusing namespace metal;\n" + result
            }
            return result
        }

        // Ensure metal_stdlib is included
        if !result.contains("<metal_stdlib>") {
            result = "#include <metal_stdlib>\nusing namespace metal;\n" + result
        }

        // Add standard vertex shader if not already supplied
        if !hasVertex {
            result = standardHeader + "\n" + result
        }

        // Add standard fragment wrapper if user provided a custom body without signature
        if !hasFragment {
            result += """

            fragment float4 proceduralFragmentShader(
                VertexOut in [[stage_in]],
                constant ShaderUniforms &uniforms [[buffer(0)]]
            ) {
                return float4(in.uv.x, in.uv.y, 0.5 + 0.5 * sin(uniforms.time), 1.0);
            }
            """
        }

        return result
    }
}

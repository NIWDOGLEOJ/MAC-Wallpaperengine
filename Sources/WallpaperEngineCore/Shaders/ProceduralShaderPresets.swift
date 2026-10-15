//
//  ProceduralShaderPresets.swift
//  WallpaperEngineCore
//
//  High-performance, GPU-accelerated procedural Metal shaders:
//  1. Aurora (Atmospheric Northern Lights)
//  2. Starfield (3D Hyper-Warp Space)
//  3. Gradient Flow (Organic Liquid Mesh)
//  4. Cyberpunk Grid (80s Synthwave Horizon)
//  5. Bokeh (Cinematic Luminous Orbs)
//

import Foundation

public enum ProceduralShaderPreset: String, CaseIterable, Identifiable, Sendable {
    case aurora = "aurora"
    case starfield = "starfield"
    case gradientFlow = "gradientFlow"
    case cyberpunkGrid = "cyberpunkGrid"
    case bokeh = "bokeh"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .aurora: return "Aurora Borealis"
        case .starfield: return "3D Warp Starfield"
        case .gradientFlow: return "Gradient Flow"
        case .cyberpunkGrid: return "Cyberpunk Grid"
        case .bokeh: return "Cinematic Bokeh"
        }
    }

    public var metalSource: String {
        switch self {
        case .aurora:
            return Self.auroraShader
        case .starfield:
            return Self.starfieldShader
        case .gradientFlow:
            return Self.gradientFlowShader
        case .cyberpunkGrid:
            return Self.cyberpunkGridShader
        case .bokeh:
            return Self.bokehShader
        }
    }

    public init?(nameOrKey: String) {
        let lower = nameOrKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let direct = Self(rawValue: lower) {
            self = direct
            return
        }
        for preset in Self.allCases {
            if preset.rawValue.lowercased() == lower || preset.displayName.lowercased() == lower {
                self = preset
                return
            }
        }
        if lower.contains("aurora") { self = .aurora }
        else if lower.contains("star") || lower.contains("warp") || lower.contains("space") { self = .starfield }
        else if lower.contains("gradient") || lower.contains("flow") { self = .gradientFlow }
        else if lower.contains("grid") || lower.contains("cyber") || lower.contains("synth") { self = .cyberpunkGrid }
        else if lower.contains("bokeh") || lower.contains("orb") { self = .bokeh }
        else { return nil }
    }

    // MARK: - 1. Aurora Borealis Shader
    public static let auroraShader = """
    \(ShadertoyCompatibility.standardHeader)

    // Hash function for pseudo-random numbers
    static float hash(float2 p) {
        p = fract(p * float2(234.34, 435.345));
        p += dot(p, p + 34.23);
        return fract(p.x * p.y);
    }

    // Smooth value noise
    static float vnoise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);

        return mix(mix(hash(i + float2(0.0, 0.0)),
                       hash(i + float2(1.0, 0.0)), u.x),
                   mix(hash(i + float2(0.0, 1.0)),
                       hash(i + float2(1.0, 1.0)), u.x), u.y);
    }

    fragment float4 proceduralFragmentShader(
        VertexOut in [[stage_in]],
        constant ShaderUniforms &uniforms [[buffer(0)]]
    ) {
        float2 uv = in.uv;
        float aspect = uniforms.resolution.x / uniforms.resolution.y;
        float2 p = uv * 2.0 - 1.0;
        p.x *= aspect;

        float t = uniforms.time * uniforms.speed * 0.4;

        // Background Starfield
        float3 col = float3(0.01, 0.015, 0.035);
        float starSeed = hash(floor(in.position.xy * 0.4));
        if (starSeed > 0.996) {
            float twinkle = 0.5 + 0.5 * sin(t * 3.0 + starSeed * 100.0);
            col += float3(0.8, 0.9, 1.0) * twinkle * (starSeed - 0.996) * 200.0;
        }

        // Aurora Curtains Layering
        float auroraIntensity = 0.0;
        float3 auroraCol = float3(0.0);

        for (int i = 0; i < 4; i++) {
            float fi = float(i);
            float speedMult = 1.0 + fi * 0.25;
            float layerTime = t * speedMult;

            // Wave deformation
            float wave = sin(p.x * (1.2 + fi * 0.4) + layerTime + fi * 1.5) * 0.25;
            wave += cos(p.x * (2.4 + fi * 0.6) - layerTime * 0.7) * 0.15;
            wave += vnoise(float2(p.x * 2.0 + layerTime * 0.3, fi * 3.0)) * 0.2;

            float yOffset = -0.1 + fi * 0.18;
            float dist = abs(p.y - wave - yOffset);

            // Vertical flare streak
            float streak = vnoise(float2(p.x * 12.0 + layerTime * 0.5, fi));
            float flare = smoothstep(0.45, 0.0, dist) * (0.6 + 0.4 * streak);

            // Aurora color gradient: emerald base -> cyan mid -> violet crest
            float3 cEmerald = float3(0.05, 0.95, 0.55);
            float3 cCyan    = float3(0.02, 0.85, 0.95);
            float3 cViolet  = float3(0.65, 0.15, 0.95);

            float3 layerColor = mix(cEmerald, cCyan, smoothstep(-0.3, 0.3, p.y));
            layerColor = mix(layerColor, cViolet, smoothstep(0.2, 0.7, p.y));

            auroraCol += layerColor * flare * (1.2 - fi * 0.2);
        }

        // Atmosphere and horizon ground fade
        col += auroraCol;
        col += float3(0.0, 0.05, 0.08) * smoothstep(0.8, -0.8, p.y);

        // Vignette
        float vig = 1.0 - length(uv - 0.5) * 0.4;
        col *= clamp(vig, 0.0, 1.0);

        return float4(col, 1.0);
    }
    """

    // MARK: - 2. 3D Warp Starfield Shader
    public static let starfieldShader = """
    \(ShadertoyCompatibility.standardHeader)

    static float2x2 rot(float a) {
        float c = cos(a), s = sin(a);
        return float2x2(c, -s, s, c);
    }

    static float hash12(float2 p) {
        float3 p3 = fract(float3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }

    fragment float4 proceduralFragmentShader(
        VertexOut in [[stage_in]],
        constant ShaderUniforms &uniforms [[buffer(0)]]
    ) {
        float2 uv = (in.position.xy - 0.5 * uniforms.resolution) / min(uniforms.resolution.x, uniforms.resolution.y);
        float t = uniforms.time * uniforms.speed * 0.6;

        // Mouse tilt
        float2 mouseOffset = (uniforms.mouse.xy / uniforms.resolution - 0.5) * 0.8;
        uv += mouseOffset;
        uv = rot(t * 0.05) * uv;

        float3 col = float3(0.005, 0.008, 0.02);

        // Background Nebula Dust
        float nebula = sin(uv.x * 2.0 + t * 0.1) * cos(uv.y * 2.0 - t * 0.08);
        col += float3(0.08, 0.02, 0.15) * smoothstep(-0.5, 1.0, nebula);
        col += float3(0.01, 0.08, 0.12) * smoothstep(0.2, 1.2, -nebula);

        // 3D Warp Starfield Slices
        for (float i = 0.0; i < 1.0; i += 1.0 / 32.0) {
            float depth = fract(i + t * 0.3);
            float scale = mix(20.0, 0.5, depth);
            float fade = depth * smoothstep(1.0, 0.8, depth);

            float2 starGrid = floor(uv * scale + i * 45.67);
            float starRand = hash12(starGrid);

            if (starRand > 0.85) {
                float2 starCenter = (starGrid + 0.5) / scale;
                float dist = length(uv - starCenter);
                float radius = (starRand - 0.85) * 0.025 / (scale * 0.15);

                float brightness = smoothstep(radius, 0.0, dist);

                // Star spectral temperature
                float3 starCol = mix(float3(1.0, 0.85, 0.7), float3(0.7, 0.85, 1.0), starRand);
                col += starCol * brightness * fade * 2.5;
            }
        }

        return float4(col, 1.0);
    }
    """

    // MARK: - 3. Gradient Flow Shader
    public static let gradientFlowShader = """
    \(ShadertoyCompatibility.standardHeader)

    static float2 hash2(float2 p) {
        p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
        return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
    }

    static float perlinNoise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);

        return mix(mix(dot(hash2(i + float2(0.0, 0.0)), f - float2(0.0, 0.0)),
                       dot(hash2(i + float2(1.0, 0.0)), f - float2(1.0, 0.0)), u.x),
                   mix(dot(hash2(i + float2(0.0, 1.0)), f - float2(0.0, 1.0)),
                       dot(hash2(i + float2(1.0, 1.0)), f - float2(1.0, 1.0)), u.x), u.y);
    }

    static float fbmFlow(float2 p) {
        float f = 0.0;
        f += 0.5000 * perlinNoise(p); p = p * 2.02;
        f += 0.2500 * perlinNoise(p); p = p * 2.03;
        f += 0.1250 * perlinNoise(p); p = p * 2.01;
        f += 0.0625 * perlinNoise(p);
        return f;
    }

    fragment float4 proceduralFragmentShader(
        VertexOut in [[stage_in]],
        constant ShaderUniforms &uniforms [[buffer(0)]]
    ) {
        float2 uv = in.uv;
        float aspect = uniforms.resolution.x / uniforms.resolution.y;
        float2 p = uv * 3.0;
        p.x *= aspect;

        float t = uniforms.time * uniforms.speed * 0.25;

        // Domain warping for organic liquid motion
        float2 q = float2(fbmFlow(p + float2(0.0, 0.0) + t * 0.3),
                          fbmFlow(p + float2(5.2, 1.3) - t * 0.2));

        float2 r = float2(fbmFlow(p + 4.0 * q + float2(1.7, 9.2) + t * 0.15),
                          fbmFlow(p + 4.0 * q + float2(8.3, 2.8) - t * 0.12));

        float f = fbmFlow(p + 4.0 * r);

        // Rich chromatic palette
        float3 c1 = float3(0.08, 0.12, 0.35); // Deep Sapphire
        float3 c2 = float3(0.85, 0.25, 0.55); // Sunset Magenta
        float3 c3 = float3(0.15, 0.85, 0.75); // Electric Turquoise
        float3 c4 = float3(0.98, 0.72, 0.32); // Radiant Amber

        float3 col = mix(c1, c2, clamp(f * f * 4.0, 0.0, 1.0));
        col = mix(col, c3, clamp(length(q), 0.0, 1.0));
        col = mix(col, c4, clamp(length(r), 0.0, 1.0) * 0.6);

        // Soft specular highlights
        col += float3(1.0, 1.0, 1.0) * smoothstep(0.7, 0.95, f) * 0.35;

        return float4(col, 1.0);
    }
    """

    // MARK: - 4. Cyberpunk Grid Shader
    public static let cyberpunkGridShader = """
    \(ShadertoyCompatibility.standardHeader)

    fragment float4 proceduralFragmentShader(
        VertexOut in [[stage_in]],
        constant ShaderUniforms &uniforms [[buffer(0)]]
    ) {
        float2 uv = in.uv;
        float aspect = uniforms.resolution.x / uniforms.resolution.y;
        float2 p = uv * 2.0 - 1.0;
        p.x *= aspect;

        float t = uniforms.time * uniforms.speed * 1.2;

        float3 col = float3(0.0);

        // Horizon position
        float horizon = -0.1;

        if (p.y > horizon) {
            // Sky & Synthwave Sun
            float skyY = (p.y - horizon) / (1.0 - horizon);
            col = mix(float3(0.12, 0.02, 0.25), float3(0.01, 0.005, 0.05), skyY);

            // Retro Sun
            float2 sunPos = float2(0.0, 0.3);
            float sunDist = length(p - sunPos);
            if (sunDist < 0.45) {
                // Horizontal laser slats
                float slat = sin((p.y - sunPos.y) * 45.0);
                if (p.y > sunPos.y || slat > -0.2) {
                    float3 sunCol = mix(float3(1.0, 0.2, 0.6), float3(1.0, 0.85, 0.1), (p.y - sunPos.y + 0.45) / 0.9);
                    col = mix(col, sunCol, smoothstep(0.45, 0.43, sunDist));
                }
            }

            // Distant Mountains Silhouette
            float mtn = sin(p.x * 3.5) * 0.08 + sin(p.x * 9.0) * 0.04;
            if (p.y < horizon + 0.15 + mtn) {
                col = mix(float3(0.04, 0.01, 0.08), col, smoothstep(horizon, horizon + 0.15 + mtn, p.y));
            }

            // Horizon Glow
            float glow = exp(-abs(p.y - horizon) * 6.0);
            col += float3(0.9, 0.1, 0.6) * glow * 0.7;

        } else {
            // Infinite 3D Perspective Grid
            float depth = 1.0 / (horizon - p.y);
            float2 gridPos = float2(p.x * depth * 0.8, depth + t * 2.5);

            float2 grid = abs(fract(gridPos - 0.5) - 0.5) / fwidth(gridPos);
            float line = min(grid.x, grid.y);
            float gridPattern = 1.0 - min(line, 1.0);

            // Neon Grid Color
            float3 gridCol = float3(0.0, 0.9, 1.0); // Cyan
            float fog = exp(-depth * 0.05);

            col = gridCol * gridPattern * fog * 1.5;
            col += float3(0.4, 0.0, 0.8) * fog * 0.3; // Ambient floor purple
        }

        // Retro CRT scanline effect
        float scanline = sin(in.position.y * 1.5) * 0.05;
        col -= scanline;

        return float4(col, 1.0);
    }
    """

    // MARK: - 5. Cinematic Bokeh Shader
    public static let bokehShader = """
    \(ShadertoyCompatibility.standardHeader)

    static float hashB(float2 p) {
        return fract(sin(dot(p, float2(41.12, 289.43))) * 45758.5453);
    }

    fragment float4 proceduralFragmentShader(
        VertexOut in [[stage_in]],
        constant ShaderUniforms &uniforms [[buffer(0)]]
    ) {
        float2 uv = in.uv;
        float aspect = uniforms.resolution.x / uniforms.resolution.y;
        float2 p = uv;
        p.x *= aspect;

        float t = uniforms.time * uniforms.speed * 0.5;

        // Dark rich background gradient
        float3 col = mix(float3(0.02, 0.015, 0.035), float3(0.06, 0.03, 0.08), uv.y);

        // Bokeh Orbs across 3 depth tiers
        for (float layer = 1.0; layer <= 3.0; layer += 1.0) {
            float count = 18.0 * layer;
            for (float i = 0.0; i < 24.0; i += 1.0) {
                float id = i + layer * 100.0;
                float seedX = hashB(float2(id, 1.23));
                float seedY = hashB(float2(id, 4.56));
                float seedR = hashB(float2(id, 7.89));

                // Floating motion
                float speedY = 0.08 + 0.05 * seedR;
                float speedX = sin(t * 0.5 + id) * 0.04;
                float2 pos = float2(
                    fract(seedX * aspect + speedX),
                    fract(seedY + t * speedY * 0.2)
                );
                pos.x *= aspect;

                float radius = mix(0.03, 0.09, seedR) * (layer * 0.6);
                float dist = length(p - pos);

                if (dist < radius) {
                    // Spherical aberration: brighter outer rim, soft translucent core
                    float normDist = dist / radius;
                    float ring = smoothstep(0.7, 0.98, normDist) * 1.8 + (1.0 - normDist * normDist) * 0.5;

                    // Color palette: Warm Amber, Rose, Cool Turquoise
                    float3 orbColor;
                    float pal = fract(seedR * 3.0);
                    if (pal < 0.33) {
                        orbColor = float3(1.0, 0.65, 0.25); // Warm Amber
                    } else if (pal < 0.66) {
                        orbColor = float3(0.95, 0.35, 0.65); // Rose
                    } else {
                        orbColor = float3(0.25, 0.85, 0.95); // Turquoise
                    }

                    // Additive luminous blending
                    col += orbColor * ring * (0.18 / layer);
                }
            }
        }

        // Vignette
        float vig = 1.0 - length(uv - 0.5) * 0.5;
        col *= clamp(vig, 0.0, 1.0);

        return float4(col, 1.0);
    }
    """
}

//
//  CommandLineOptions.swift
//  WallpaperEngineCore
//
//  Command-line arguments parsing, validation, and configuration mapping.
//

import CoreGraphics
import Foundation
import OSLog

public struct CommandLineOptions: Equatable, Sendable {
    public var videoPath: String?
    public var targetDisplayID: CGDirectDisplayID?
    public var targetFPS: Int?
    public var throttledFPS: Int?
    public var isHeadless: Bool
    public var showWindow: Bool
    public var isBenchmark: Bool
    public var configPath: String?
    public var isHelpRequested: Bool
    public var isVersionRequested: Bool
    public var dumpConfig: Bool
    public var pauseOnBattery: Bool
    public var pauseOnBatteryOverride: Bool?
    public var unknownOptions: [String]

    // 3D Parallax Photo Scene Options
    public var photoPath: String?
    public var useHeadTracking: Bool
    public var depthIntensity: Float?
    public var focalDepth: Float?

    // Real-Time Procedural Metal & Imported Shader Options
    public var shaderName: String?
    public var shaderPath: String?
    public var shaderSpeed: Float?

    // Desktop HUD & Audio Reactive Options
    public var isHUDEnabled: Bool?
    public var hudPosition: EngineConfig.HUDConfig.HUDPosition?
    public var isAudioReactive: Bool?

    // Convenience aliases
    public var displayID: CGDirectDisplayID? {
        get { targetDisplayID }
        set { targetDisplayID = newValue }
    }

    public var targetFrameRate: Int? {
        get { targetFPS }
        set { targetFPS = newValue }
    }

    public var throttledFrameRate: Int? {
        get { throttledFPS }
        set { throttledFPS = newValue }
    }

    public var isDumpConfigRequested: Bool {
        get { dumpConfig }
        set { dumpConfig = newValue }
    }

    public init(
        videoPath: String? = nil,
        photoPath: String? = nil,
        useHeadTracking: Bool = false,
        depthIntensity: Float? = nil,
        focalDepth: Float? = nil,
        shaderName: String? = nil,
        shaderPath: String? = nil,
        shaderSpeed: Float? = nil,
        isHUDEnabled: Bool? = nil,
        hudPosition: EngineConfig.HUDConfig.HUDPosition? = nil,
        isAudioReactive: Bool? = nil,
        targetDisplayID: CGDirectDisplayID? = nil,
        displayID: CGDirectDisplayID? = nil,
        targetFPS: Int? = nil,
        targetFrameRate: Int? = nil,
        throttledFPS: Int? = nil,
        throttledFrameRate: Int? = nil,
        isHeadless: Bool = false,
        showWindow: Bool = true,
        isBenchmark: Bool = false,
        configPath: String? = nil,
        isHelpRequested: Bool = false,
        isVersionRequested: Bool = false,
        dumpConfig: Bool = false,
        isDumpConfigRequested: Bool = false,
        pauseOnBattery: Bool = false,
        pauseOnBatteryOverride: Bool? = nil,
        unknownOptions: [String] = []
    ) {
        self.videoPath = videoPath
        self.photoPath = photoPath
        self.useHeadTracking = useHeadTracking
        self.depthIntensity = depthIntensity
        self.focalDepth = focalDepth
        self.shaderName = shaderName
        self.shaderPath = shaderPath
        self.shaderSpeed = shaderSpeed
        self.isHUDEnabled = isHUDEnabled
        self.hudPosition = hudPosition
        self.isAudioReactive = isAudioReactive
        self.targetDisplayID = targetDisplayID ?? displayID
        let resolvedFPS = targetFPS ?? targetFrameRate
        self.targetFPS = resolvedFPS.flatMap { $0 > 0 ? $0 : nil }
        let resolvedThrottled = throttledFPS ?? throttledFrameRate
        self.throttledFPS = resolvedThrottled.flatMap { $0 > 0 ? $0 : nil }
        self.isHeadless = isHeadless
        self.showWindow = !isHeadless && showWindow
        self.isBenchmark = isBenchmark
        self.configPath = configPath
        self.isHelpRequested = isHelpRequested
        self.isVersionRequested = isVersionRequested
        self.dumpConfig = dumpConfig || isDumpConfigRequested
        self.pauseOnBattery = pauseOnBattery || (pauseOnBatteryOverride == true)
        self.pauseOnBatteryOverride = pauseOnBatteryOverride ?? (pauseOnBattery ? true : nil)
        self.unknownOptions = unknownOptions
    }

    public static func parse(arguments: [String] = CommandLine.arguments) -> CommandLineOptions {
        var options = CommandLineOptions()
        var unknown: [String] = []

        // Strip executable path if present as the first token
        let tokens: [String]
        if let first = arguments.first, !first.hasPrefix("-") && arguments.count > 1 {
            tokens = Array(arguments.dropFirst())
        } else if let first = arguments.first, !first.hasPrefix("-") && arguments.count == 1 {
            tokens = []
        } else {
            tokens = arguments
        }

        func isFlag(_ token: String) -> Bool {
            guard token.hasPrefix("-") else { return false }
            if Double(token) != nil { return false }
            return true
        }

        var idx = 0
        while idx < tokens.count {
            let token = tokens[idx]

            // Check inline equal syntax: --flag=value
            if token.hasPrefix("--") && token.contains("=") {
                let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
                let flag = parts[0]
                let val = parts.count > 1 ? parts[1] : ""
                handleKeyValue(flag: flag, value: val, options: &options, unknown: &unknown)
                idx += 1
                continue
            }

            switch token {
            case "--video":
                if idx + 1 < tokens.count && !isFlag(tokens[idx + 1]) {
                    options.videoPath = tokens[idx + 1]
                    idx += 2
                } else {
                    unknown.append(token)
                    idx += 1
                }

            case "--display":
                if idx + 1 < tokens.count && !isFlag(tokens[idx + 1]) {
                    let val = tokens[idx + 1]
                    if let parsedID = UInt32(val) {
                        options.targetDisplayID = parsedID
                    } else {
                        unknown.append("\(token) \(val)")
                    }
                    idx += 2
                } else {
                    unknown.append(token)
                    idx += 1
                }

            case "--fps":
                if idx + 1 < tokens.count && !isFlag(tokens[idx + 1]) {
                    let val = tokens[idx + 1]
                    if let parsedFPS = Int(val), parsedFPS > 0 {
                        options.targetFPS = parsedFPS
                    } else {
                        unknown.append("\(token) \(val)")
                    }
                    idx += 2
                } else {
                    unknown.append(token)
                    idx += 1
                }

            case "--throttled-fps":
                if idx + 1 < tokens.count && !isFlag(tokens[idx + 1]) {
                    let val = tokens[idx + 1]
                    if let parsedFPS = Int(val), parsedFPS > 0 {
                        options.throttledFPS = parsedFPS
                    } else {
                        unknown.append("\(token) \(val)")
                    }
                    idx += 2
                } else {
                    unknown.append(token)
                    idx += 1
                }

            case "--config":
                if idx + 1 < tokens.count && !isFlag(tokens[idx + 1]) {
                    options.configPath = tokens[idx + 1]
                    idx += 2
                } else {
                    unknown.append(token)
                    idx += 1
                }

            case "--headless":
                options.isHeadless = true
                options.showWindow = false
                idx += 1

            case "--no-window", "--menu-bar-only":
                options.showWindow = false
                idx += 1

            case "--window", "--gui":
                options.showWindow = true
                idx += 1

            case "--benchmark":
                options.isBenchmark = true
                idx += 1

            case "--help", "-h":
                options.isHelpRequested = true
                idx += 1

            case "--version", "-v":
                options.isVersionRequested = true
                idx += 1

            case "--dump-config":
                options.dumpConfig = true
                idx += 1

            case "--pause-on-battery":
                options.pauseOnBattery = true
                options.pauseOnBatteryOverride = true
                idx += 1

            case "--photo":
                if idx + 1 < tokens.count && !isFlag(tokens[idx + 1]) {
                    options.photoPath = tokens[idx + 1]
                    idx += 2
                } else {
                    unknown.append(token)
                    idx += 1
                }

            case "--head-tracking":
                options.useHeadTracking = true
                idx += 1

            case "--depth", "--depth-intensity":
                if idx + 1 < tokens.count && !isFlag(tokens[idx + 1]) {
                    let val = tokens[idx + 1]
                    if let parsed = Float(val) {
                        options.depthIntensity = parsed
                    } else {
                        unknown.append("\(token) \(val)")
                    }
                    idx += 2
                } else {
                    unknown.append(token)
                    idx += 1
                }

            case "--focal", "--focal-depth":
                if idx + 1 < tokens.count && !isFlag(tokens[idx + 1]) {
                    let val = tokens[idx + 1]
                    if let parsed = Float(val) {
                        options.focalDepth = parsed
                    } else {
                        unknown.append("\(token) \(val)")
                    }
                    idx += 2
                } else {
                    unknown.append(token)
                    idx += 1
                }

            case "--shader":
                if idx + 1 < tokens.count && !isFlag(tokens[idx + 1]) {
                    let val = tokens[idx + 1]
                    let isPath = val.hasPrefix("/") || val.hasPrefix("./") || val.hasPrefix("../") ||
                                 ["metal", "frag", "glsl", "shadertoy", "txt"].contains(URL(fileURLWithPath: val).pathExtension.lowercased()) ||
                                 FileManager.default.fileExists(atPath: val)
                    if isPath {
                        options.shaderPath = val
                    } else {
                        options.shaderName = val
                    }
                    idx += 2
                } else {
                    unknown.append(token)
                    idx += 1
                }

            case "--shader-speed", "--speed":
                if idx + 1 < tokens.count && !isFlag(tokens[idx + 1]) {
                    let val = tokens[idx + 1]
                    if let parsed = Float(val) {
                        options.shaderSpeed = parsed
                    } else {
                        unknown.append("\(token) \(val)")
                    }
                    idx += 2
                } else {
                    unknown.append(token)
                    idx += 1
                }

            case "--hud":
                options.isHUDEnabled = true
                idx += 1

            case "--no-hud":
                options.isHUDEnabled = false
                idx += 1

            case "--hud-position":
                if idx + 1 < tokens.count && !isFlag(tokens[idx + 1]) {
                    let val = tokens[idx + 1]
                    options.hudPosition = EngineConfig.HUDConfig.HUDPosition(rawValue: val)
                    idx += 2
                } else {
                    unknown.append(token)
                    idx += 1
                }

            case "--audio-reactive":
                options.isAudioReactive = true
                idx += 1

            case "--no-audio-reactive":
                options.isAudioReactive = false
                idx += 1

            default:
                unknown.append(token)
                idx += 1
            }
        }

        options.unknownOptions = unknown
        return options
    }

    private static func handleKeyValue(flag: String, value: String, options: inout CommandLineOptions, unknown: inout [String]) {
        switch flag {
        case "--video":
            options.videoPath = value.isEmpty ? nil : value
        case "--photo":
            options.photoPath = value.isEmpty ? nil : value
        case "--shader":
            if value.isEmpty {
                options.shaderName = nil
                options.shaderPath = nil
            } else {
                let isPath = value.hasPrefix("/") || value.hasPrefix("./") || value.hasPrefix("../") ||
                             ["metal", "frag", "glsl", "shadertoy", "txt"].contains(URL(fileURLWithPath: value).pathExtension.lowercased()) ||
                             FileManager.default.fileExists(atPath: value)
                if isPath {
                    options.shaderPath = value
                } else {
                    options.shaderName = value
                }
            }
        case "--shader-speed", "--speed":
            if let s = Float(value) {
                options.shaderSpeed = s
            } else {
                unknown.append("\(flag)=\(value)")
            }
        case "--head-tracking":
            options.useHeadTracking = (value.lowercased() != "false" && value != "0")
        case "--depth", "--depth-intensity":
            if let d = Float(value) {
                options.depthIntensity = d
            } else {
                unknown.append("\(flag)=\(value)")
            }
        case "--focal", "--focal-depth":
            if let f = Float(value) {
                options.focalDepth = f
            } else {
                unknown.append("\(flag)=\(value)")
            }
        case "--display":
            if let id = UInt32(value) {
                options.targetDisplayID = id
            } else {
                unknown.append("\(flag)=\(value)")
            }
        case "--fps":
            if let fps = Int(value), fps > 0 {
                options.targetFPS = fps
            } else {
                unknown.append("\(flag)=\(value)")
            }
        case "--throttled-fps":
            if let fps = Int(value), fps > 0 {
                options.throttledFPS = fps
            } else {
                unknown.append("\(flag)=\(value)")
            }
        case "--config":
            options.configPath = value.isEmpty ? nil : value
        case "--hud":
            options.isHUDEnabled = (value.lowercased() != "false" && value != "0")
        case "--no-hud":
            options.isHUDEnabled = false
        case "--hud-position":
            options.hudPosition = EngineConfig.HUDConfig.HUDPosition(rawValue: value)
        case "--audio-reactive":
            options.isAudioReactive = (value.lowercased() != "false" && value != "0")
        case "--no-audio-reactive":
            options.isAudioReactive = false
        default:
            unknown.append("\(flag)=\(value)")
        }
    }

    /// Applies command-line overrides to an existing EngineConfig instance.
    public func apply(to config: inout EngineConfig) {
        if let fps = targetFPS {
            config.targetFrameRate = fps
        }
        if let throttled = throttledFPS {
            config.throttledFrameRate = min(throttled, config.targetFrameRate)
        }
        if pauseOnBattery || (pauseOnBatteryOverride == true) {
            config.pauseOnBattery = true
        }
        if let video = videoPath {
            if let targetDisplay = targetDisplayID {
                let key = String(targetDisplay)
                var displayCfg = config.displayConfigurations[key] ?? DisplayConfig()
                displayCfg.assetPath = video
                displayCfg.shaderName = nil
                displayCfg.shaderPath = nil
                displayCfg.photoPath = nil
                config.displayConfigurations[key] = displayCfg
            } else {
                config.defaultAssetPath = video
                config.shaderName = nil
                config.shaderPath = nil
                config.photoPath = nil
            }
        }
        if let photo = photoPath {
            if let targetDisplay = targetDisplayID {
                let key = String(targetDisplay)
                var displayCfg = config.displayConfigurations[key] ?? DisplayConfig()
                displayCfg.photoPath = photo
                displayCfg.assetPath = nil
                displayCfg.shaderName = nil
                displayCfg.shaderPath = nil
                config.displayConfigurations[key] = displayCfg
            } else {
                config.photoPath = photo
                config.defaultAssetPath = nil
                config.shaderName = nil
                config.shaderPath = nil
            }
        }
        if let shader = shaderName {
            if let targetDisplay = targetDisplayID {
                let key = String(targetDisplay)
                var displayCfg = config.displayConfigurations[key] ?? DisplayConfig()
                displayCfg.shaderName = shader
                displayCfg.shaderPath = nil
                displayCfg.photoPath = nil
                displayCfg.assetPath = nil
                config.displayConfigurations[key] = displayCfg
            } else {
                config.shaderName = shader
                config.shaderPath = nil
                config.photoPath = nil
                config.defaultAssetPath = nil
            }
        }
        if let path = shaderPath {
            if let targetDisplay = targetDisplayID {
                let key = String(targetDisplay)
                var displayCfg = config.displayConfigurations[key] ?? DisplayConfig()
                displayCfg.shaderPath = path
                displayCfg.shaderName = nil
                displayCfg.photoPath = nil
                displayCfg.assetPath = nil
                config.displayConfigurations[key] = displayCfg
            } else {
                config.shaderPath = path
                config.shaderName = nil
                config.photoPath = nil
                config.defaultAssetPath = nil
            }
        }
        if let speed = shaderSpeed {
            config.shaderSpeed = speed
        }
        if useHeadTracking {
            config.useHeadTracking = true
        }
        if let depth = depthIntensity {
            config.depthIntensity = depth
        }
        if let focal = focalDepth {
            config.focalDepth = focal
        }
        if let hud = isHUDEnabled {
            config.hudConfig.isEnabled = hud
        }
        if let pos = hudPosition {
            config.hudConfig.position = pos
        }
        if let audio = isAudioReactive {
            config.isAudioReactive = audio
        }
    }

    public static var versionString: String {
        "Wallpaper Engine Core version 1.0.0 (build 20261015)"
    }

    public static var usageString: String {
        return """
        Wallpaper Engine Core — High-Performance Native macOS Desktop Wallpaper Engine

        USAGE:
          wallpaper_engine_core [OPTIONS]

        OPTIONS:
          --video <path>          Override default wallpaper asset path (MP4/MOV)
          --photo <path>          Set 2D photo path to infer depth and render as 3D parallax
          --shader <name|path>    Load procedural preset (aurora, starfield, gradientFlow, cyberpunkGrid, bokeh) or custom shader path (.metal, .shadertoy)
          --shader-speed <speed>  Set procedural shader animation speed multiplier (e.g. 0.5, 1.0, 2.0)
          --hud                   Enable glassmorphic desktop HUD (Clock, Stats, Now Playing, Spectrum)
          --no-hud                Disable desktop HUD overlays
          --hud-position <pos>    Set HUD anchor (topRight, topLeft, bottomRight, bottomLeft, topCenter)
          --audio-reactive        Enable CoreAudio spectrum analysis for shaders and visualizer
          --no-audio-reactive     Disable audio reactivity
          --head-tracking         Enable webcam head tracking for perspective parallax
          --depth <intensity>     Set 3D parallax depth intensity (default: 0.04)
          --focal <depth>         Set 3D parallax focal plane (default: 0.5)
          --display <id>          Target specific display ID for asset override (UInt32)
          --fps <rate>            Override target rendering frame rate (e.g. 30, 60, 120)
          --throttled-fps <rate>  Override power-throttled frame rate (e.g. 15, 30)
          --headless              Run in background daemon mode without Menu Bar NSStatusItem
          --benchmark             Execute playback telemetry benchmark and exit
          --config <path>         Load configuration from custom JSON path
          --dump-config           Print loaded configuration JSON to stdout and exit
          --pause-on-battery      Enable automatic pause when running on battery power
          -v, --version           Print version information and exit
          -h, --help              Print this help information and exit
        """
    }
}

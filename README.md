# Wallpaper Engine Core (macOS)

An open-source, high-performance native macOS live desktop wallpaper engine. Built with Swift 6, AppKit, AVFoundation, and IOKit.

## Key Features

- **Desktop Window Attachment (`kCGDesktopWindowLevelKey`)**: Injects non-activating, borderless windows strictly beneath user desktop files and icons (`ignoresMouseEvents = true`).
- **Seamless Mission Control & Spaces Integration**: Full `.canJoinAllSpaces`, `.stationary`, and `.ignoresCycle` support — persists across Spaces without appearing in `Cmd+Tab` or window switchers.
- **Dynamic Multi-Monitor Management**: Detects display connect/disconnect, resolution changes, and sleep/wake events with automatic layout reconciliation and zero memory leaks.
- **Hardware-Accelerated Looping Video Engine**: Uses `AVPlayerLooper` and `AVQueuePlayer` for gapless, zero-flash video looping (MP4/MOV) with 4-tier audio suppression.
- **AI 3D Parallax Photo Scenes**:
  - Converts standard 2D photos into dynamic 3D depth-displaced scenes via Depth Anything V2 CoreML neural models.
  - Interactive mouse/trackpad pointer parallax driver (with clamp physics and smoothing).
  - Head-tracking support via Apple's Vision framework.
- **Real-Time Metal Procedural Shaders**:
  - 5 high-performance built-in procedural presets: `aurora`, `starfield`, `gradientFlow`, `cyberpunkGrid`, `bokeh`.
  - Full Shadertoy GLSL / MSL importer with automatic syntax wrapping and coordinate inversion.
  - Dynamic runtime speed multiplier and hot-reloading.
- **Audio-Reactive Visualizer**:
  - Live system audio capture via `ScreenCaptureKit` stream tap.
  - High-performance frequency decomposition with Accelerate `vDSP` 1024-point FFT into 16 frequency bands.
  - Drives live Metal shaders via `iAudio`, `iBass`, `iMid`, `iTreble`, and `iAmplitude` uniform parameters.
  - Organic 120 BPM rhythmic fallback simulation if screen recording permission is withheld.
- **Glassmorphic Desktop HUD & Widgets**:
  - Native `NSVisualEffectView` HUD overlay anchored to desktop corners (`topRight`, `topLeft`, `bottomRight`, `bottomLeft`, `topCenter`).
  - Customizable widgets: Live Time/Date, Mach host CPU/RAM & FPS telemetry badges, Now Playing card (Spotify & Apple Music), and a 16-band live spectrum visualizer.
  - Click-through event passthrough: desktop icons underneath remain fully clickable.
- **Intelligent Power & Environment Throttling**:
  - Automatically pauses when displays sleep or when the screen is locked (`com.apple.screenIsLocked`).
  - Automatically pauses or throttles (e.g. 60 FPS -> 30 FPS) when running on battery or when Low Power Mode is enabled.
  - Per-display window occlusion awareness (pauses playback when full-screen apps completely cover the desktop).
- **Native Menu Bar Extra (`NSStatusItem`)**: Quick controls for switching between Video, Parallax, and Shader engines; toggling HUD and Audio-Reactive modes; and selecting HUD positions.
- **Configurable CLI & JSON Persistence**: Run as a standalone daemon (`--headless`), pass custom flags, or persist settings via `~/.config/WallpaperEngineCore/config.json`.

---

## 🚀 Direct Download & Installation

### Option 1: Direct Download (.dmg)
Download the standalone macOS application installer directly:
- **Download Link**: [**Download WallpaperEngine-v1.0.0.dmg**](https://github.com/NIWDOGLEOJ/MAC-Wallpaperengine/releases/latest/download/WallpaperEngine-v1.0.0.dmg)
- Open the downloaded `.dmg` file.
- Drag **Wallpaper Engine.app** into your **Applications** folder.
- Double-click **Wallpaper Engine** to launch! The interactive management window and Menu Bar item will appear immediately.

### Option 2: Build Distributable DMG from Source
To package the app and `.dmg` locally at any time:
```bash
./scripts/package_app.sh
```
This automatically compiles the optimized release binary, bundles `Wallpaper Engine.app` with icons and CoreML models, ad-hoc codesigns the app, and outputs `dist/WallpaperEngine-v1.0.0.dmg`.

---

## Directory Structure

```
Sources/
├── WallpaperEngineApp/             # Native executable daemon entrypoint
│   └── main.swift
└── WallpaperEngineCore/            # Core engine framework
    ├── Audio/                      # Audio-Reactive & Media capture
    │   ├── AudioSpectrumAnalyzer.swift   # vDSP 1024-point FFT analyzer
    │   ├── AudioSpectrumData.swift       # 16-band energy & SIMD4 uniforms
    │   ├── NowPlayingMonitor.swift       # Spotify / Apple Music metadata
    │   └── SystemAudioCapture.swift      # ScreenCaptureKit system audio tap
    ├── Coordinator/                # App lifecycle & CLI parsing
    │   ├── AppCoordinator.swift
    │   └── CommandLineOptions.swift
    ├── HUD/                        # Glassmorphic desktop overlays
    │   ├── DesktopHUDView.swift          # NSVisualEffectView widget panel
    │   └── SystemTelemetryMonitor.swift  # Mach host CPU/RAM/FPS probes
    ├── MenuBar/                    # Status item & quick menu controls
    │   └── MenuBarController.swift
    ├── Models/                     # Domain state & Codable config
    │   ├── DisplayInfo.swift
    │   ├── EngineConfig.swift
    │   └── PlaybackState.swift
    ├── Parallax/                   # AI 3D Parallax Scene Engine
    │   ├── DepthEstimator.swift          # CoreML Depth Anything V2
    │   ├── ParallaxMeshRenderer.swift    # Metal 3D vertex displacement
    │   ├── ParallaxWallpaperView.swift   # MTKView layer
    │   └── PointerParallaxDriver.swift   # Mouse/head pointer tracking
    ├── Power/                      # Power source & display environment observers
    │   ├── OcclusionManager.swift
    │   ├── PowerObserver.swift
    │   ├── SleepLockObserver.swift
    │   └── StateEvaluator.swift
    ├── Shaders/                    # Real-Time Metal Procedural Shaders
    │   ├── MetalShaderRenderer.swift     # Metal pipeline & shader compilation
    │   ├── ProceduralShaderPreset.swift  # Aurora, Starfield, Bokeh, etc.
    │   ├── ShaderWallpaperView.swift     # Real-time render MTKView
    │   └── ShadertoyCompatibility.swift  # GLSL to MSL compatibility bridge
    ├── Video/                      # AVFoundation video looping & stall watchdog
    │   ├── AssetManager.swift
    │   ├── DisplayVideoPlayer.swift
    │   ├── StallWatchdog.swift
    │   └── VideoEngine.swift
    └── Window/                     # Desktop window levels & multi-screen reconciler
        ├── DesktopWindow.swift
        ├── DesktopWindowManager.swift
        └── ScreenManager.swift

Tests/
├── E2ETests/                       # Comprehensive E2E Test Suite (220 tests, Tiers 1–4)
└── WallpaperEngineCoreTests/       # Unit & Adversarial Stress Probe Suites (233 tests)
```

---

## Building and Running

### Requirements
- macOS 13.0 (Ventura) or newer
- Swift 6.0+ toolchain (Xcode or Command Line Tools)
- Apple Silicon (M1/M2/M3/M4) or Intel Mac with Metal support

### Build Release Binary
```bash
swift build --product WallpaperEngineApp -c release
```
The executable is generated at:
```
.build/release/WallpaperEngineApp
```

### Quick Run Examples

#### 1. Procedural Shader with Audio Reactivity & HUD
```bash
./.build/release/WallpaperEngineApp --shader aurora --audio-reactive --hud --hud-position topRight
```

#### 2. Cyberpunk Grid at 1.5x Speed with Bottom-Left HUD
```bash
./.build/release/WallpaperEngineApp --shader cyberpunkGrid --shader-speed 1.5 --hud --hud-position bottomLeft
```

#### 3. Custom Shadertoy / Metal Shader File
```bash
./.build/release/WallpaperEngineApp --shader-file /path/to/my_shader.metal --audio-reactive
```

#### 4. AI 3D Parallax Wallpaper from a 2D Photo
```bash
./.build/release/WallpaperEngineApp --parallax /path/to/photo.jpg
```

#### 5. Custom Looping Video Wallpaper
```bash
./.build/release/WallpaperEngineApp --video /path/to/wallpaper.mp4
```

#### 6. Headless Background Daemon
```bash
./.build/release/WallpaperEngineApp --shader starfield --headless
```

---

## Command Line Options

```
OPTIONS:
  --video <path>          Override default wallpaper asset path (MP4/MOV)
  --shader <preset>       Activate procedural shader preset (aurora, starfield,
                          gradientFlow, cyberpunkGrid, bokeh)
  --shader-file <path>    Load custom Metal or Shadertoy shader source file
  --shader-speed <speed>  Set shader animation speed multiplier (default: 1.0)
  --parallax <path>       Activate AI 3D parallax photo wallpaper from 2D image
  --no-parallax           Disable parallax mode
  --audio-reactive        Enable ScreenCaptureKit audio-reactive visualizer
  --no-audio-reactive     Disable audio reactivity
  --hud                   Display glassmorphic desktop HUD & telemetry widgets
  --no-hud                Disable desktop HUD
  --hud-position <pos>    Set HUD anchor (topRight, topLeft, bottomRight,
                          bottomLeft, topCenter)
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
```

---

## Verification & Test Results

Run all test suites:

```bash
# Run the 220 End-to-End tests
swift test

# Run the 233 Unit, Shader, Parallax, Audio, and HUD tests
swift run WallpaperEngineCoreTests
```

Both test suites execute with a **100% pass rate (453 / 453 tests passed)**, validating strict Swift 6 concurrency, Accelerate FFT calculations, Metal shader pipelines, ScreenCaptureKit audio streams, Mach host telemetry, and desktop window hierarchy.

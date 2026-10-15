# Wallpaper Engine Core (macOS)

An open-source, high-performance native macOS live desktop wallpaper engine. Built with Swift 6, AppKit, AVFoundation, and IOKit.

## Key Features

- **Desktop Window Attachment (`kCGDesktopWindowLevelKey`)**: Injects non-activating, borderless windows strictly beneath user desktop files and icons (`ignoresMouseEvents = true`).
- **Seamless Mission Control & Spaces Integration**: Full `.canJoinAllSpaces`, `.stationary`, and `.ignoresCycle` support — persists across Spaces without appearing in `Cmd+Tab` or window switchers.
- **Dynamic Multi-Monitor Management**: Detects display connect/disconnect, resolution changes, and sleep/wake events with automatic layout reconciliation and zero memory leaks.
- **Hardware-Accelerated Looping Video Engine**: Uses `AVPlayerLooper` and `AVQueuePlayer` for gapless, zero-flash video looping (MP4/MOV) with 4-tier audio suppression.
- **Per-Display Video Routing**: Assign different videos to different monitors or maintain synchronized multi-display setups.
- **Intelligent Power & Environment Throttling**:
  - Automatically pauses when displays sleep or when the screen is locked (`com.apple.screenIsLocked`).
  - Automatically pauses or throttles (e.g. 60 FPS -> 30 FPS) when running on battery or when Low Power Mode is enabled.
  - Per-display window occlusion awareness (pauses playback when full-screen apps completely cover the desktop).
- **Native Menu Bar Extra (`NSStatusItem`)**: Quick play/pause toggling, display picker, video selector, preferences, and clean quit without requiring an open window.
- **Configurable CLI & JSON Persistence**: Run as a standalone daemon (`--headless`), pass custom video flags (`--video /path/to/video.mp4`), or persist settings via `~/.config/WallpaperEngineCore/config.json`.

---

## Directory Structure

```
Sources/
├── WallpaperEngineApp/             # Native executable daemon entrypoint
│   └── main.swift
└── WallpaperEngineCore/            # Core engine framework
    ├── Coordinator/                # App lifecycle & CLI parsing
    │   ├── AppCoordinator.swift
    │   └── CommandLineOptions.swift
    ├── MenuBar/                    # Status item & quick menu controls
    │   └── MenuBarController.swift
    ├── Models/                     # Domain state & Codable config
    │   ├── DisplayInfo.swift
    │   ├── EngineConfig.swift
    │   └── PlaybackState.swift
    ├── Power/                      # Power source & display environment observers
    │   ├── OcclusionManager.swift
    │   ├── PowerObserver.swift
    │   ├── SleepLockObserver.swift
    │   └── StateEvaluator.swift
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
└── WallpaperEngineCoreTests/       # Unit & Adversarial Stress Probe Suites (206 tests)
```

---

## Building and Running

### Requirements
- macOS 13.0 (Ventura) or newer
- Swift 6.0+ toolchain (Xcode or Command Line Tools)

### Build Release Binary
```bash
swift build --product WallpaperEngineApp -c release
```
The executable is generated at:
```
.build/release/WallpaperEngineApp
```

### Run with a Custom Video
```bash
./.build/release/WallpaperEngineApp --video /path/to/your/wallpaper.mp4
```

### Run Headless (Daemon Mode)
```bash
./.build/release/WallpaperEngineApp --video /path/to/wallpaper.mp4 --headless
```

### Inspect Configuration
```bash
./.build/release/WallpaperEngineApp --dump-config
```

---

## Command Line Options

```
OPTIONS:
  --video <path>          Override default wallpaper asset path (MP4/MOV)
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

# Run the 206 Unit & Adversarial Challenger tests
swift run WallpaperEngineCoreTests
```

Both suites execute with **100% pass rate (426 / 426 tests passed)**, verifying window level hierarchy, memory management, zero-leak display tear-down, hardware acceleration, audio suppression, and power-state transitions.

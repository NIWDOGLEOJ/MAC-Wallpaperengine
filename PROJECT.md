# Project: Wallpaper Engine Core (macOS Native Live Wallpaper Engine)

## Architecture
Wallpaper Engine Core is designed as a modular, lightweight, high-performance native macOS system utility built in Swift 6. It operates as an accessory UI element (`LSUIElement = 1`), rendering hardware-accelerated looping video wallpapers directly beneath desktop icons across all connected displays without stealing focus, interfering with Finder gestures, or leaking resources.

```
                      ┌───────────────────────────────────────┐
                      │          MenuBarController            │
                      │     (NSStatusItem, Menus, App UI)     │
                      └──────────────────┬────────────────────┘
                                         │ User Actions / Config
                                         ▼
                      ┌───────────────────────────────────────┐
                      │            AppCoordinator             │
                      │   (Lifecycle, Orchestration, State)   │
                      └───────┬──────────────┬──────────────┬─┘
                              │              │              │
              ┌───────────────┘              │              └───────────────┐
              ▼                              ▼                              ▼
  ┌───────────────────────┐      ┌───────────────────────┐      ┌───────────────────────┐
  │  Screen & Window Mgr  │      │  State & Power Observers│    │  Video Playback Engine│
  │  - ScreenManager      │      │  - PowerObserver      │      │  - VideoEngine        │
  │  - DesktopWindow      │      │  - SleepLockObserver  │      │  - DisplayVideoPlayer │
  │  - DesktopWindowManager│     │  - OcclusionManager   │      │  - AVPlayerLooper     │
  └───────────┬───────────┘      │  - StateEvaluator     │      │  - AssetManager       │
              │                  └───────────┬───────────┘      └───────────┬───────────┘
              │                              │                              │
              └──────────────────────────────┼──────────────────────────────┘
                                             ▼
                             ┌───────────────────────────────┐
                             │       Desktop Rendering       │
                             │   Level: kCGDesktopWindowLevel│
                             │   Layer: AVPlayerLayer (Scanout)│
                             └───────────────────────────────┘
```

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| F1 | Desktop Window Level | Position window at `kCGDesktopWindowLevelKey` (-2147483623), 20 levels beneath Finder desktop icons (-2147483603) | M1 | ORIGINAL_REQUEST R1 |
| F2 | Spaces & Mission Control | Pinned across all Spaces with `[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]` | M1 | ORIGINAL_REQUEST R1 |
| F3 | Input Event Pass-Through | `ignoresMouseEvents = true`, `canBecomeKey = false`, `canBecomeMain = false`; Finder icons, drags, and context menus fully interactive | M1 | ORIGINAL_REQUEST R1 |
| F4 | Dynamic Display Management | `didChangeScreenParametersNotification` listener, geometry diffing, debounced multi-display reconciliation | M1 | ORIGINAL_REQUEST R1 |
| F5 | Gapless Looping Video | `AVQueuePlayer` + `AVPlayerLooper` pipeline eliminating decoder flushes, black frames, and PTS hitches | M2 | ORIGINAL_REQUEST R2 |
| F6 | Hardware Scanout Acceleration | `AVPlayerLayer` (`.resizeAspectFill`) direct zero-copy IOSurface scanout to WindowServer (< 1.5% CPU on Apple Silicon) | M2 | ORIGINAL_REQUEST R2 |
| F7 | Total Audio Suppression | 4-tier muting (`isMuted = true`, volume = 0, audio tracks disabled, empty `AVAudioMix`) preventing `coreaudiod` wakeups | M2 | ORIGINAL_REQUEST R2 |
| F8 | Multi-Display Video Pipeline | Isolated `DisplayVideoPlayer` per `CGDirectDisplayID`, 2-layer crossfade on asset switch | M2 | ORIGINAL_REQUEST R2 |
| F9 | Video Stall Watchdog | 3.0s stall detection, automatic loop recovery, asset pre-flight validation | M2 | ORIGINAL_REQUEST R2 |
| F10 | IOKit Power Observer | Monitors AC vs Battery power via `IOPSCopyPowerSourcesInfo` and `IOPSNotificationCreateRunLoopSource` | M3 | ORIGINAL_REQUEST R3 |
| F11 | Low Power Mode Observer | `ProcessInfo.processInfo.isLowPowerModeEnabled` and `NSProcessInfoPowerStateDidChange` background queue dispatch | M3 | ORIGINAL_REQUEST R3 |
| F12 | Sleep & Wake Observer | `NSWorkspace.shared.notificationCenter` observing system sleep/wake and display sleep/wake | M3 | ORIGINAL_REQUEST R3 |
| F13 | Screen Lock Observer | Darwin Notification Center (`com.apple.screenIsLocked` / `unlocked`) + `CGSessionCopyCurrentDictionary` validation | M3 | ORIGINAL_REQUEST R3 |
| F14 | Display Occlusion Awareness | `NSWindow.didChangeOcclusionStateNotification` per display, pausing decoding when display or Space is occluded | M3 | ORIGINAL_REQUEST R3 |
| F15 | Pure Functional State Machine | `StateEvaluator.evaluate(...)` consolidating async power, sleep, lock, and occlusion states into `.play`, `.pause`, `.throttle` | M3 | ORIGINAL_REQUEST R3 |
| F16 | Menu Bar Status Controller | Lightweight `NSStatusItem` with template icon, play/pause toggle, display asset picker, preferences, and quit | M4 | ORIGINAL_REQUEST R4 |
| F17 | Configuration & CLI | `EngineConfig` JSON persistence in App Support, command-line arguments (`--video`, `--display`, `--headless`, etc.) | M4 | ORIGINAL_REQUEST R4 |
| F18 | App Coordinator Lifecycle | Ties together WindowManager, VideoEngine, Power/State Observers, and MenuBarController into seamless daemon | M4 | ORIGINAL_REQUEST R4 |
| F19 | Test Suite & Quality Infrastructure | Unit tests, window hierarchy audit, looping continuity test, mock power state harness, and Tiers 1-5 E2E tests | M5 | ORIGINAL_REQUEST Verification |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Desktop Window & Space Hierarchy Management | `ScreenManager`, `DesktopWindow`, `DesktopWindowManager`, screen diffing & notifications (F1-F4) | none | **DONE** |
| M2 | Hardware-Accelerated Looping Video Engine | `VideoEngine`, `DisplayVideoPlayer`, `AVPlayerLooper`, 4-tier audio suppression, stall watchdog (F5-F9) | M1 | **DONE** |
| M3 | Intelligent Power & Display State Throttling | `PowerObserver`, `SleepLockObserver`, `OcclusionManager`, `StateEvaluator` pure functional engine (F10-F15) | M1, M2 | **DONE** |
| M4 | Menu Bar Status & Quick Controller | `MenuBarController`, `EngineConfig`, `CommandLineOptions`, `AppCoordinator` lifecycle (F16-F18) | M1, M2, M3 | **IN_PROGRESS** |
| M5 | Dual Track E2E Test Suite & Adversarial Hardening | Comprehensive test suite (Tiers 1-4), adversarial test hardening (Tier 5), build & performance verification (F19) | M1, M2, M3, M4 | PLANNED |

## Interface Contracts

### M1 ↔ M2: DesktopWindowManager ↔ VideoEngine
- `DesktopWindowProtocol.attachPlayerLayer(_ playerLayer: CALayer)`: Attaches the hardware scanout layer to the window's layer hierarchy beneath desktop icons.
- `DesktopWindowManagerProtocol.window(for displayID: CGDirectDisplayID) -> DesktopWindowProtocol?`: Returns the active desktop window for a given screen ID.
- `DesktopWindowManagerDelegate.displayConfigurationDidChange(added: [CGDirectDisplayID], removed: [CGDirectDisplayID], updated: [CGDirectDisplayID])`: Informs the VideoEngine to spawn, close, or resize display video player pipelines.

### M2 ↔ M3: VideoEngine ↔ ThrottlingCoordinator / StateEvaluator
- `VideoEngineProtocol.setPlaybackState(_ state: PlaybackState, for displayID: CGDirectDisplayID?)`: Commands the video player to play, pause, or throttle frame rate (e.g. 30 FPS vs 60 FPS) per display or globally.
- `PlaybackDecision`: Enum (`.play`, `.pause(reason: PauseReason)`, `.throttle(fps: Int)`).

### M3 ↔ M4: StateEvaluator ↔ AppCoordinator & MenuBarController
- `AppCoordinatorProtocol.handleDecisionChange(_ decision: PlaybackDecision)`: Synchronizes video engine playback and updates Menu Bar status item icon and labels.
- `EngineConfig`: Holds user preferences (e.g. `pauseOnBattery: Bool`, `pauseOnLowPowerMode: Bool`, `pauseWhenOccluded: Bool`, `defaultVideoURL: URL?`).

## Code Layout
```
wallpaper_engine_core/
├── Package.swift                                # SPM package definition (macOS 13+, Swift 6)
├── Sources/
│   ├── WallpaperEngineCore/                     # Core engine library
│   │   ├── Models/
│   │   │   ├── EngineConfig.swift              # Configuration & persistence model
│   │   │   ├── PlaybackState.swift             # Playback states, decisions, pause reasons
│   │   │   └── DisplayInfo.swift               # Screen metadata and geometry models
│   │   ├── Window/
│   │   │   ├── DesktopWindow.swift             # Borderless non-activating NSWindow subclass
│   │   │   ├── ScreenManager.swift             # Screen parameters & notifications observer
│   │   │   └── DesktopWindowManager.swift      # Multi-display window lifecycle coordinator
│   │   ├── Video/
│   │   │   ├── VideoEngine.swift               # AVFoundation playback coordinator
│   │   │   ├── DisplayVideoPlayer.swift        # Single-display AVQueuePlayer + AVPlayerLooper
│   │   │   ├── AssetManager.swift              # Video asset validation & caching
│   │   │   └── StallWatchdog.swift             # 3.0s stall recovery timer
│   │   ├── Power/
│   │   │   ├── PowerObserver.swift             # IOKit AC/Battery & Low Power Mode observer
│   │   │   ├── SleepLockObserver.swift         # NSWorkspace sleep/wake & Darwin lock observer
│   │   │   ├── OcclusionManager.swift          # NSWindow occlusion state tracker
│   │   │   └── StateEvaluator.swift            # Pure functional decision matrix
│   │   ├── MenuBar/
│   │   │   └── MenuBarController.swift         # NSStatusItem quick controller & menu actions
│   │   └── Coordinator/
│   │       ├── AppCoordinator.swift            # Master daemon coordinator
│   │       └── CommandLineOptions.swift        # CLI parsing for headless / custom mode
│   └── WallpaperEngineApp/                     # Executable entrypoint
│       └── main.swift                          # NSApplication initialization & lifecycle
└── Tests/
    ├── WallpaperEngineCoreTests/               # Unit and integration tests
    │   ├── WindowHierarchyTests.swift          # Window level & collection behavior tests
    │   ├── VideoEngineTests.swift              # Looping & audio suppression tests
    │   ├── StateEvaluatorTests.swift           # Pure functional power/sleep/lock matrix tests
    │   └── ConfigPersistenceTests.swift        # Config serialization & loading tests
    └── E2ETests/                               # End-to-end verification suite
        ├── TestHarness.swift                   # Opaque-box E2E test harness
        ├── Tier1_FeatureCoverageTests.swift    # 5+ tests per feature
        ├── Tier2_BoundaryTests.swift           # Edge cases, missing files, zero screens
        ├── Tier3_PairwiseTests.swift           # Power changes during asset switch, etc.
        ├── Tier4_RealWorldTests.swift          # Long-running loop & multi-display simulation
        └── Tier5_AdversarialTests.swift        # Challenger generated stress & chaos tests
```

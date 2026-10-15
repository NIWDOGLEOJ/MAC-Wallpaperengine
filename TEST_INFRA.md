# Wallpaper Engine Core: End-to-End Testing Infrastructure & Opaque-Box Suite Specification

## 1. Opaque-Box Test Philosophy

The testing architecture for **Wallpaper Engine Core** adheres strictly to the **Opaque-Box Testing Philosophy**. 

In live desktop wallpaper engines, internal implementation details (such as whether an internal helper is called or which private dispatch queue is selected) must never be the subject of brittle assertions. Instead, the test suite verifies **observable system behavior, OS contract compliance, and end-to-end interface integrity** as mandated by `ORIGINAL_REQUEST.md`:

1. **System & WindowServer Contract Invariants**:
   - Windows must strictly reside at `kCGDesktopWindowLevelKey` (`-2147483623`), exactly 20 levels below Finder desktop icons (`-2147483603`), and above the WindowServer wallpaper canvas (`-2147483624`).
   - Window collection behaviors must strictly enforce `[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]` so they never float into Mission Control or intercept window cycling (`Cmd+Tab`).
   - Mouse events must pass through completely (`ignoresMouseEvents = true`), allowing Finder desktop selection, marquee drag-selection, and desktop context menus to operate without interference.

2. **Hardware Playback & Looping Invariants**:
   - Looping video playback must be gapless and seamless (zero black frames, continuous presentation timestamps).
   - Hardware-accelerated scanout (`AVPlayerLayer` direct to WindowServer) must incur minimal CPU footprint (< 1.5% on Apple Silicon).
   - 4-tier defensive audio suppression ensures the audio engine (`coreaudiod`) is never awakened.

3. **Power, Sleep, Lock, & Occlusion State Invariants**:
   - Playback must immediately pause upon display sleep, system sleep, screen lock, or session inactivation, and resume when conditions normalize.
   - Throttling and pausing must conform to user configuration when running on battery or Low Power Mode.
   - The pure functional state evaluator `StateEvaluator.evaluate(...)` must deterministically resolve multi-variable state changes without race conditions or invalid resume states.

4. **Usability & Lifecycle Invariants**:
   - Menu Bar status controller operates as an unactivated accessory (`LSUIElement = 1`), never stealing keyboard focus from active user apps.
   - Configuration persistence roundtrips atomically to `~/Library/Application Support/WallpaperEngineCore/config.json`.
   - Multi-display connect, disconnect, and resolution change events trigger layout reconciliation with zero orphan windows or memory leaks.

---

## 2. Feature Inventory Mapping (F1 – F19)

The suite provides exhaustive, verified coverage across all 19 features defined in `PROJECT.md`:

| Feature ID | Feature Name | Core Verification Target | Primary Tier 1 Isolation Coverage |
|:---|:---|:---|:---|
| **F1** | Desktop Window Level | Position at `CGWindowLevelForKey(.desktopWindow)` (`-2147483623`), 20 levels below Finder icons (`-2147483603`) | 5 isolation tests verifying exact level, relation to icons, base window, and layer hierarchy |
| **F2** | Spaces & Mission Control | Collection behaviors `[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]` | 5 isolation tests verifying each bitmask flag and combined bitmask |
| **F3** | Input Event Pass-Through | `ignoresMouseEvents = true`, `canBecomeKey = false`, `canBecomeMain = false` | 5 isolation tests verifying click-through, non-activating traits, and responder chain bypass |
| **F4** | Dynamic Display Management | `didChangeScreenParametersNotification`, geometry diffing, debounced reconciliation | 5 isolation tests verifying display add, remove, resize, debounce timer, and coordinate mapping |
| **F5** | Gapless Looping Video | `AVQueuePlayer` + `AVPlayerLooper`, PTS continuity, closed GOP boundaries | 5 isolation tests verifying looper creation, queue buffering, gapless loop advance, and error handling |
| **F6** | Hardware Scanout Acceleration | `AVPlayerLayer` (`.resizeAspectFill`), zero-copy scanout, action animation disabling | 5 isolation tests verifying layer hosting, gravity, action dictionary nulling, and frame matching |
| **F7** | Total Audio Suppression | 4-tier muting (player muted, volume = 0, audio tracks disabled, empty `AVAudioMix`) | 5 isolation tests verifying all 4 tiers of silence enforcement |
| **F8** | Multi-Display Video Pipeline | Isolated `DisplayVideoPlayer` per display, 2-layer crossfade on asset switch | 5 isolation tests verifying display isolation, crossfade layer insertion, opacity swap, and teardown |
| **F9** | Video Stall Watchdog | 3.0s stall detection, automatic loop recovery, asset pre-flight validation | 5 isolation tests verifying stall timer trigger, rate retry, hard looper rebuild, and recovery limits |
| **F10** | IOKit Power Observer | Monitors AC vs Battery power via `IOPSCopyPowerSourcesInfo` and dynamic notifications | 5 isolation tests verifying AC detection, battery detection, charging status, and runloop source |
| **F11** | Low Power Mode Observer | `ProcessInfo.processInfo.isLowPowerModeEnabled` and `NSProcessInfoPowerStateDidChange` | 5 isolation tests verifying LPM detection, notification dispatch, state transitions, and background thread safety |
| **F12** | Sleep & Wake Observer | `NSWorkspace` sleep/wake and display sleep/wake notification handling | 5 isolation tests verifying willSleep, didWake, screensDidSleep, screensDidWake, and workspace center binding |
| **F13** | Screen Lock Observer | Darwin `com.apple.screenIsLocked`/`unlocked` + `CGSessionCopyCurrentDictionary` | 5 isolation tests verifying lock notification, unlock notification, session query, and Darwin dealloc cleanup |
| **F14** | Display Occlusion Awareness | `NSWindow.didChangeOcclusionStateNotification` per display, pausing decoding when occluded | 5 isolation tests verifying occlusion registration, visible vs hidden state, Space change sweeps, and multi-display independence |
| **F15** | Pure Functional State Machine | `StateEvaluator.evaluate(...)` consolidating async states into `.play`, `.pause`, `.throttle` | 5 isolation tests verifying decision matrix, pause precedence, throttle conditions, and config overrides |
| **F16** | Menu Bar Status Controller | Lightweight `NSStatusItem` with template icon, play/pause toggle, display picker, quit | 5 isolation tests verifying status item initialization, menu items, action forwarding, and non-activating presentation |
| **F17** | Configuration & CLI | `EngineConfig` JSON persistence in App Support, CLI arguments parsing | 5 isolation tests verifying Codable roundtrip, default values, atomic file persistence, CLI flag parsing, and corrupt file fallback |
| **F18** | App Coordinator Lifecycle | Master daemon coordinator wiring WindowManager, VideoEngine, Observers, MenuBar | 5 isolation tests verifying lifecycle start/stop, observer synchronization, event propagation, and graceful shutdown |
| **F19** | Test Suite & Quality Infrastructure | Unit tests, window hierarchy audit, looping continuity test, mock harness, E2E runner | 5 isolation tests verifying test harness capabilities, mock injections, telemetry tracking, and assertion engines |

---

## 3. Test Suite Architecture & Directory Layout

The E2E test suite resides strictly within `Tests/E2ETests/` in the project root:

```
wallpaper_engine_core/
└── Tests/
    └── E2ETests/
        ├── TestHarness.swift                   # OS simulation harness, mock injectors, and telemetry
        ├── Tier1_FeatureCoverageTests.swift    # 95 tests: Isolated coverage for F1 through F19 (>=5 per feature)
        ├── Tier2_BoundaryTests.swift           # 40 tests: Extreme values, zero displays, missing files, thermal panic
        ├── Tier3_PairwiseTests.swift           # 50 tests: Combinatorial cross-feature interactions
        └── Tier4_RealWorldTests.swift          # 35 tests: Complex real-world operational user workloads
```

### Component Responsibilities:

- **`TestHarness.swift`**:
  - Provides mock display generation, coordinate space mapping, and screen parameter change dispatching.
  - Simulates IOKit power sources (`AC`, `Battery`, `UPS`), Low Power Mode toggles, and thermal state transitions.
  - Simulates `NSWorkspace` sleep/wake and Darwin screen lock/unlock notifications without modifying user session.
  - Tracks process memory footprint (`mach_task_basic_info`) and CPU metrics.
  - Verifies window levels, collection behaviors, and mouse event configurations against CoreGraphics specifications.

- **`Tier1_FeatureCoverageTests.swift`**:
  - Verifies each feature $F_1 \dots F_{19}$ independently in a clean, isolated environment.
  - Exactly $\ge 5$ test cases per feature (95 tests total).

- **`Tier2_BoundaryTests.swift`**:
  - Tests boundary conditions, edge cases, and unexpected environmental states:
    - Zero displays, 1 display, 8+ displays.
    - Battery level at 0%, 1%, 100%, missing battery on desktop Macs.
    - Video stall watchdog at $t = 2.99\text{s}$ vs $t = 3.01\text{s}$.
    - Non-existent video files, unreadable files, corrupt container headers.
    - Rapid back-to-back screen reconfigurations within 10ms.
    - Thermal pressure escalation (`.serious` vs `.critical`).

- **`Tier3_PairwiseTests.swift`**:
  - Tests pairwise combinatorial interactions between distinct subsystems:
    - Display disconnect during active video crossfade.
    - Low Power Mode activation while running on AC power.
    - Display sleep occurring simultaneously with screen lock.
    - Menu bar user pause while display is occluded.
    - Resolution resize while system is asleep.
    - Thermal throttling active while on battery power.

- **`Tier4_RealWorldTests.swift`**:
  - Tests end-to-end holistic user workflows:
    - Full application launch to steady-state playback.
    - Multi-monitor docking: MacBook built-in screen + external 4K monitor connect -> disconnect -> reconnect.
    - Day/Night power cycle: AC power -> Unplug to Battery -> Low Power Mode -> Screen Lock -> Display Sleep -> Wake -> Plug into AC.
    - Simulated 10,000-loop playback endurance with zero memory accumulation.
    - Clean shutdown sequence releasing all window and player handles.

---

## 4. Minimum Threshold Verification

To guarantee rigorous mathematical coverage, the suite enforces the threshold formula:

$$\text{Minimum Test Count} = 11 \times N + \max\left(5, \left\lfloor\frac{N}{2}\right\rfloor\right)$$

For $N = 19$ features:
- $11 \times 19 = 209$
- $\max(5, \lfloor 19 / 2 \rfloor) = \max(5, 9) = 9$
- **Target Minimum Threshold**: $209 + 9 = \mathbf{218}$ tests.

### Test Count Breakdown across Tiers:

| Test Tier | Test File | Test Method Count | Features Covered |
|:---|:---|:---:|:---|
| **Tier 1** | `Tier1_FeatureCoverageTests.swift` | **95** | F1 – F19 (5 tests each) |
| **Tier 2** | `Tier2_BoundaryTests.swift` | **40** | Boundary values, extremes, errors |
| **Tier 3** | `Tier3_PairwiseTests.swift` | **50** | Subsystem combinatorial pairs |
| **Tier 4** | `Tier4_RealWorldTests.swift` | **35** | Holistic lifecycle & endurance |
| **Total** | **All Tiers** | **220** | **Exceeds threshold of 218 ($\ge 218$)** |

---

## 5. How to Run the Tests

The entire suite is fully automated and runs via the standard Swift Package Manager test runner on macOS:

```bash
# Run all E2E Tests:
swift test --filter E2ETests

# Run a specific Tier:
swift test --filter Tier1_FeatureCoverageTests
swift test --filter Tier2_BoundaryTests
swift test --filter Tier3_PairwiseTests
swift test --filter Tier4_RealWorldTests

# Run with verbose output:
swift test --filter E2ETests -v
```

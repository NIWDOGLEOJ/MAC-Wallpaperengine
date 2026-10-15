# Original User Request

## Initial Request — 2026-10-15T08:47:45Z

Build an open-source, high-performance native macOS desktop live wallpaper engine core (alternative to Walyro) that renders hardware-accelerated video behind desktop icons across all connected displays with power and space awareness.

Working directory: /Users/godjoel/.gemini/antigravity/scratch/wallpaper_engine_core
Integrity mode: development

## Requirements

### R1. Desktop Window & Space Hierarchy Management
Create a native macOS desktop window controller that manages borderless, non-activating windows attached strictly beneath desktop icons across all active screens. The windows must remain anchored behind user desktop files, persist across macOS Spaces and Mission Control transitions without participating in the window cycle (Cmd+Tab), and dynamically adapt to display connection, disconnection, and resolution changes.

### R2. Hardware-Accelerated Looping Video Engine
Provide a video playback pipeline that continuously loops video media (MP4/MOV) with seamless loop transitions (no black flashes or dropped frames). Support per-display wallpaper assignment and maintain smooth playback across multiple simultaneous screens with minimal CPU and memory overhead.

### R3. Intelligent Power & Display State Throttling
Incorporate background power and environment observers that monitor AC/battery power status, Low Power Mode, display sleep, screen lock, and active screen coverage. Playback must automatically pause or throttle when the display is occluded or running on constrained power, resuming seamlessly when conditions normalize.

### R4. Menu Bar Status & Quick Controller
Provide a lightweight menu bar status item allowing immediate control over the wallpaper engine: toggling playback (pause/resume), switching active video assets per display, and accessing configuration without requiring a persistent main app window.

## Verification Resources & Methods
- **Programmatic Build & Test Suite**: The project must compile cleanly with `swift build` or `xcodebuild` with zero warnings or errors.
- **Window Hierarchy Audit**: Automated tests or verification scripts must verify window levels against `CGWindowLevelForKey(.desktopWindow)` and ensure `ignoresMouseEvents` is active.
- **Loop Continuity & Resource Test**: Verification scripts validating that video playback operates without hitching and that CPU utilization remains within efficient limits (< 5% on Apple Silicon).

## Acceptance Criteria

### Desktop Integration & Behavior
- [ ] Desktop windows are created at desktop level (`kCGDesktopWindowLevelKey`), allowing user desktop icons and clicks to function without interference.
- [ ] Desktop windows include `.canJoinAllSpaces`, `.stationary`, and `.ignoresCycle` collection behaviors.
- [ ] Connecting or disconnecting external monitors triggers layout reconciliation without process crashes or orphaned windows.

### Media Playback & Efficiency
- [ ] Seamless looping video playback executes without black frames, audio leaks, or memory accumulation over time.
- [ ] Independent video streams can be assigned to different connected displays simultaneously.
- [ ] Video decoding utilizes hardware acceleration via AVFoundation / CoreVideo.

### System & Power Management
- [ ] Playback pauses immediately upon display sleep or system lock, and resumes on display wake.
- [ ] Throttling or pausing is invoked when Low Power Mode is activated or on battery according to preferences.

### Usability & Control
- [ ] A functional macOS Menu Bar item enables one-click pause/play, display selection, and graceful quit.
- [ ] All code resides self-contained in `/Users/godjoel/.gemini/antigravity/scratch/wallpaper_engine_core`.

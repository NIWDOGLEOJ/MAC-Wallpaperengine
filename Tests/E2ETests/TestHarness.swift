//
//  TestHarness.swift
//  WallpaperEngineCoreTests / E2ETests
//
//  Created for Wallpaper Engine Core Opaque-Box E2E Testing Track.
//

import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import IOKit.ps
import Darwin
import Foundation

// MARK: - 1. Core Domain Types & Protocols (Mirroring PROJECT.md & Surveys)

public typealias DisplayID = CGDirectDisplayID

public struct ScreenDescriptor: Identifiable, Equatable, Hashable, Sendable {
    public var id: DisplayID { displayID }
    public let displayID: DisplayID
    public let name: String
    public let frame: CGRect
    public let scaleFactor: CGFloat
    public let isMain: Bool
    public let isBuiltin: Bool

    public init(
        displayID: DisplayID,
        name: String,
        frame: CGRect,
        scaleFactor: CGFloat = 2.0,
        isMain: Bool = false,
        isBuiltin: Bool = false
    ) {
        self.displayID = displayID
        self.name = name
        self.frame = frame
        self.scaleFactor = scaleFactor
        self.isMain = isMain
        self.isBuiltin = isBuiltin
    }
}

public protocol DesktopWindowProtocol: AnyObject {
    var displayID: DisplayID { get }
    var underlyingWindow: NSWindow? { get }
    var contentLayer: CALayer? { get set }
    var isVisible: Bool { get }
    var frame: CGRect { get }
    var windowLevel: Int { get }
    var collectionBehaviorFlags: NSWindow.CollectionBehavior { get }
    var ignoresMouseEventsFlag: Bool { get }
    var canBecomeKeyWindow: Bool { get }
    var canBecomeMainWindow: Bool { get }

    func updateFrame(_ newFrame: CGRect)
    func orderToDesktopLevel()
    func closeAndRelease()
}

public protocol ScreenManagerDelegate: AnyObject {
    func screenManagerDidDetectChanges(screens: [ScreenDescriptor])
}

public protocol ScreenManagerProtocol: AnyObject {
    var activeScreens: [ScreenDescriptor] { get }
    var delegate: ScreenManagerDelegate? { get set }
    var displaysHaveSeparateSpaces: Bool { get }
    func startMonitoring()
    func stopMonitoring()
}

public struct VideoAsset: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    public let fileURL: URL
    public let title: String
    public let duration: CMTime
    public let naturalSize: CGSize
    public let codec: String
    public let bookmarkData: Data?

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        title: String,
        duration: CMTime = CMTime(seconds: 10, preferredTimescale: 600),
        naturalSize: CGSize = CGSize(width: 1920, height: 1080),
        codec: String = "avc1",
        bookmarkData: Data? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.title = title
        self.duration = duration
        self.naturalSize = naturalSize
        self.codec = codec
        self.bookmarkData = bookmarkData
    }
}

public enum PauseReason: String, Codable, Hashable, Sendable {
    case userRequested = "User Paused"
    case systemSleeping = "System Sleeping"
    case screensSleeping = "Display Sleeping"
    case screenLocked = "Screen Locked"
    case screensaverActive = "Screensaver Active"
    case sessionInactive = "Session Inactive (Fast User Switching)"
    case lowPowerMode = "Low Power Mode Enabled"
    case onBattery = "Running on Battery Power"
    case displayOccluded = "Display Fully Occluded"
    case thermalPressure = "Thermal Pressure Protection"
}

public enum ThrottleReason: String, Codable, Hashable, Sendable {
    case onBattery = "Battery Power Throttling"
    case thermalPressure = "Elevated Thermal State"
}

public enum PlaybackState: Sendable, Equatable {
    case idle
    case loading(URL)
    case playing
    case paused(reason: PauseReason)
    case throttled(fps: Int)
    case stalled(reason: String)
    case failed(VideoEngineError)
}

public enum VideoEngineError: Error, LocalizedError, Sendable, Equatable {
    case fileNotFound(URL)
    case assetNotPlayable(URL)
    case noVideoTrack(URL)
    case unreadableFormat(String)
    case looperCreationFailed(String)
    case playbackStalled
    case displayNotFound(DisplayID)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url): return "Video file not found at: \(url.path)"
        case .assetNotPlayable(let url): return "Asset is not playable: \(url.path)"
        case .noVideoTrack(let url): return "No video track found in: \(url.path)"
        case .unreadableFormat(let msg): return "Unreadable format: \(msg)"
        case .looperCreationFailed(let msg): return "AVPlayerLooper creation failed: \(msg)"
        case .playbackStalled: return "Playback stalled and failed recovery"
        case .displayNotFound(let id): return "Display not found for ID: \(id)"
        }
    }
}

public struct VideoEngineConfiguration: Sendable, Equatable {
    public var videoGravity: AVLayerVideoGravity
    public var crossfadeDuration: TimeInterval
    public var stallTimeoutThreshold: TimeInterval
    public var maxStallRecoveryAttempts: Int
    public var enableHardwareAcceleration: Bool

    public static let `default` = VideoEngineConfiguration(
        videoGravity: .resizeAspectFill,
        crossfadeDuration: 0.35,
        stallTimeoutThreshold: 3.0,
        maxStallRecoveryAttempts: 3,
        enableHardwareAcceleration: true
    )
}

public protocol DisplayVideoPlayerProtocol: AnyObject {
    var displayID: DisplayID { get }
    var state: PlaybackState { get }
    var currentAsset: VideoAsset? { get }
    var isMuted: Bool { get }
    var volume: Float { get }
    var audioTracksEnabled: Bool { get }
    var stallRecoveryCount: Int { get }

    func load(asset: VideoAsset, crossfade: Bool) async throws
    func play()
    func pause(reason: PauseReason)
    func triggerStall()
    func tearDown()
}

public protocol VideoEngineProtocol: AnyObject {
    var configuration: VideoEngineConfiguration { get set }
    var isPaused: Bool { get }
    var activeDisplays: [DisplayID] { get }
    func playAll()
    func pauseAll(reason: PauseReason)
    func assign(asset: VideoAsset, to displayID: DisplayID) async throws
    func assignToAll(asset: VideoAsset) async throws
    func player(for displayID: DisplayID) -> DisplayVideoPlayerProtocol?
    func detach(displayID: DisplayID)
}

public enum PowerSource: String, Codable, Sendable {
    case ac = "AC Power"
    case battery = "Battery Power"
    case ups = "UPS Power"
    case unknown = "Unknown"
}

public struct PowerState: Equatable, Sendable {
    public var source: PowerSource
    public var batteryLevel: Double? // 0.0 ... 1.0
    public var isCharging: Bool
    public var isLowPowerModeEnabled: Bool
    public var thermalState: ProcessInfo.ThermalState

    public var isOnBattery: Bool {
        source == .battery
    }

    public init(
        source: PowerSource = .ac,
        batteryLevel: Double? = 1.0,
        isCharging: Bool = true,
        isLowPowerModeEnabled: Bool = false,
        thermalState: ProcessInfo.ThermalState = .nominal
    ) {
        self.source = source
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.thermalState = thermalState
    }
}

public protocol PowerObserverDelegate: AnyObject {
    func powerStateDidChange(_ newState: PowerState)
}

public protocol PowerObserverProtocol: AnyObject {
    var currentState: PowerState { get }
    var delegate: PowerObserverDelegate? { get set }
    func start()
    func stop()
}

public struct SleepLockState: Equatable, Sendable {
    public var isSystemSleeping: Bool = false
    public var areScreensSleeping: Bool = false
    public var isScreenLocked: Bool = false
    public var isScreensaverActive: Bool = false
    public var isSessionActive: Bool = true

    public init(
        isSystemSleeping: Bool = false,
        areScreensSleeping: Bool = false,
        isScreenLocked: Bool = false,
        isScreensaverActive: Bool = false,
        isSessionActive: Bool = true
    ) {
        self.isSystemSleeping = isSystemSleeping
        self.areScreensSleeping = areScreensSleeping
        self.isScreenLocked = isScreenLocked
        self.isScreensaverActive = isScreensaverActive
        self.isSessionActive = isSessionActive
    }
}

public protocol SleepLockObserverDelegate: AnyObject {
    func sleepLockStateDidChange(_ newState: SleepLockState)
}

public protocol SleepLockObserverProtocol: AnyObject {
    var currentState: SleepLockState { get }
    var delegate: SleepLockObserverDelegate? { get set }
    func start()
    func stop()
}

public protocol OcclusionManagerDelegate: AnyObject {
    func occlusionDidChange(for displayID: DisplayID, isVisible: Bool)
}

public protocol OcclusionManagerProtocol: AnyObject {
    var delegate: OcclusionManagerDelegate? { get set }
    func registerDisplay(_ displayID: DisplayID, isVisible: Bool)
    func setDisplayVisibility(_ displayID: DisplayID, isVisible: Bool)
    func unregisterDisplay(_ displayID: DisplayID)
    func isDisplayVisible(_ displayID: DisplayID) -> Bool
}

public enum PlaybackDecision: Equatable, Sendable {
    case play(fps: Int)
    case pause(reasons: Set<PauseReason>)
    case throttle(fps: Int, reasons: Set<ThrottleReason>)
}

public struct EngineConfig: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var isPaused: Bool = false
    public var targetFrameRate: Int = 60
    public var throttledFrameRate: Int = 30

    // Throttling Toggles
    public var pauseOnBattery: Bool = false
    public var throttleOnBattery: Bool = true
    public var pauseOnLowPowerMode: Bool = true
    public var pauseOnScreenLock: Bool = true
    public var pauseOnDisplaySleep: Bool = true
    public var pauseWhenOccluded: Bool = true

    // Global Media Settings
    public var isMuted: Bool = true
    public var hardwareDecodingEnabled: Bool = true
    public var defaultAssetPath: String? = nil

    // Per-display configurations (Key: DisplayID string)
    public var displayConfigurations: [String: DisplayConfig] = [:]

    public struct DisplayConfig: Codable, Equatable, Sendable {
        public var assetPath: String?
        public var scalingMode: ScalingMode = .aspectFill
        public var isEnabled: Bool = true
        public var isMuted: Bool = true

        public enum ScalingMode: String, Codable, Sendable {
            case aspectFill
            case aspectFit
            case resize
        }

        public init(
            assetPath: String? = nil,
            scalingMode: ScalingMode = .aspectFill,
            isEnabled: Bool = true,
            isMuted: Bool = true
        ) {
            self.assetPath = assetPath
            self.scalingMode = scalingMode
            self.isEnabled = isEnabled
            self.isMuted = isMuted
        }
    }

    public init(
        version: Int = 1,
        isPaused: Bool = false,
        targetFrameRate: Int = 60,
        throttledFrameRate: Int = 30,
        pauseOnBattery: Bool = false,
        throttleOnBattery: Bool = true,
        pauseOnLowPowerMode: Bool = true,
        pauseOnScreenLock: Bool = true,
        pauseOnDisplaySleep: Bool = true,
        pauseWhenOccluded: Bool = true,
        isMuted: Bool = true,
        hardwareDecodingEnabled: Bool = true,
        defaultAssetPath: String? = nil,
        displayConfigurations: [String: DisplayConfig] = [:]
    ) {
        self.version = version
        self.isPaused = isPaused
        self.targetFrameRate = targetFrameRate
        self.throttledFrameRate = throttledFrameRate
        self.pauseOnBattery = pauseOnBattery
        self.throttleOnBattery = throttleOnBattery
        self.pauseOnLowPowerMode = pauseOnLowPowerMode
        self.pauseOnScreenLock = pauseOnScreenLock
        self.pauseOnDisplaySleep = pauseOnDisplaySleep
        self.pauseWhenOccluded = pauseWhenOccluded
        self.isMuted = isMuted
        self.hardwareDecodingEnabled = hardwareDecodingEnabled
        self.defaultAssetPath = defaultAssetPath
        self.displayConfigurations = displayConfigurations
    }
}

public struct StateEvaluator {
    public static func evaluate(
        manualPause: Bool,
        sleepLock: SleepLockState,
        power: PowerState,
        isDisplayVisible: Bool,
        config: EngineConfig
    ) -> PlaybackDecision {
        var pauseReasons = Set<PauseReason>()

        // 1. Manual user override
        if manualPause { pauseReasons.insert(.userRequested) }

        // 2. Sleep & Screen states
        if sleepLock.isSystemSleeping && config.pauseOnDisplaySleep { pauseReasons.insert(.systemSleeping) }
        if sleepLock.areScreensSleeping && config.pauseOnDisplaySleep { pauseReasons.insert(.screensSleeping) }
        if sleepLock.isScreenLocked && config.pauseOnScreenLock { pauseReasons.insert(.screenLocked) }
        if sleepLock.isScreensaverActive { pauseReasons.insert(.screensaverActive) }
        if !sleepLock.isSessionActive { pauseReasons.insert(.sessionInactive) }

        // 3. Power states
        if power.isLowPowerModeEnabled && config.pauseOnLowPowerMode { pauseReasons.insert(.lowPowerMode) }
        if power.isOnBattery && config.pauseOnBattery { pauseReasons.insert(.onBattery) }
        if power.thermalState == .critical { pauseReasons.insert(.thermalPressure) }

        // 4. Occlusion
        if !isDisplayVisible && config.pauseWhenOccluded { pauseReasons.insert(.displayOccluded) }

        // Check if pause required
        if !pauseReasons.isEmpty {
            return .pause(reasons: pauseReasons)
        }

        // 5. Throttling checks
        var throttleReasons = Set<ThrottleReason>()
        if power.isOnBattery && config.throttleOnBattery {
            throttleReasons.insert(.onBattery)
        }
        if power.thermalState == .serious {
            throttleReasons.insert(.thermalPressure)
        }

        if !throttleReasons.isEmpty {
            return .throttle(fps: config.throttledFrameRate, reasons: throttleReasons)
        }

        return .play(fps: config.targetFrameRate)
    }
}

public protocol MenuBarActionDelegate: AnyObject {
    func menuBarDidTogglePlayback()
    func menuBarDidSelectAsset(_ url: URL, for displayID: DisplayID)
    func menuBarDidToggleSetting(_ keyPath: WritableKeyPath<EngineConfig, Bool>)
    func menuBarDidRequestQuit()
}

public protocol MenuBarControllerProtocol: AnyObject {
    var delegate: MenuBarActionDelegate? { get set }
    var isStatusItemVisible: Bool { get }
    var currentTitle: String { get }
    var isMenuPresented: Bool { get }

    func setup()
    func updateStatus(isPlaying: Bool, fps: Int, powerInfo: String)
    func updateDisplays(displays: [(id: DisplayID, name: String, currentAsset: String?)])
    func updateConfig(_ config: EngineConfig)
}

public struct CommandLineOptions: Equatable, Sendable {
    public var videoPath: String?
    public var targetDisplayID: DisplayID?
    public var pauseOnBattery: Bool
    public var targetFPS: Int?
    public var isHeadless: Bool
    public var configPath: String?
    public var dumpConfig: Bool
    public var isBenchmark: Bool

    public init(
        videoPath: String? = nil,
        targetDisplayID: DisplayID? = nil,
        pauseOnBattery: Bool = false,
        targetFPS: Int? = nil,
        isHeadless: Bool = false,
        configPath: String? = nil,
        dumpConfig: Bool = false,
        isBenchmark: Bool = false
    ) {
        self.videoPath = videoPath
        self.targetDisplayID = targetDisplayID
        self.pauseOnBattery = pauseOnBattery
        self.targetFPS = targetFPS
        self.isHeadless = isHeadless
        self.configPath = configPath
        self.dumpConfig = dumpConfig
        self.isBenchmark = isBenchmark
    }

    public static func parse(arguments: [String]) -> CommandLineOptions {
        var opts = CommandLineOptions()
        var iterator = arguments.makeIterator()
        _ = iterator.next() // Skip executable name

        while let arg = iterator.next() {
            switch arg {
            case "--video":
                opts.videoPath = iterator.next()
            case "--display":
                if let str = iterator.next(), let id = DisplayID(str) {
                    opts.targetDisplayID = id
                }
            case "--pause-on-battery":
                opts.pauseOnBattery = true
            case "--fps":
                if let str = iterator.next(), let fps = Int(str) {
                    opts.targetFPS = fps
                }
            case "--headless":
                opts.isHeadless = true
            case "--config":
                opts.configPath = iterator.next()
            case "--dump-config":
                opts.dumpConfig = true
            case "--benchmark":
                opts.isBenchmark = true
            default:
                break
            }
        }
        return opts
    }
}

// MARK: - 2. Mock Subsystem Implementations for Isolated & Integrated Testing

public final class MockDesktopWindow: DesktopWindowProtocol {
    public let displayID: DisplayID
    public var underlyingWindow: NSWindow?
    public var contentLayer: CALayer?
    public var isVisible: Bool = false
    public var frame: CGRect
    public var windowLevel: Int
    public var collectionBehaviorFlags: NSWindow.CollectionBehavior
    public var ignoresMouseEventsFlag: Bool
    public var canBecomeKeyWindow: Bool
    public var canBecomeMainWindow: Bool

    public private(set) var updateFrameCallCount: Int = 0
    public private(set) var orderToDesktopLevelCallCount: Int = 0
    public private(set) var closeAndReleaseCallCount: Int = 0

    public init(
        screen: ScreenDescriptor,
        level: Int = Int(CGWindowLevelForKey(.desktopWindow)),
        collectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary],
        ignoresMouseEvents: Bool = true,
        canBecomeKey: Bool = false,
        canBecomeMain: Bool = false
    ) {
        self.displayID = screen.displayID
        self.frame = screen.frame
        self.windowLevel = level
        self.collectionBehaviorFlags = collectionBehavior
        self.ignoresMouseEventsFlag = ignoresMouseEvents
        self.canBecomeKeyWindow = canBecomeKey
        self.canBecomeMainWindow = canBecomeMain
    }

    public func updateFrame(_ newFrame: CGRect) {
        updateFrameCallCount += 1
        self.frame = newFrame
    }

    public func orderToDesktopLevel() {
        orderToDesktopLevelCallCount += 1
        self.isVisible = true
    }

    public func closeAndRelease() {
        closeAndReleaseCallCount += 1
        self.isVisible = false
        self.contentLayer = nil
    }
}

public final class MockScreenManager: ScreenManagerProtocol {
    public var activeScreens: [ScreenDescriptor] = []
    public weak var delegate: ScreenManagerDelegate?
    public var displaysHaveSeparateSpaces: Bool = true
    public var isMonitoring: Bool = false

    public init(screens: [ScreenDescriptor] = []) {
        self.activeScreens = screens
    }

    public func startMonitoring() {
        isMonitoring = true
    }

    public func stopMonitoring() {
        isMonitoring = false
    }

    public func simulateScreenChange(screens: [ScreenDescriptor]) {
        self.activeScreens = screens
        delegate?.screenManagerDidDetectChanges(screens: screens)
    }
}

public final class MockDisplayVideoPlayer: DisplayVideoPlayerProtocol {
    public let displayID: DisplayID
    public private(set) var state: PlaybackState = .idle
    public private(set) var currentAsset: VideoAsset?
    public var isMuted: Bool = true
    public var volume: Float = 0.0
    public var audioTracksEnabled: Bool = false
    public private(set) var stallRecoveryCount: Int = 0
    public private(set) var loadCallCount: Int = 0
    public private(set) var playCallCount: Int = 0
    public private(set) var pauseCallCount: Int = 0
    public private(set) var tearDownCallCount: Int = 0

    public init(displayID: DisplayID) {
        self.displayID = displayID
    }

    public func load(asset: VideoAsset, crossfade: Bool) async throws {
        loadCallCount += 1
        currentAsset = asset
        state = .playing
    }

    public func play() {
        playCallCount += 1
        state = .playing
    }

    public func pause(reason: PauseReason) {
        pauseCallCount += 1
        state = .paused(reason: reason)
    }

    public func triggerStall() {
        stallRecoveryCount += 1
        if stallRecoveryCount < 3 {
            state = .stalled(reason: "Buffering")
            // Soft recovery
            play()
        } else {
            state = .failed(.playbackStalled)
        }
    }

    public func tearDown() {
        tearDownCallCount += 1
        state = .idle
        currentAsset = nil
    }
}

public final class MockVideoEngine: VideoEngineProtocol {
    public var configuration: VideoEngineConfiguration = .default
    public var isPaused: Bool = false
    public var players: [DisplayID: MockDisplayVideoPlayer] = [:]

    public var activeDisplays: [DisplayID] {
        Array(players.keys)
    }

    public init() {}

    public func registerDisplay(displayID: DisplayID) -> MockDisplayVideoPlayer {
        let player = MockDisplayVideoPlayer(displayID: displayID)
        players[displayID] = player
        return player
    }

    public func playAll() {
        isPaused = false
        for player in players.values {
            player.play()
        }
    }

    public func pauseAll(reason: PauseReason) {
        isPaused = true
        for player in players.values {
            player.pause(reason: reason)
        }
    }

    public func assign(asset: VideoAsset, to displayID: DisplayID) async throws {
        guard let p = players[displayID] else {
            throw VideoEngineError.displayNotFound(displayID)
        }
        try await p.load(asset: asset, crossfade: true)
    }

    public func assignToAll(asset: VideoAsset) async throws {
        for player in players.values {
            try await player.load(asset: asset, crossfade: true)
        }
    }

    public func player(for displayID: DisplayID) -> DisplayVideoPlayerProtocol? {
        players[displayID]
    }

    public func detach(displayID: DisplayID) {
        if let player = players.removeValue(forKey: displayID) {
            player.tearDown()
        }
    }
}

public final class MockPowerObserver: PowerObserverProtocol {
    public var currentState: PowerState
    public weak var delegate: PowerObserverDelegate?
    public var isObserving: Bool = false

    public init(initialState: PowerState = PowerState()) {
        self.currentState = initialState
    }

    public func start() {
        isObserving = true
    }

    public func stop() {
        isObserving = false
    }

    public func updateState(_ newState: PowerState) {
        self.currentState = newState
        delegate?.powerStateDidChange(newState)
    }
}

public final class MockSleepLockObserver: SleepLockObserverProtocol {
    public var currentState: SleepLockState
    public weak var delegate: SleepLockObserverDelegate?
    public var isObserving: Bool = false

    public init(initialState: SleepLockState = SleepLockState()) {
        self.currentState = initialState
    }

    public func start() {
        isObserving = true
    }

    public func stop() {
        isObserving = false
    }

    public func updateState(_ newState: SleepLockState) {
        self.currentState = newState
        delegate?.sleepLockStateDidChange(newState)
    }
}

public final class MockOcclusionManager: OcclusionManagerProtocol {
    public weak var delegate: OcclusionManagerDelegate?
    private var visibilities: [DisplayID: Bool] = [:]

    public init() {}

    public func registerDisplay(_ displayID: DisplayID, isVisible: Bool = true) {
        visibilities[displayID] = isVisible
    }

    public func setDisplayVisibility(_ displayID: DisplayID, isVisible: Bool) {
        visibilities[displayID] = isVisible
        delegate?.occlusionDidChange(for: displayID, isVisible: isVisible)
    }

    public func unregisterDisplay(_ displayID: DisplayID) {
        visibilities.removeValue(forKey: displayID)
    }

    public func isDisplayVisible(_ displayID: DisplayID) -> Bool {
        visibilities[displayID] ?? true
    }
}

public final class MockMenuBarController: MenuBarControllerProtocol {
    public weak var delegate: MenuBarActionDelegate?
    public private(set) var isStatusItemVisible: Bool = false
    public private(set) var currentTitle: String = ""
    public private(set) var isMenuPresented: Bool = false
    public private(set) var lastStatus: (isPlaying: Bool, fps: Int, powerInfo: String)?
    public private(set) var displayList: [(id: DisplayID, name: String, currentAsset: String?)] = []
    public private(set) var currentConfig: EngineConfig = EngineConfig()

    public init() {}

    public func setup() {
        isStatusItemVisible = true
        currentTitle = "Wallpaper Engine"
    }

    public func updateStatus(isPlaying: Bool, fps: Int, powerInfo: String) {
        lastStatus = (isPlaying, fps, powerInfo)
    }

    public func updateDisplays(displays: [(id: DisplayID, name: String, currentAsset: String?)]) {
        self.displayList = displays
    }

    public func updateConfig(_ config: EngineConfig) {
        self.currentConfig = config
    }

    public func simulateUserTogglePlayback() {
        delegate?.menuBarDidTogglePlayback()
    }

    public func simulateUserSelectAsset(_ url: URL, for displayID: DisplayID) {
        delegate?.menuBarDidSelectAsset(url, for: displayID)
    }

    public func simulateUserToggleSetting(_ keyPath: WritableKeyPath<EngineConfig, Bool>) {
        delegate?.menuBarDidToggleSetting(keyPath)
    }

    public func simulateUserQuit() {
        delegate?.menuBarDidRequestQuit()
    }
}

// MARK: - 3. OS System Inspection & Telemetry Harness

public struct SystemTelemetry {
    public let residentMemoryBytes: UInt64
    public let virtualMemoryBytes: UInt64
    public let userCPUTimeSeconds: Double
    public let systemCPUTimeSeconds: Double

    public var residentMemoryMB: Double {
        Double(residentMemoryBytes) / (1024.0 * 1024.0)
    }
}

public final class TestHarness {
    public static let shared = TestHarness()

    private init() {}

    // MARK: - Memory & CPU Telemetry

    public func captureTelemetry() -> SystemTelemetry {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        var threadTimes = tms()
        times(&threadTimes)

        let resident = (kerr == KERN_SUCCESS) ? UInt64(info.resident_size) : 0
        let virtual = (kerr == KERN_SUCCESS) ? UInt64(info.virtual_size) : 0
        let userTime = Double(threadTimes.tms_utime) / Double(sysconf(_SC_CLK_TCK))
        let sysTime = Double(threadTimes.tms_stime) / Double(sysconf(_SC_CLK_TCK))

        return SystemTelemetry(
            residentMemoryBytes: resident,
            virtualMemoryBytes: virtual,
            userCPUTimeSeconds: userTime,
            systemCPUTimeSeconds: sysTime
        )
    }

    // MARK: - Window Level Verification

    public func expectedDesktopWindowLevel() -> Int {
        Int(CGWindowLevelForKey(.desktopWindow))
    }

    public func expectedDesktopIconWindowLevel() -> Int {
        Int(CGWindowLevelForKey(.desktopIconWindow))
    }

    public func expectedBaseWindowLevel() -> Int {
        Int(CGWindowLevelForKey(.baseWindow))
    }

    // MARK: - Temporary File & Video Fixture Helpers

    public func createTemporaryDirectory() throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("WallpaperEngineTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        return tempURL
    }

    public func createDummyVideoFile(in directory: URL, name: String = "test_loop.mp4", byteCount: Int = 1024) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        let dummyData = Data(repeating: 0x41, count: byteCount)
        try dummyData.write(to: fileURL)
        return fileURL
    }

    // MARK: - CGWindowList Inspection

    public func queryOnScreenWindowCount() -> Int {
        guard let windowListInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return 0
        }
        return windowListInfo.count
    }

    public func inspectWindowLevels() -> [Int] {
        guard let windowListInfo = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return windowListInfo.compactMap { $0[kCGWindowLayer as String] as? Int }
    }
}

//
//  PowerObserver.swift
//  WallpaperEngineCore
//
//  IOKit power source, battery capacity, Low Power Mode, and thermal state observer.
//

import Foundation
import IOKit.ps
import OSLog

// MARK: - Power Models

/// The electrical power source currently supplying current to the Mac.
public enum PowerSource: String, Codable, Sendable {
    case ac = "AC Power"
    case battery = "Battery Power"
    case ups = "UPS Power"
    case unknown = "Unknown"
}

/// An immutable snapshot of the system power, battery, and thermal conditions.
public struct PowerState: Equatable, Sendable {
    /// Active electrical power source.
    public var source: PowerSource
    
    /// Battery charge level normalized in the range 0.0 ... 1.0 (nil on desktop Macs without battery).
    public var batteryLevel: Double?
    
    /// Indicates whether the internal battery is currently charging from an external power supply.
    public var isCharging: Bool
    
    /// Indicates whether macOS Low Power Mode is currently enabled.
    public var isLowPowerModeEnabled: Bool
    
    /// Hardware thermal state reflecting temperature pressure and thermal throttling.
    public var thermalState: ProcessInfo.ThermalState

    /// Convenience helper indicating if running on battery power.
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

// MARK: - Power Observer Protocols

/// Delegate interface notifying downstream coordinators of changes in system power or thermal conditions.
@MainActor
public protocol PowerObserverDelegate: AnyObject {
    /// Invoked whenever power source, battery level, Low Power Mode, or thermal state changes.
    func powerStateDidChange(_ newState: PowerState)
}

/// Interface contract for power and thermal observation.
@MainActor
public protocol PowerObserverProtocol: AnyObject {
    /// Latest verified power state.
    var currentState: PowerState { get }
    
    /// Delegate receiving updates.
    var delegate: PowerObserverDelegate? { get set }
    
    /// Indicates whether monitoring is currently active.
    var isObserving: Bool { get }
    
    /// Begins observing power source, Low Power Mode, and thermal notifications.
    func start()
    
    /// Stops observing notifications and releases underlying run loop resources.
    func stop()
}

// MARK: - Dependency Injection: Power Source Provider

/// Delegate interface through which low-level power source providers signal raw hardware changes.
@MainActor
public protocol PowerSourceProviderDelegate: AnyObject {
    /// Signals that power source or thermal state has changed on the host system.
    func powerSourceProviderDidDetectChange(_ provider: PowerSourceProviderProtocol)
}

/// Low-level abstraction decoupling hardware IOKit and ProcessInfo queries for deterministic testing.
@MainActor
public protocol PowerSourceProviderProtocol: AnyObject {
    var delegate: PowerSourceProviderDelegate? { get set }
    func startMonitoring()
    func stopMonitoring()
    func fetchCurrentPowerState() -> PowerState
}

// MARK: - Production IOKit Hardware Provider

/// Production implementation interfacing directly with IOKit (`IOPowerSources.h`) and `ProcessInfo`.
@MainActor
public final class IOKitPowerSourceProvider: PowerSourceProviderProtocol {
    public weak var delegate: PowerSourceProviderDelegate?

    private var runLoopSource: CFRunLoopSource?
    private var lpmObserverToken: NSObjectProtocol?
    private var thermalObserverToken: NSObjectProtocol?
    private var isMonitoring: Bool = false
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "PowerProvider")

    public init() {}

    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // 1. Register IOKit RunLoop Source on Main Run Loop (.commonModes)
        registerIOKitRunLoopSource()

        // 2. Register Low Power Mode notification (NSProcessInfoPowerStateDidChange)
        // Dispatched on global queue; routed to @MainActor
        lpmObserverToken = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isMonitoring else { return }
                self.logger.debug("Received NSProcessInfoPowerStateDidChange notification")
                self.delegate?.powerSourceProviderDidDetectChange(self)
            }
        }

        // 3. Register Thermal State notification (ProcessInfo.thermalStateDidChangeNotification)
        thermalObserverToken = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isMonitoring else { return }
                self.logger.debug("Received thermalStateDidChangeNotification")
                self.delegate?.powerSourceProviderDidDetectChange(self)
            }
        }
    }

    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
            runLoopSource = nil
        }

        if let token = lpmObserverToken {
            NotificationCenter.default.removeObserver(token)
            lpmObserverToken = nil
        }

        if let token = thermalObserverToken {
            NotificationCenter.default.removeObserver(token)
            thermalObserverToken = nil
        }
    }

    public func fetchCurrentPowerState() -> PowerState {
        let (source, batteryLevel, isCharging) = queryIOKitPower()
        let isLPM = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermal = ProcessInfo.processInfo.thermalState

        return PowerState(
            source: source,
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            isLowPowerModeEnabled: isLPM,
            thermalState: thermal
        )
    }

    private func registerIOKitRunLoopSource() {
        let callback: IOPowerSourceCallbackType = { context in
            guard let context = context else { return }
            Task { @MainActor in
                let provider = Unmanaged<IOKitPowerSourceProvider>.fromOpaque(context).takeUnretainedValue()
                guard provider.isMonitoring else { return }
                provider.logger.debug("IOKit power source callback fired")
                provider.delegate?.powerSourceProviderDidDetectChange(provider)
            }
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            self.runLoopSource = source
        } else {
            logger.error("Failed to allocate IOPSNotificationCreateRunLoopSource")
        }
    }

    private func queryIOKitPower() -> (source: PowerSource, batteryLevel: Double?, isCharging: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return (.ac, nil, false)
        }

        // Unretained read from snapshot blob
        let providerTypeStr = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String?
        let powerSource: PowerSource
        switch providerTypeStr {
        case kIOPMACPowerKey:
            powerSource = .ac
        case kIOPMBatteryPowerKey:
            powerSource = .battery
        case kIOPMUPSPowerKey:
            powerSource = .ups
        default:
            powerSource = .ac
        }

        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            // Desktop Mac: No internal battery installed
            return (powerSource, nil, false)
        }

        var isCharging = false
        var batteryLevel: Double? = nil

        for ps in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let isPresent = desc[kIOPSIsPresentKey] as? Bool ?? true
            guard isPresent else { continue }

            isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false

            let curCap = (desc[kIOPSCurrentCapacityKey] as? NSNumber)?.intValue
                ?? (desc[kIOPSCurrentCapacityKey] as? Int)
                ?? 0
            let maxCap = (desc[kIOPSMaxCapacityKey] as? NSNumber)?.intValue
                ?? (desc[kIOPSMaxCapacityKey] as? Int)
                ?? 100

            if maxCap > 0 {
                let ratio = Double(curCap) / Double(maxCap)
                batteryLevel = min(max(ratio, 0.0), 1.0)
            }
            break
        }

        return (powerSource, batteryLevel, isCharging)
    }

    isolated deinit {
        stopMonitoring()
    }
}

// MARK: - Mock Hardware Provider (for Unit Testing & CI)

/// Mock provider allowing deterministic injection of arbitrary power and thermal conditions.
@MainActor
public final class MockPowerSourceProvider: PowerSourceProviderProtocol {
    public weak var delegate: PowerSourceProviderDelegate?
    public var stateToReturn: PowerState
    public private(set) var isMonitoring: Bool = false
    public private(set) var fetchCount: Int = 0

    public init(initialState: PowerState = PowerState()) {
        self.stateToReturn = initialState
    }

    public func startMonitoring() {
        isMonitoring = true
    }

    public func stopMonitoring() {
        isMonitoring = false
    }

    public func fetchCurrentPowerState() -> PowerState {
        fetchCount += 1
        return stateToReturn
    }

    public func simulateChange(to newState: PowerState) {
        stateToReturn = newState
        delegate?.powerSourceProviderDidDetectChange(self)
    }
}

// MARK: - Concrete Power Observer Implementation

/// Coordinates hardware power monitoring, Low Power Mode, and thermal observation.
@MainActor
public final class PowerObserver: PowerObserverProtocol, PowerSourceProviderDelegate {
    public weak var delegate: PowerObserverDelegate?
    public private(set) var currentState: PowerState
    public private(set) var isObserving: Bool = false

    private let provider: PowerSourceProviderProtocol
    private let logger = Logger(subsystem: "com.wallpaperengine.core", category: "PowerObserver")

    /// Initializes PowerObserver with optional custom provider for dependency injection.
    public init(provider: PowerSourceProviderProtocol = IOKitPowerSourceProvider()) {
        self.provider = provider
        self.currentState = provider.fetchCurrentPowerState()
        self.provider.delegate = self
    }

    /// Starts monitoring power source, Low Power Mode, and thermal state changes.
    public func start() {
        guard !isObserving else { return }
        isObserving = true
        provider.startMonitoring()
        refreshState()
    }

    /// Stops monitoring and releases resources.
    public func stop() {
        guard isObserving else { return }
        isObserving = false
        provider.stopMonitoring()
    }

    public func powerSourceProviderDidDetectChange(_ provider: PowerSourceProviderProtocol) {
        guard isObserving else { return }
        refreshState()
    }

    private func refreshState() {
        let newState = provider.fetchCurrentPowerState()
        // Deduplicate: notify delegate only if state has materially changed
        if newState != currentState {
            let previous = currentState
            currentState = newState
            logger.info("Power state changed: \(previous.source.rawValue) -> \(newState.source.rawValue), LPM: \(newState.isLowPowerModeEnabled), Thermal: \(newState.thermalState.rawValue)")
            delegate?.powerStateDidChange(newState)
        }
    }

    isolated deinit {
        stop()
    }
}

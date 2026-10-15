//
//  PowerObserverTests.swift
//  WallpaperEngineCoreTests
//
//  Unit and integration test suite for F10 (IOKit Power Observer) and F11 (Low Power Mode Observer).
//

import Foundation
@testable import WallpaperEngineCore

@MainActor
public struct PowerObserverTests {
    
    // MARK: - Test Delegate Helper
    
    final class MockDelegate: PowerObserverDelegate {
        var states: [PowerState] = []
        func powerStateDidChange(_ newState: PowerState) {
            states.append(newState)
        }
    }
    
    public static func runAllTests() async {
        let runner = TestRunner.shared
        await runner.runSuite("PowerObserver & Low Power Mode (F10 & F11)") {
            runner.test("PO.1: Initial State Defaults to Provider Snapshot") {
                let mock = MockPowerSourceProvider(initialState: PowerState(source: .ac, batteryLevel: 1.0, isCharging: true))
                let observer = PowerObserver(provider: mock)
                
                try assertEqual(observer.currentState.source, .ac, "Must match provider source")
                try assertFalse(observer.currentState.isOnBattery, "Must not be on battery")
                try assertFalse(observer.isObserving, "Must not be observing before start")
            }
            
            runner.test("PO.2: Start and Stop Lifecycle Management") {
                let mock = MockPowerSourceProvider()
                let observer = PowerObserver(provider: mock)
                
                observer.start()
                try assertTrue(observer.isObserving, "Observer must be observing")
                try assertTrue(mock.isMonitoring, "Provider must be monitoring")
                
                observer.stop()
                try assertFalse(observer.isObserving, "Observer must stop observing")
                try assertFalse(mock.isMonitoring, "Provider must stop monitoring")
            }
            
            runner.test("PO.3: Power Source Change to Battery Dispatches to Delegate") {
                let mock = MockPowerSourceProvider(initialState: PowerState(source: .ac, isCharging: true))
                let observer = PowerObserver(provider: mock)
                let delegate = MockDelegate()
                observer.delegate = delegate
                observer.start()
                
                let batteryState = PowerState(source: .battery, batteryLevel: 0.85, isCharging: false)
                mock.simulateChange(to: batteryState)
                
                try assertEqual(observer.currentState.source, .battery, "Current state must update to battery")
                try assertTrue(observer.currentState.isOnBattery, "isOnBattery must be true")
                try assertEqual(delegate.states.count, 1, "Delegate must receive 1 change")
                try assertEqual(delegate.states.first?.source, .battery, "Received state must be battery")
            }
            
            runner.test("PO.4: Power Source Change to AC Restores AC State") {
                let mock = MockPowerSourceProvider(initialState: PowerState(source: .battery, batteryLevel: 0.50, isCharging: false))
                let observer = PowerObserver(provider: mock)
                let delegate = MockDelegate()
                observer.delegate = delegate
                observer.start()
                
                let acState = PowerState(source: .ac, batteryLevel: 0.51, isCharging: true)
                mock.simulateChange(to: acState)
                
                try assertEqual(observer.currentState.source, .ac, "Must switch to AC")
                try assertFalse(observer.currentState.isOnBattery, "isOnBattery must be false")
                try assertTrue(observer.currentState.isCharging, "Must be charging")
            }
            
            runner.test("PO.5: Charging State Accurately Reflected") {
                let mock = MockPowerSourceProvider(initialState: PowerState(source: .battery, isCharging: false))
                let observer = PowerObserver(provider: mock)
                let delegate = MockDelegate()
                observer.delegate = delegate
                observer.start()
                
                mock.simulateChange(to: PowerState(source: .battery, isCharging: true))
                try assertTrue(observer.currentState.isCharging, "isCharging must be true")
                try assertEqual(delegate.states.count, 1, "Delegate must be notified")
            }
            
            runner.test("PO.6: Battery Level Correctly Normalized in 0.0 ... 1.0") {
                let mock = MockPowerSourceProvider(initialState: PowerState(source: .battery, batteryLevel: 0.42))
                let observer = PowerObserver(provider: mock)
                
                try assertEqual(observer.currentState.batteryLevel, 0.42, "Battery level must be 0.42")
            }
            
            runner.test("PO.7: Low Power Mode Enable & Disable Toggles") {
                let mock = MockPowerSourceProvider(initialState: PowerState(source: .battery, isLowPowerModeEnabled: false))
                let observer = PowerObserver(provider: mock)
                let delegate = MockDelegate()
                observer.delegate = delegate
                observer.start()
                
                // Enable LPM
                mock.simulateChange(to: PowerState(source: .battery, isLowPowerModeEnabled: true))
                try assertTrue(observer.currentState.isLowPowerModeEnabled, "LPM must be true")
                try assertEqual(delegate.states.count, 1, "Delegate must be notified")
                
                // Disable LPM
                mock.simulateChange(to: PowerState(source: .battery, isLowPowerModeEnabled: false))
                try assertFalse(observer.currentState.isLowPowerModeEnabled, "LPM must be false")
                try assertEqual(delegate.states.count, 2, "Delegate must be notified of disable")
            }
            
            runner.test("PO.8: Thermal State Transitions (.nominal -> .serious -> .critical)") {
                let mock = MockPowerSourceProvider(initialState: PowerState(thermalState: .nominal))
                let observer = PowerObserver(provider: mock)
                let delegate = MockDelegate()
                observer.delegate = delegate
                observer.start()
                
                mock.simulateChange(to: PowerState(thermalState: .serious))
                try assertEqual(observer.currentState.thermalState, .serious, "Thermal must be serious")
                
                mock.simulateChange(to: PowerState(thermalState: .critical))
                try assertEqual(observer.currentState.thermalState, .critical, "Thermal must be critical")
                try assertEqual(delegate.states.count, 2, "Delegate must receive both thermal changes")
            }
            
            runner.test("PO.9: Redundant State Changes are Suppressed") {
                let mock = MockPowerSourceProvider(initialState: PowerState(source: .ac, batteryLevel: 1.0))
                let observer = PowerObserver(provider: mock)
                let delegate = MockDelegate()
                observer.delegate = delegate
                observer.start()
                
                // Fire identical state 5 times
                for _ in 1...5 {
                    mock.simulateChange(to: PowerState(source: .ac, batteryLevel: 1.0))
                }
                try assertTrue(delegate.states.isEmpty, "Redundant notifications must not trigger delegate")
            }
            
            runner.test("PO.10: Desktop Mac Edge Case (No Battery, nil Level)") {
                let mock = MockPowerSourceProvider(initialState: PowerState(source: .ac, batteryLevel: nil, isCharging: false))
                let observer = PowerObserver(provider: mock)
                
                try assertEqual(observer.currentState.source, .ac, "Must be AC")
                try assertNil(observer.currentState.batteryLevel, "Battery level must be nil")
                try assertFalse(observer.currentState.isOnBattery, "Must not be on battery")
            }
            
            runner.test("PO.11: Multiple Start/Stop Calls are Idempotent") {
                let mock = MockPowerSourceProvider()
                let observer = PowerObserver(provider: mock)
                
                observer.start()
                observer.start()
                try assertTrue(observer.isObserving, "Still observing")
                
                observer.stop()
                observer.stop()
                try assertFalse(observer.isObserving, "Still not observing")
            }
            
            runner.test("PO.12: Live IOKit Provider Smoke Query Does Not Crash") {
                let liveProvider = IOKitPowerSourceProvider()
                let state = liveProvider.fetchCurrentPowerState()
                try assertTrue(state.source != .unknown, "Live power source must not be unknown")
                liveProvider.startMonitoring()
                liveProvider.stopMonitoring()
            }
        }
    }
}

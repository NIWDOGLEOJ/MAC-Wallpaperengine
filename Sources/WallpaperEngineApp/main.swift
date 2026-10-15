//
//  main.swift
//  WallpaperEngineApp
//
//  Daemon executable entrypoint for Wallpaper Engine Core.
//

import AppKit
import Foundation
import WallpaperEngineCore

// 1. Parse command-line options
let cliOptions = CommandLineOptions.parse()

// 2. Handle immediate one-shot CLI commands
if cliOptions.isHelpRequested {
    print(CommandLineOptions.usageString)
    exit(0)
}

if cliOptions.isVersionRequested {
    print(CommandLineOptions.versionString)
    exit(0)
}

if cliOptions.dumpConfig {
    let storage = FileConfigStorage(fileURL: cliOptions.configPath.map { URL(fileURLWithPath: $0) })
    var config = storage.load() ?? EngineConfig.default
    cliOptions.apply(to: &config)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(config), let jsonStr = String(data: data, encoding: .utf8) {
        print(jsonStr)
    }
    exit(0)
}

// 3. Configure macOS Accessory Application Activation Policy (LSUIElement = 1)
// Ensures the daemon operates without stealing focus or displaying a Dock icon.
NSApplication.shared.setActivationPolicy(.accessory)

// 4. Initialize and start the master AppCoordinator
let storage = FileConfigStorage(fileURL: cliOptions.configPath.map { URL(fileURLWithPath: $0) })
let coordinator = AppCoordinator(configStorage: storage, cliOptions: cliOptions)
coordinator.start()

// 5. Handle benchmark mode if requested
if cliOptions.isBenchmark {
    print("Executing benchmark telemetry sweep (10 seconds)...")
    Task {
        try? await Task.sleep(nanoseconds: 10_000_000_000)
        print("Benchmark completed successfully.")
        await MainActor.run {
            coordinator.stop()
            NSApp.terminate(nil)
        }
    }
}

// 6. Run the AppKit application event loop
NSApplication.shared.run()

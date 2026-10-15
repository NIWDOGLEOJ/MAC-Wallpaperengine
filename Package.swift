// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WallpaperEngineCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "WallpaperEngineCore",
            targets: ["WallpaperEngineCore"]
        ),
        .executable(
            name: "WallpaperEngineApp",
            targets: ["WallpaperEngineApp"]
        ),
        .executable(
            name: "WallpaperEngineCoreTests",
            targets: ["WallpaperEngineCoreTests"]
        )
    ],
    dependencies: [],
    targets: [
        // WallpaperEngineApp Executable Daemon
        .executableTarget(
            name: "WallpaperEngineApp",
            dependencies: ["WallpaperEngineCore"],
            path: "Sources/WallpaperEngineApp",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        // Core Engine Library
        // Core Engine Library
        .target(
            name: "WallpaperEngineCore",
            dependencies: [],
            path: "Sources/WallpaperEngineCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        // Milestone 1 Unit & Integration Test Runner (Executable)
        .executableTarget(
            name: "WallpaperEngineCoreTests",
            dependencies: ["WallpaperEngineCore"],
            path: "Tests/WallpaperEngineCoreTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        // End-to-End Test Suite (Native Swift Testing)
        .testTarget(
            name: "E2ETests",
            dependencies: [],
            path: "Tests/E2ETests",
            swiftSettings: [
                .unsafeFlags([
                    "-swift-version", "5",
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-load-plugin-library", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
                ])
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)

// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TrafficMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TrafficCore", targets: ["TrafficCore"]),
        .executable(name: "traffic-probe", targets: ["TrafficProbe"])
    ],
    targets: [
        .target(
            name: "TrafficCore",
            path: "Sources/Core",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "TrafficProbe",
            dependencies: ["TrafficCore"],
            path: "Sources/Probe"
        ),
        .testTarget(
            name: "TrafficCoreTests",
            dependencies: ["TrafficCore"],
            path: "Tests/TrafficCoreTests"
        )
    ]
)

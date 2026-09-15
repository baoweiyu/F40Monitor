// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "F40Monitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "F40Monitor", targets: ["F40Monitor"])
    ],
    targets: [
        .executableTarget(name: "F40Monitor"),
        .testTarget(name: "F40MonitorTests", dependencies: ["F40Monitor"])
    ]
)

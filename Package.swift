// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReplaceKit",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ReplaceKit", targets: ["ReplaceKitApp"]),
        .executable(name: "ReplaceKitAXProbe", targets: ["ReplaceKitAXProbe"]),
        .executable(name: "ReplaceKitTests", targets: ["ReplaceKitTests"]),
        .library(name: "ReplaceKitCore", targets: ["ReplaceKitCore"]),
        .library(name: "ReplaceKitMac", targets: ["ReplaceKitMac"]),
    ],
    targets: [
        .target(name: "ReplaceKitCore"),
        .target(name: "ReplaceKitMac", dependencies: ["ReplaceKitCore"]),
        .executableTarget(name: "ReplaceKitApp", dependencies: ["ReplaceKitCore", "ReplaceKitMac"]),
        .executableTarget(name: "ReplaceKitAXProbe", dependencies: ["ReplaceKitMac"], path: "Tools/ReplaceKitAXProbe"),
        .executableTarget(name: "ReplaceKitTests", dependencies: ["ReplaceKitCore", "ReplaceKitMac"], path: "Tests/ReplaceKitTests"),
    ]
)

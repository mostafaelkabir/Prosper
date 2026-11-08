// swift-tools-version:6.0
import PackageDescription

// Shared core for the iPhone and Mac apps (docs/mac/PLAN.md §3.7). Pure Swift:
// models, domain logic, copy, design tokens. The Mac targets link this package;
// the iOS targets compile the same files by path from project.yml.
let package = Package(
    name: "ProsperCore",
    platforms: [.iOS(.v17), .macOS(.v15)],
    products: [
        .library(name: "ProsperCore", targets: ["ProsperCore"]),
    ],
    targets: [
        .target(name: "ProsperCore"),
        .testTarget(name: "ProsperCoreTests", dependencies: ["ProsperCore"]),
    ]
)

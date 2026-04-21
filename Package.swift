// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TokenScope",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TokenScopeApp", targets: ["TokenScopeApp"]),
        .library(name: "TokenScopeCore", targets: ["TokenScopeCore"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "TokenScopeApp",
            dependencies: ["TokenScopeCore"],
            path: "Sources/TokenScopeApp"
        ),
        .target(
            name: "TokenScopeCore",
            path: "Sources/TokenScopeCore"
        ),
        .testTarget(
            name: "TokenScopeCoreTests",
            dependencies: ["TokenScopeCore"],
            path: "Tests/TokenScopeCoreTests"
        ),
    ]
)

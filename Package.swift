// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TokenScope",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TokenScopeApp", targets: ["TokenScopeApp"]),
        .library(name: "TokenScopeCore", targets: ["TokenScopeCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/facebook/zstd.git", exact: "1.5.7"),
    ],
    targets: [
        .executableTarget(
            name: "TokenScopeApp",
            dependencies: ["TokenScopeCore"],
            path: "Sources/TokenScopeApp",
            resources: [.process("Resources")]
        ),
        .target(
            name: "TokenScopeCore",
            dependencies: [
                .product(name: "libzstd", package: "zstd"),
            ],
            path: "Sources/TokenScopeCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "TokenScopeCoreTests",
            dependencies: [
                "TokenScopeCore",
                .product(name: "libzstd", package: "zstd"),
            ],
            path: "Tests/TokenScopeCoreTests"
        ),
    ]
)

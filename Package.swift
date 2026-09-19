// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TerminalAsset",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "TerminalAssetDomain", targets: ["TerminalAssetDomain"]),
        .library(name: "TerminalAssetCore", targets: ["TerminalAssetCore"])
    ],
    targets: [
        .target(
            name: "TerminalAssetDomain",
            path: "Sources/TerminalAssetDomain"
        ),
        .target(
            name: "TerminalAssetCore",
            dependencies: ["TerminalAssetDomain"],
            path: "Sources/TerminalAssetCore"
        ),
        .testTarget(
            name: "TerminalAssetCoreTests",
            dependencies: ["TerminalAssetCore", "TerminalAssetDomain"],
            path: "Tests/TerminalAssetCoreTests"
        ),
        .testTarget(
            name: "TerminalAssetDomainTests",
            dependencies: ["TerminalAssetDomain"],
            path: "Tests/TerminalAssetDomainTests"
        )
    ]
)

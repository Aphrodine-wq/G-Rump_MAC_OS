// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let strictLibrarySettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency=complete"),
    .unsafeFlags(["-warnings-as-errors"]),
]

let package = Package(
    name: "GRump",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "GRumpKit", targets: ["GRumpKit"]),
        .executable(name: "grump", targets: ["GRumpCLI"]),
        .executable(
            name: "G-Rump",
            targets: ["GRumpAppExecutable"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .target(
            name: "GRumpCore",
            path: "Sources/GRumpCore",
            swiftSettings: strictLibrarySettings
        ),
        .target(
            name: "GRumpTools",
            dependencies: ["GRumpCore"],
            path: "Sources/GRumpTools",
            resources: [.process("Resources")],
            swiftSettings: strictLibrarySettings
        ),
        .target(
            name: "GRumpProviders",
            dependencies: ["GRumpCore"],
            path: "Sources/GRumpProviders",
            swiftSettings: strictLibrarySettings
        ),
        .target(
            name: "GRumpAgent",
            dependencies: ["GRumpCore", "GRumpTools", "GRumpProviders"],
            path: "Sources/GRumpAgent",
            swiftSettings: strictLibrarySettings
        ),
        .target(
            name: "GRumpMCP",
            dependencies: [
                "GRumpCore", "GRumpTools", "GRumpAgent",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ],
            path: "Sources/GRumpMCP",
            swiftSettings: strictLibrarySettings
        ),
        .target(
            name: "GRumpApple",
            dependencies: ["GRumpCore", "GRumpTools"],
            path: "Sources/GRumpApple",
            swiftSettings: strictLibrarySettings
        ),
        .target(
            name: "GRumpKit",
            dependencies: ["GRumpCore", "GRumpTools", "GRumpProviders", "GRumpAgent", "GRumpMCP", "GRumpApple"],
            path: "Sources/GRumpKit",
            swiftSettings: strictLibrarySettings
        ),
        .executableTarget(
            name: "GRumpCLI",
            dependencies: ["GRumpKit"],
            path: "Sources/GRumpCLI",
            swiftSettings: strictLibrarySettings
        ),
        .target(
            name: "GRumpAppCore",
            dependencies: [
                "GRumpKit",
                .product(name: "Sparkle", package: "Sparkle", condition: .when(platforms: [.macOS])),
            ],
            path: "Sources/GRump",
            exclude: ["Info.plist"],
            resources: [.process("Resources")],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=complete"),
                .define("GRUMP_SPM_BUILD"),
                .define("GRUMP_LIBRARY_BUILD"),
            ]),
        .executableTarget(
            name: "GRumpAppExecutable",
            dependencies: ["GRumpAppCore"],
            path: "Sources/GRumpAppExecutable"
        ),
        .testTarget(
            name: "GRumpTests",
            dependencies: ["GRumpAppCore", "GRumpKit"],
            path: "Tests/GRumpTests"
        ),
        .testTarget(
            name: "GRumpKitTests",
            dependencies: ["GRumpKit"],
            path: "Tests/GRumpKitTests"
        ),
    ]
)

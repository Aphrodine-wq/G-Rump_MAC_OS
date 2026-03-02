// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GRump",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .executable(
            name: "GRump",
            targets: ["GRump"]),
        .executable(
            name: "GRumpServer",
            targets: ["GRumpServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "GRump",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle", condition: .when(platforms: [.macOS])),
            ],
            path: "Sources/GRump",
            exclude: ["Info.plist"],
            resources: [.process("Resources")],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=complete"),
                .define("GRUMP_SPM_BUILD"),
            ]),
        .executableTarget(
            name: "GRumpServer",
            dependencies: [],
            path: "Sources/GRumpServer"),
        .testTarget(
            name: "GRumpTests",
            dependencies: ["GRump"],
            path: "Tests/GRumpTests"
        ),
    ]
)

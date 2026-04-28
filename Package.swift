// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Whitesnake",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Whitesnake",
            targets: ["Whitesnake"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Whitesnake",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "WhitesnakeTests",
            dependencies: ["Whitesnake"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

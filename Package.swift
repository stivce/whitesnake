// swift-tools-version: 6.0

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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "Whitesnake",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .testTarget(
            name: "WhitesnakeTests",
            dependencies: ["Whitesnake"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

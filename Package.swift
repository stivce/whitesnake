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
        .package(url: "https://github.com/apple/swift-testing", from: "0.9.0"),
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
            dependencies: [
                "Whitesnake",
                .product(name: "Testing", package: "swift-testing")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

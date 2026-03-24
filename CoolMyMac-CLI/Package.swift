// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoolMyMacCLI",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "../SMCKit"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "CoolMyMacCLI",
            dependencies: [
                .product(name: "SMCKit", package: "SMCKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/CoolMyMacCLI"
        )
    ]
)

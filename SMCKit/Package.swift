// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SMCKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "SMCKit",
            targets: ["SMCKit"]
        )
    ],
    targets: [
        .target(
            name: "SMCKit",
            path: "Sources/SMCKit"
        ),
        .testTarget(
            name: "SMCKitTests",
            dependencies: ["SMCKit"],
            path: "Tests/SMCKitTests"
        )
    ]
)

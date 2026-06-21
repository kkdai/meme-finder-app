// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MemeFinder",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MemeFinder",
            path: "Sources/MemeFinder"
        ),
        .testTarget(
            name: "MemeFinderTests",
            dependencies: [
                "MemeFinder",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/MemeFinderTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)

// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MemeFinder",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.0.0"),
    ],
    targets: [
        // Library target: all logic, models, services, and view models.
        // Tests depend on this; it has no main entry point so it links cleanly
        // as a library. The @main SwiftUI app lives in the MemeFinderApp
        // executable target (added in the UI task) and imports this.
        .target(
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

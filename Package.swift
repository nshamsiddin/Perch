// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Perch",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Perch", targets: ["Perch"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Perch",
            dependencies: ["Sparkle"],
            path: "Sources/Perch"
        ),
        .testTarget(
            name: "PerchTests",
            dependencies: ["Perch"],
            path: "Tests/PerchTests"
        )
    ]
)

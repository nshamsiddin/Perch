// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Islet",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Islet",
            path: "Sources/Islet"
        )
    ]
)

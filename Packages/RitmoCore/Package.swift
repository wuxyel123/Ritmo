// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RitmoCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "RitmoCore", targets: ["RitmoCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "RitmoCore",
            dependencies: [],
            path: "Sources/RitmoCore"
        )
    ]
)

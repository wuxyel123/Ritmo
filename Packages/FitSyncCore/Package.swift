// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FitSyncCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "FitSyncCore", targets: ["FitSyncCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FitSyncCore",
            dependencies: [],
            path: "Sources/FitSyncCore"
        )
    ]
)

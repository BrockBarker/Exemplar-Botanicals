// swift-tools-version:5.9
import PackageDescription

// Pure-Swift garden logic shared by the iPhone app: vocabulary, crop catalog, weather
// parsing and math (GDD, water balance), the nudge engine, and the backend API models.
// It depends only on Foundation so its tests also run on Linux (see .github/workflows/ci.yml).
let package = Package(
    name: "GardenCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GardenCore", targets: ["GardenCore"]),
    ],
    targets: [
        .target(name: "GardenCore"),
        .testTarget(name: "GardenCoreTests", dependencies: ["GardenCore"]),
    ]
)

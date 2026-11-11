// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Planer",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PlanerCore"),
        .target(name: "PlanerData", dependencies: ["PlanerCore"]),
        .executableTarget(
            name: "Planer",
            dependencies: ["PlanerCore", "PlanerData"]
        ),
        .executableTarget(
            name: "PlanerWidget",
            dependencies: ["PlanerCore", "PlanerData"]
        ),
        .testTarget(name: "PlanerCoreTests", dependencies: ["PlanerCore"]),
        .testTarget(name: "PlanerDataTests", dependencies: ["PlanerData", "PlanerCore"]),
    ]
)

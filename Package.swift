// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StreetViewWander",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "StreetViewWander", targets: ["StreetViewWander"]),
        .executable(name: "StreetViewWanderSelfTest", targets: ["StreetViewWanderSelfTest"])
    ],
    targets: [
        .target(
            name: "StreetViewWanderCore",
            path: "Sources/StreetViewWanderCore"
        ),
        .executableTarget(
            name: "StreetViewWander",
            dependencies: ["StreetViewWanderCore"],
            path: "Sources/StreetViewWander"
        ),
        .executableTarget(
            name: "StreetViewWanderSelfTest",
            dependencies: ["StreetViewWanderCore"],
            path: "Sources/StreetViewWanderSelfTest"
        )
    ]
)

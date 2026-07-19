// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OrbeliasDB",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "OrbeliasDB", targets: ["OrbeliasDB"])
    ],
    targets: [
        .systemLibrary(
            name: "COrbeliasDB",
            path: "Sources/COrbeliasDB"
        ),
        .target(
            name: "OrbeliasDB",
            dependencies: ["COrbeliasDB"],
            linkerSettings: [
                .unsafeFlags(["-L../../lib"])
            ]
        ),
        .testTarget(
            name: "OrbeliasDBTests",
            dependencies: ["OrbeliasDB"]
        )
    ]
)

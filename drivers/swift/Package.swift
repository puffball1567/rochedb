// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RocheDB",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "RocheDB", targets: ["RocheDB"])
    ],
    targets: [
        .systemLibrary(
            name: "CRocheDB",
            path: "Sources/CRocheDB"
        ),
        .target(
            name: "RocheDB",
            dependencies: ["CRocheDB"],
            linkerSettings: [
                .unsafeFlags(["-L../../lib"])
            ]
        ),
        .testTarget(
            name: "RocheDBTests",
            dependencies: ["RocheDB"]
        )
    ]
)

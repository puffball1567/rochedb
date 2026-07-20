// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KoutenDB",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "KoutenDB", targets: ["KoutenDB"])
    ],
    targets: [
        .systemLibrary(
            name: "CKoutenDB",
            path: "Sources/CKoutenDB"
        ),
        .target(
            name: "KoutenDB",
            dependencies: ["CKoutenDB"],
            linkerSettings: [
                .unsafeFlags(["-L../../lib"])
            ]
        ),
        .testTarget(
            name: "KoutenDBTests",
            dependencies: ["KoutenDB"]
        )
    ]
)

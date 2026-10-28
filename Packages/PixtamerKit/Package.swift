// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PixtamerKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PixtamerKit", targets: ["PixtamerKit"]),
    ],
    targets: [
        // Vendored libwebp 1.6.0 (BSD-3-Clause). See Sources/CWebP/libwebp/VENDORED.md.
        .target(
            name: "CWebP",
            exclude: [
                "libwebp/COPYING",
                "libwebp/PATENTS",
                "libwebp/AUTHORS",
                "libwebp/VENDORED.md",
            ],
            cSettings: [
                .headerSearchPath("libwebp"),
                .define("NDEBUG", .when(configuration: .release)),
                .unsafeFlags(["-w"]),
            ]
        ),
        .target(
            name: "PixtamerKit",
            dependencies: ["CWebP"]
        ),
        .testTarget(
            name: "PixtamerKitTests",
            dependencies: ["PixtamerKit"]
        ),
    ]
)

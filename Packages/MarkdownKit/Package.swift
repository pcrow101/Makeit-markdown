// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MarkdownKit",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "MarkdownKit",
            targets: ["MarkdownKit"]
        ),
        .executable(
            name: "makeit-markdown",
            targets: ["makeit-markdown"]
        )
    ],
    dependencies: [
        // Pinned below 1.6.0: the 1.8.x manifests declare a custom path
        // ('Tools/generate-docc-reference') that is absent from the tagged
        // sources, which aborts package graph resolution in Xcode.
        .package(url: "https://github.com/apple/swift-argument-parser.git", "1.5.0" ..< "1.6.0")
    ],
    targets: [
        .target(
            name: "MarkdownKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "makeit-markdown",
            dependencies: [
                "MarkdownKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MarkdownKitTests",
            dependencies: ["MarkdownKit", "makeit-markdown"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

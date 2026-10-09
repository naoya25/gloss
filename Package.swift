// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Gloss",
    platforms: [.macOS(.v14)],
    products: [.library(name: "GlossCore", targets: ["GlossCore"])],
    targets: [
        .target(name: "GlossCore"),
        .executableTarget(name: "Gloss", dependencies: ["GlossCore"]),
        .testTarget(name: "GlossCoreTests", dependencies: ["GlossCore"]),
    ],
    swiftLanguageModes: [.v5]
)

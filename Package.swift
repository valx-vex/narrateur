// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Narrateur",
    platforms: [.macOS(.v14)],
    products: [.library(name: "NarrateurCore", targets: ["NarrateurCore"]), .executable(name: "Narrateur", targets: ["Narrateur"])],
    targets: [
        .target(name: "NarrateurCore"),
        .executableTarget(name: "Narrateur", dependencies: ["NarrateurCore"]),
        .testTarget(name: "NarrateurCoreTests", dependencies: ["NarrateurCore", "Narrateur"], resources: [.copy("Fixtures")])
    ]
)

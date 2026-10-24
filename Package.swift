// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Afterglow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Afterglow", targets: ["Afterglow"])],
    targets: [
        .target(name: "AfterglowCore"),
        .executableTarget(name: "Afterglow", dependencies: ["AfterglowCore"]),
        .executableTarget(name: "AfterglowChecks", dependencies: ["AfterglowCore"], path: "Tests/AfterglowCoreTests")
    ],
    swiftLanguageModes: [.v5]
)

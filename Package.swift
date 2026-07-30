// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "Startle",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "StartleCore", targets: ["StartleCore"]),
    .executable(name: "Startle", targets: ["StartleApp"]),
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4")
  ],
  targets: [
    .target(name: "StartleCore"),
    .executableTarget(
      name: "StartleApp",
      dependencies: [
        "StartleCore",
        .product(name: "Sparkle", package: "Sparkle"),
      ],
      resources: [.process("Resources")]
    ),
    .testTarget(name: "StartleCoreTests", dependencies: ["StartleCore"]),
  ],
  swiftLanguageModes: [.v5]
)

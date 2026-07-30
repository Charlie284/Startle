// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "Startle",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "StartleCore", targets: ["StartleCore"]),
    .executable(name: "Startle", targets: ["StartleApp"]),
  ],
  targets: [
    .target(name: "StartleCore"),
    .executableTarget(
      name: "StartleApp",
      dependencies: ["StartleCore"],
      resources: [.process("Resources")]
    ),
    .testTarget(name: "StartleCoreTests", dependencies: ["StartleCore"]),
  ],
  swiftLanguageModes: [.v5]
)

// swift-tools-version:5.7
import PackageDescription

let package = Package(
  name: "PolkabindSwift",
  platforms: [
    .iOS(.v13)
  ],
  products: [
    .library(
      name: "PolkabindSwift",
      targets: ["Polkabind"]
    )
  ],
  targets: [
    // Binary target (C‐ABI)
    .binaryTarget(
      name: "PolkabindFFI",
      path: "Polkabind.xcframework"
    ),

    // Swift target
    .target(
      name: "Polkabind",
      dependencies: ["PolkabindFFI"],
      path: "Sources/Polkabind"
    )
  ]
)

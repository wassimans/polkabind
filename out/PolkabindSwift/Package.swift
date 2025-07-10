// swift-tools-version:5.7
import PackageDescription

let package = Package(
  name: "Polkabind",
  platforms: [
    .iOS(.v13), .macOS(.v12),
  ],
  products: [
    .library(
      name: "Polkabind",
      targets: ["Polkabind"]
    ),
  ],
  targets: [
    .binaryTarget(
      name: "polkabindFFI",
      path: "polkabindFFI.xcframework"
    ),
    .target(
      name: "Polkabind",
      dependencies: ["polkabindFFI"]
    ),
  ]
)

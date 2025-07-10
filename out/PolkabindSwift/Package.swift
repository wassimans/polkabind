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
    // your Swift façade
    .target(
      name: "Polkabind",
      dependencies: [
        .target(name: "PolkabindFFI")
      ]
    ),
    // the binary FFI module
    .binaryTarget(
      name: "PolkabindFFI",          // <— lowercase, matches import
      path: "Polkabind.xcframework"
    ),
  ]
)

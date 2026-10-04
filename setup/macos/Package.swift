// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "SquirrelSetup",
  platforms: [.macOS(.v13)],
  targets: [
    .executableTarget(
      name: "SquirrelSetup",
      path: "Sources/SquirrelSetup",
      swiftSettings: [.unsafeFlags(["-suppress-warnings"])]
    )
  ]
)

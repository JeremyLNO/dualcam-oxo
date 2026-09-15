// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "CrazyBeeLicense",
  platforms: [.macOS(.v13), .iOS(.v16)],
  products: [
    .library(name: "CrazyBeeLicense", targets: ["CrazyBeeLicense"]),
  ],
  targets: [
    .target(name: "CrazyBeeLicense"),
  ]
)

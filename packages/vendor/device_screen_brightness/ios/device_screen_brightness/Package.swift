// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "device_screen_brightness",
  platforms: [.iOS("13.0")],
  products: [
    .library(name: "device-screen-brightness", targets: ["device_screen_brightness"]),
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework"),
  ],
  targets: [
    .target(
      name: "device_screen_brightness",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework"),
      ]
    ),
  ]
)

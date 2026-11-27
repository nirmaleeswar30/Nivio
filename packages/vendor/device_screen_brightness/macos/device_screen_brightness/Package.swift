// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "device_screen_brightness",
  platforms: [.macOS("10.15")],
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
      ],
      cSettings: [
        .headerSearchPath("include/device_screen_brightness"),
      ],
      linkerSettings: [
        .linkedFramework("CoreGraphics"),
        .linkedFramework("IOKit"),
      ]
    ),
  ]
)

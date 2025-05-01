// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DAWebRTC",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(name: "DAWebRTC", targets: ["DAWebRTC"])
    ],
    dependencies: [
        .package(url: "https://github.com/stasel/WebRTC.git", .upToNextMajor(from: "135.0.0"))
    ],
    targets: [
        .target(
            name: "DAWebRTC",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC")
            ],
            path: "Sources"
        )
    ]
)

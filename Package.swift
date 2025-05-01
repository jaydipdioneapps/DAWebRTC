// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DAWebRTC",
    platforms: [
        .iOS(.v13)
    ], products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "DAWebRTC",
            targets: ["DAWebRTC"]),
    ],
    dependencies: [
        //.package(url: "https://github.com/jaydipdioneapps/DACombineAlamofireAPI", from: "1.0.0"),
            .package(url: "https://github.com/stasel/WebRTC.git", .upToNextMajor(from: "135.0.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "DAWebRTC",
            dependencies: ["WebRTC"]),
        .testTarget(
            name: "DAWebRTCTests",
            dependencies: ["DAWebRTC"]),
    ],
    swiftLanguageModes: [.v5]

)

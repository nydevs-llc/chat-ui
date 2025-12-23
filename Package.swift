// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Chat",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "ExyteChat",
            targets: ["ExyteChat"]),
    ],
    dependencies: [
//        .package(
//            url: "https://github.com/exyte/MediaPicker.git",
//            from: "3.2.4"
//        ),
        .package(
            url: "https://github.com/exyte/FloatingButton",
            from: "1.2.2"
        )
    ],
    targets: [
        .target(
            name: "ExyteChat",
            dependencies: [
//                .product(name: "ExyteMediaPicker", package: "MediaPicker"),
                .product(name: "FloatingButton", package: "FloatingButton"),
            ]
        )
    ]
)

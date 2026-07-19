// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NativeIslandOverlay",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NativeIslandOverlay", targets: ["NativeIslandOverlay"])
    ],
    targets: [
        .executableTarget(name: "NativeIslandOverlay"),
        .testTarget(name: "NativeIslandOverlayTests", dependencies: ["NativeIslandOverlay"])
    ]
)

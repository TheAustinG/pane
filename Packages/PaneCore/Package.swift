// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PaneCore",
    platforms: [.macOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "PaneCore", targets: ["PaneCore"]),
    ],
    targets: [
        .target(name: "PaneCore"),
        .testTarget(name: "PaneCoreTests", dependencies: ["PaneCore"], resources: [.copy("Fixtures")]),
    ]
)

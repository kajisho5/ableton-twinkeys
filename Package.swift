// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TwinKeys",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TwinKeys", targets: ["TwinKeys"]),
    ],
    targets: [
        // Platform-independent logic. Builds and tests on Linux too.
        .target(name: "TwinKeysCore"),
        // macOS app (SwiftUI, CoreMIDI, Network.framework, CGEventTap).
        .executableTarget(
            name: "TwinKeys",
            dependencies: ["TwinKeysCore"],
            linkerSettings: [
                .linkedFramework("CoreMIDI", .when(platforms: [.macOS])),
                .linkedFramework("Network", .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(name: "TwinKeysCoreTests", dependencies: ["TwinKeysCore"]),
    ]
)

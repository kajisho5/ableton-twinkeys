// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TwinKeys",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TwinKeys", targets: ["TwinKeys"]),
    ],
    dependencies: [
        // Apple's swift-crypto: re-exports CryptoKit on macOS, same API on Linux for the tests.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "5.1.1"),
    ],
    targets: [
        // Platform-independent logic. Builds and tests on Linux too.
        .target(name: "TwinKeysCore", dependencies: [.product(name: "Crypto", package: "swift-crypto")]),
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

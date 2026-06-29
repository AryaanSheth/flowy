// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Flowy",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "Flowy", targets: ["Flowy"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", .upToNextMinor(from: "0.18.0")),
    ],
    targets: [
        .executableTarget(
            name: "Flowy",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/Flowy",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Speech"),
                // Translation is macOS 14+. Weak-link it so the binary still
                // launches on macOS 13 (TranslationBridge gates use at runtime).
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "Translation"]),
            ]
        ),
        .testTarget(
            name: "FlowyTests",
            dependencies: ["Flowy"],
            path: "Tests/FlowyTests"
        ),
    ]
)

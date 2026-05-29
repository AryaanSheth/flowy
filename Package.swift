// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Flowey",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "Flowey", targets: ["Flowey"]),
    ],
    targets: [
        .executableTarget(
            name: "Flowey",
            path: "Sources/Flowey",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Speech"),
            ]
        ),
    ]
)

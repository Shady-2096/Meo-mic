// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MeoMic",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MeoMic", targets: ["MeoMicApp"])
    ],
    targets: [
        .target(
            name: "CMeoAudio",
            publicHeadersPath: "include"
        ),
        .target(
            name: "MeoMicCore",
            dependencies: ["CMeoAudio"],
            linkerSettings: [
                .linkedFramework("AVFAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Network")
            ]
        ),
        .executableTarget(
            name: "MeoMicApp",
            dependencies: ["MeoMicCore"],
            resources: [
                .copy("Resources/icon.jpg")
            ],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreImage")
            ]
        ),
        .testTarget(
            name: "MeoMicCoreTests",
            dependencies: ["MeoMicCore", "CMeoAudio"]
        )
    ],
    swiftLanguageModes: [.v5]
)

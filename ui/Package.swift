// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ohmyvoice-ui",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "OhMyVoiceUI",
            path: "Sources/OhMyVoiceUI"
        ),
        .executableTarget(
            name: "ohmyvoice-ui",
            dependencies: ["OhMyVoiceUI"],
            path: "Sources/CLI"
        ),
        .testTarget(
            name: "OhMyVoiceUITests",
            dependencies: ["OhMyVoiceUI"],
            path: "Tests/OhMyVoiceUITests"
        ),
    ]
)

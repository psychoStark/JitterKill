// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JitterKill",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "JitterKill", targets: ["JitterKillApp"])
    ],
    targets: [
        .executableTarget(
            name: "JitterKillApp",
            path: "Sources/JitterKillApp",
            exclude: [
                "Resources/Info.plist",
                "Resources/Assets.xcassets",
                "task.md"
            ],
            resources: [
                .copy("Resources/jitterkill-helper.sh"),
                .copy("Resources/jitterkill-cli.sh"),
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/logo.png"),
                .copy("Resources/logo_1024.png"),
                .copy("Resources/mono_guard.png"),
                .copy("Resources/mono_unguard.png")
            ]
        )
    ]
)

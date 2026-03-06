// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChargeControl",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ChargeControl", targets: ["ChargeControlApp"]),
        .executable(name: "ChargeControlDaemon", targets: ["ChargeControlDaemon"])
    ],
    targets: [
        .target(
            name: "ChargeControlShared",
            path: "Shared"
        ),
        .executableTarget(
            name: "ChargeControlApp",
            dependencies: ["ChargeControlShared"],
            path: "App",
            sources: ["AppDelegate.swift", "BatteryState.swift", "SettingsView.swift", "Components.swift", "AppIntents.swift"]
        ),
        .executableTarget(
            name: "ChargeControlDaemon",
            dependencies: ["ChargeControlShared"],
            path: "Daemon",
            exclude: ["launchd.plist"],
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath(".")
            ]
        )
    ]
)

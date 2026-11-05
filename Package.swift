// swift-tools-version: 5.9
import PackageDescription

let strictConcurrency: [SwiftSetting] = [.enableUpcomingFeature("StrictConcurrency")]

let package = Package(
    name: "Ada",
    defaultLocalization: "tr",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Ada", targets: ["AdaLauncher"])],
    targets: [
        .target(name: "AdaCore", swiftSettings: strictConcurrency),
        .target(name: "Ada", dependencies: ["AdaCore"],
            resources: [.process("Resources")],
            swiftSettings: strictConcurrency,
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("IOKit"), .linkedFramework("WebKit"), .linkedFramework("Carbon"), .linkedFramework("ServiceManagement"), .linkedFramework("UserNotifications"), .linkedFramework("EventKit"), .linkedFramework("IOBluetooth")]),
        .executableTarget(name: "AdaLauncher", dependencies: ["Ada"], swiftSettings: strictConcurrency),
        .target(name: "AdaCheckSuite", dependencies: ["Ada", "AdaCore"], path: "Tests/Checks", swiftSettings: strictConcurrency),
        .executableTarget(name: "AdaChecks", dependencies: ["AdaCheckSuite"], path: "Tests/CheckRunner", swiftSettings: strictConcurrency),
        .testTarget(name: "AdaTests", dependencies: ["AdaCheckSuite"], path: "Tests/AdaTests", swiftSettings: strictConcurrency)
    ]
)

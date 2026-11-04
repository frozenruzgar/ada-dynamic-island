// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ada",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Ada", targets: ["Ada"])],
    targets: [
        .target(name: "AdaCore"),
        .executableTarget(name: "Ada", dependencies: ["AdaCore"],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("IOKit"), .linkedFramework("WebKit"), .linkedFramework("Carbon"), .linkedFramework("ServiceManagement")]),
        // Runs with Command Line Tools, without requiring full Xcode/XCTest.
        .executableTarget(name: "AdaChecks", dependencies: ["AdaCore"], path: "Tests/AdaCoreTests")
    ]
)

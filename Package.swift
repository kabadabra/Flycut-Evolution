// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flycut",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FlycutCore", targets: ["FlycutCore"]),
        .library(name: "FlycutPlatform", targets: ["FlycutPlatform"]),
        .executable(name: "FlycutMac", targets: ["FlycutMac"]),
    ],
    targets: [
        .target(name: "FlycutCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(
            name: "FlycutPlatform",
            dependencies: ["FlycutCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CloudKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Security"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(name: "FlycutMac", dependencies: ["FlycutCore", "FlycutPlatform"]),
        .testTarget(name: "FlycutCoreTests", dependencies: ["FlycutCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "FlycutMacTests", dependencies: ["FlycutMac", "FlycutCore"]),
        .testTarget(name: "FlycutPlatformTests", dependencies: ["FlycutPlatform", "FlycutCore"]),
    ],
    swiftLanguageModes: [.v6]
)

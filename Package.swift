// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stasis",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Stasis", targets: ["Stasis"]),
        // Not "stasis": the build directory is case-insensitive. The Makefile installs it as
        // Stasis.app/Contents/Helpers/stasis.
        .executable(name: "stasis-cli", targets: ["StasisCLI"]),
    ],
    targets: [
        .target(name: "StasisCore", linkerSettings: [.linkedFramework("AppKit")]),
        .executableTarget(
            name: "Stasis",
            dependencies: ["StasisCore"],
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
        .executableTarget(name: "StasisCLI", dependencies: ["StasisCore"]),
        .testTarget(name: "StasisCoreTests", dependencies: ["StasisCore"]),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stasis",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StasisCore"),
        .executableTarget(
            name: "Stasis",
            dependencies: ["StasisCore"],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ServiceManagement")]
        ),
        .testTarget(name: "StasisCoreTests", dependencies: ["StasisCore"]),
    ]
)

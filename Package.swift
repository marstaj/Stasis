// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppPause",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AppPauseCore"),
        .executableTarget(
            name: "AppPause",
            dependencies: ["AppPauseCore"],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ServiceManagement")]
        ),
        .testTarget(name: "AppPauseCoreTests", dependencies: ["AppPauseCore"]),
    ]
)

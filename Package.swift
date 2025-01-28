// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ngx_swift",
    platforms: [
        .macOS(.v10_13),
    ],
    products: [
        .executable(name: "sample", targets: ["sample"]),
        .library(name: "ngx_swift", targets: ["libnginx"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", revision: "1.5.0"),
        .package(url: "https://github.com/vproxy-tools/WaitfreeMpscQueueSwift", branch: "stable"),
        .package(url: "https://github.com/apple/swift-atomics", revision: "1.2.0"),
    ],
    targets: [
        // ---
        // executables
        // ...
        .executableTarget(
            name: "sample",
            dependencies: [
                "ngx_swift",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // ---
        // lib
        // ...
        .target(
            name: "ngx_swift",
            dependencies: [
                "libnginx",
                "WaitfreeMpscQueueSwift",
                "LinuxSOMemfd",
                .product(name: "Atomics", package: "swift-atomics"),
            ]
        ),
        // ---
        // native implementations
        // ...
        .target(
            name: "libnginx",
            path: "ngx_as_lib",
            cSettings: [
                .unsafeFlags(["-Wall"]),
            ]
        ),
        .target(
            name: "LinuxSOMemfd",
            path: "LinuxSOMemfd",
            cSettings: [
                .unsafeFlags(["-Wall"]),
            ]
        ),
    ]
)

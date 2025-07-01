// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Glyph",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Glyph", targets: ["Glyph"])
    ],
    dependencies: [
        .package(url: "https://github.com/pvieito/PythonKit.git", from: "0.3.1"),
        .package(url: "https://github.com/apple/swift-numerics", from: "1.0.0"),
        .package(url: "https://github.com/1024jp/GzipSwift", from: "5.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Glyph",
            dependencies: [
                "PythonKit",
                .product(name: "Numerics", package: "swift-numerics"),
                .product(name: "Gzip", package: "GzipSwift")
            ],
            resources: [
                .process("Resources"),
                .copy("PythonAPIService.py"),
                .copy("source_collection_workflow.py")
            ],
            swiftSettings: [
                // Disable strict concurrency checking for PythonKit compatibility
                .unsafeFlags(["-Xfrontend", "-disable-availability-checking"]),
                .unsafeFlags(["-Xfrontend", "-warn-concurrency"])
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                // Python framework linking
                .linkedLibrary("python3.13"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/Users/darrenlund/.pyenv/versions/3.13.3/lib"]),
                .unsafeFlags(["-L/Users/darrenlund/.pyenv/versions/3.13.3/lib"]),
                // Disable library validation for PythonKit
                .unsafeFlags(["-Xlinker", "-no_adhoc_codesign"])
            ]
        )
    ]
) 
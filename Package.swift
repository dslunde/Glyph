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
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit")
            ]
        )
    ]
) 
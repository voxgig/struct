// swift-tools-version:5.9
//
// Voxgig Struct — Swift port of the canonical TypeScript implementation.
// See ../REPORT.md for cross-language parity.
import PackageDescription

let package = Package(
    name: "VoxgigStruct",
    products: [
        .library(name: "VoxgigStruct", targets: ["VoxgigStruct"]),
    ],
    dependencies: [
        // OrderedDictionary preserves insertion order — required by the
        // canonical ports' map semantics and by the inject machinery's
        // `$`-suffix key partitioning.
        .package(url: "https://github.com/apple/swift-collections.git",
                 from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "VoxgigStruct",
            dependencies: [
                .product(name: "OrderedCollections", package: "swift-collections"),
            ],
            path: "Sources/VoxgigStruct"
        ),
        .testTarget(
            name: "VoxgigStructTests",
            dependencies: ["VoxgigStruct"],
            path: "Tests/VoxgigStructTests"
        ),
    ]
)

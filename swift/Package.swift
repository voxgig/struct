// swift-tools-version:5.9
//
// Voxgig Struct — Swift port of the canonical TypeScript implementation.
// Zero runtime dependencies — see Sources/VoxgigStruct/OrderedDictionary.swift
// for the in-tree insertion-ordered map type.
import Foundation
import PackageDescription

// The corpus runner is voxgig/omni, consumed as a local checkout - it is not
// published. `make test` points `.omni-runner`, a gitignored symlink, at the
// omni SwiftPM package it found via $OMNI_HOME or beside this repository.
//
// The symlink is not decoration. SwiftPM derives a path dependency's IDENTITY
// from the last path component, and omni's package lives at `omni/swift` -
// the same basename as this package's own directory, which SwiftPM then reads
// as a package depending on itself ("cyclic dependency between packages
// VoxgigStruct -> VoxgigStruct"). A distinctly named symlink gives it a
// distinct identity.
//
// It is a dependency of the TEST target only, and is declared at all only when
// the symlink is present: `swift build` compiles the library and the bench
// executable without it, and nothing this package ships names omni
// (register 4.13). `make test` fails with a readable message when the checkout
// is missing, rather than leaving `import Omni` to explain itself.
let omniLink = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent(".omni-runner").path

let omniPath: String? =
    FileManager.default.fileExists(atPath: omniLink + "/Package.swift") ? omniLink : nil

let package = Package(
    name: "VoxgigStruct",
    products: [
        .library(name: "VoxgigStruct", targets: ["VoxgigStruct"]),
    ],
    dependencies: nil == omniPath ? [] : [
        .package(name: "VoxgigOmni", path: omniPath!),
    ],
    targets: [
        .target(name: "VoxgigStruct", path: "Sources/VoxgigStruct"),
        // Cross-port performance bench (see build/bench/README.md).
        .executableTarget(
            name: "bench",
            dependencies: ["VoxgigStruct"],
            path: "Sources/bench"
        ),
        .testTarget(
            name: "VoxgigStructTests",
            dependencies: nil == omniPath
                ? ["VoxgigStruct"]
                : ["VoxgigStruct", .product(name: "Omni", package: "VoxgigOmni")],
            path: "Tests/VoxgigStructTests"
        ),
    ]
)

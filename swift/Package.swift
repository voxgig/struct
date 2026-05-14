// swift-tools-version:5.9
//
// Voxgig Struct — Swift port of the canonical TypeScript implementation.
// Zero runtime dependencies — see Sources/VoxgigStruct/OrderedDictionary.swift
// for the in-tree insertion-ordered map type.
import PackageDescription

let package = Package(
    name: "VoxgigStruct",
    products: [
        .library(name: "VoxgigStruct", targets: ["VoxgigStruct"]),
    ],
    targets: [
        .target(name: "VoxgigStruct", path: "Sources/VoxgigStruct"),
        .testTarget(
            name: "VoxgigStructTests",
            dependencies: ["VoxgigStruct"],
            path: "Tests/VoxgigStructTests"
        ),
    ]
)

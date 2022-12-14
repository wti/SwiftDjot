// swift-tools-version:5.6

import PackageDescription

let swiftDjot = "SwiftDjot"
let cdj = "Cdjot"

let package = Package(
    name: swiftDjot,
    products: [
        .library( name: cdj, targets: [cdj]),
        .library( name: swiftDjot, targets: [swiftDjot]),
    ],
    targets: [
        .target( name: cdj ),
        .target(
            name: swiftDjot,
            dependencies: [ .target(name: cdj) ]
        ),
        .testTarget(
            name: "\(swiftDjot)Tests",
            dependencies: [ .target(name: swiftDjot) ]
        )
    ]
)

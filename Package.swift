// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Chordflow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Chordflow", targets: ["Chordflow"])],
    dependencies: [
        .package(path: "../swift-app-support"),
    ],
    targets: [
        .executableTarget(
            name: "Chordflow",
            dependencies: [
                .product(name: "AppHelpKit", package: "swift-app-support"),
                .product(name: "MusicTheoryKit", package: "swift-app-support"),
                .product(name: "MIDILiveKit", package: "swift-app-support"),
                .product(name: "MusicTheoryUI", package: "swift-app-support"),
                .product(name: "ABCNotationKit", package: "swift-app-support"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "ChordflowTests", dependencies: ["Chordflow"]),
    ]
)

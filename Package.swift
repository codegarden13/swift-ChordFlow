// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Chordflow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Chordflow", targets: ["Chordflow"])],
    targets: [
        .executableTarget(
            name: "Chordflow",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "ChordflowTests", dependencies: ["Chordflow"]),
    ]
)

// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "M0Spikes",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "PanelSpike"),
        .executableTarget(name: "TranslateSpike"),
        .executableTarget(name: "LayerSpike"),
    ]
)

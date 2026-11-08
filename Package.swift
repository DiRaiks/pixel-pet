// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "PixelPet",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Updates for the signed release build (scripts/bundle.sh embeds the framework).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .target(name: "PetCore"),
        .target(name: "PetSprites", dependencies: ["PetCore"]),
        .target(name: "PetIntegrations", dependencies: ["PetCore"]),
        .executableTarget(name: "PixelPet", dependencies: ["PetCore", "PetSprites", "PetIntegrations",
                                                           .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "PetCoreTests", dependencies: ["PetCore"]),
        .testTarget(name: "PetSpritesTests", dependencies: ["PetSprites"]),
        .testTarget(name: "PetIntegrationsTests", dependencies: ["PetIntegrations"]),
    ]
)

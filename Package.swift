// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "PixelPet",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "PetCore"),
        .target(name: "PetSprites", dependencies: ["PetCore"]),
        .executableTarget(name: "PixelPet", dependencies: ["PetCore", "PetSprites"]),
        .testTarget(name: "PetCoreTests", dependencies: ["PetCore"]),
        .testTarget(name: "PetSpritesTests", dependencies: ["PetSprites"]),
    ]
)

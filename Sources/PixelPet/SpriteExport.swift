import AppKit
import ImageIO
import PetCore
import PetSprites
import UniformTypeIdentifiers

/// Debug aid (`--export-sprites <dir> [skin] [accessory]`): every state as a ×4 PNG strip of its frames,
/// for reviewing the art without running each animation.
enum SpriteExport {
    static func run(to directory: URL, look: Look) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scale = 4, gap = 2
        for state in PetState.allCases {
            let frames = SpriteFactory.frames(for: state, agentCubes: false, look: look)
            let width = frames.count * (32 + gap) * scale, height = 32 * scale
            guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.interpolationQuality = .none
            ctx.setFillColor(CGColor(red: 0.945, green: 0.937, blue: 0.91, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            for (i, frame) in frames.enumerated() {
                guard let image = frame.makeImage() else { continue }
                ctx.draw(image, in: CGRect(x: i * (32 + gap) * scale, y: 0, width: 32 * scale, height: 32 * scale))
            }
            guard let strip = ctx.makeImage(),
                  let out = CGImageDestinationCreateWithURL(directory.appendingPathComponent("\(state.rawValue).png") as CFURL,
                                                            UTType.png.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(out, strip, nil)
            CGImageDestinationFinalize(out)
        }
    }
}

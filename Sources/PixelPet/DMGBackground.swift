import AppKit
import ImageIO
import PetCore
import PetSprites
import UniformTypeIdentifiers

/// `--export-dmg-background <dir>`: the picture behind the icons in the release DMG's window, as
/// `background.png` and `background@2x.png` (scripts/release.sh joins them into one TIFF). Drawn by the same
/// code as the pet, so the cube there never drifts from the app. Kept in Resources/; rerun after changing it.
/// The icon spots (176, 200) and (464, 200) must match scripts/dmg-settings.py.
enum DMGBackground {
    static let width = 640, height = 400

    /// Finder draws the icon names black in light mode and white in dark mode, over the picture. This tone
    /// gives both 4.6:1, so the names read in either; a light or dark backdrop would lose one of them.
    static let backdrop = RGBA(0x746EA9)
    static let cream = RGBA(0xF6F1E7)

    static func run(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scale in [1, 2] {
            guard let image = render(scale: scale) else { continue }
            let name = scale == 1 ? "background.png" : "background@\(scale)x.png"
            guard let out = CGImageDestinationCreateWithURL(directory.appendingPathComponent(name) as CFURL,
                                                            UTType.png.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(out, image, [kCGImagePropertyDPIWidth: 72 * scale,
                                                    kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary)
            if !CGImageDestinationFinalize(out) { NSLog("PixelPet: failed to write \(name)") }
        }
    }

    /// Laid out in points from the top-left, like Finder's icon positions; `top` turns that into
    /// CoreGraphics' bottom-left origin.
    static func render(scale: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width * scale, height: height * scale, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        ctx.interpolationQuality = .none
        func top(_ y: CGFloat, _ h: CGFloat) -> CGFloat { CGFloat(height) - y - h }

        ctx.setFillColor(color(backdrop))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Twinkles: small pixel pluses in the cube's highlight.
        ctx.setFillColor(color(Skin.lavender.highlight, alpha: 0.55))
        let arm: CGFloat = 3
        for (x, y) in [(52, 58), (118, 128), (566, 70), (604, 150), (500, 40), (36, 330), (596, 318), (262, 60), (392, 52)] {
            let x = CGFloat(x), y = CGFloat(y)
            ctx.fill(CGRect(x: x, y: top(y - arm, arm * 3), width: arm, height: arm * 3))
            ctx.fill(CGRect(x: x - arm, y: top(y, arm), width: arm * 3, height: arm))
        }

        // The cube above the arrow, asking: a 32-pixel frame at 4 points a pixel.
        let ask = SpriteFactory.frame(for: .question, index: 3, agentCubes: false, look: .standard, props: [])
        if let image = ask.makeImage() {
            ctx.draw(image, in: CGRect(x: 256, y: top(22, 128), width: 128, height: 128))
        }

        // A dashed pixel arrow from the app to Applications, 6 points a pixel.
        ctx.setFillColor(color(cream))
        let unit: CGFloat = 6, origin = CGPoint(x: 263, y: 179)
        var cells = stride(from: 0, to: 14, by: 3).flatMap { [($0, 3), ($0 + 1, 3)] }
        cells += [(15, 0), (15, 1), (16, 1), (15, 2), (16, 2), (17, 2), (15, 3), (16, 3), (17, 3), (18, 3),
                  (15, 4), (16, 4), (17, 4), (15, 5), (16, 5), (15, 6)]
        for (cx, cy) in cells {
            ctx.fill(CGRect(x: origin.x + CGFloat(cx) * unit, y: top(origin.y + CGFloat(cy) * unit, unit),
                            width: unit, height: unit))
        }

        // The hint under the icons.
        let caption = NSAttributedString(string: "Drag PixelPet into Applications", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor(cgColor: color(cream, alpha: 0.92)) ?? .white,
        ])
        let size = caption.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        caption.draw(at: CGPoint(x: (CGFloat(width) - size.width) / 2, y: top(342, size.height)))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    private static func color(_ c: RGBA, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: alpha)
    }
}

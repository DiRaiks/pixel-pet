import CoreGraphics
import Foundation

public struct RGBA: Equatable, Hashable, Sendable {
    public var r, g, b, a: UInt8

    public init(_ hex: UInt32, alpha: UInt8 = 255) {
        r = UInt8((hex >> 16) & 0xFF)
        g = UInt8((hex >> 8) & 0xFF)
        b = UInt8(hex & 0xFF)
        a = alpha
    }
}

/// A tiny top-left-origin pixel buffer; nil means transparent.
public struct PixelCanvas: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public internal(set) var pixels: [RGBA?]

    public init(width: Int = 32, height: Int = 32) {
        self.width = width
        self.height = height
        pixels = Array(repeating: nil, count: width * height)
    }

    public func pixel(_ x: Int, _ y: Int) -> RGBA? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return pixels[y * width + x]
    }

    public var opaquePixelCount: Int { pixels.lazy.filter { $0 != nil }.count }

    public mutating func set(_ x: Int, _ y: Int, _ color: RGBA) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        pixels[y * width + x] = color
    }

    public mutating func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: RGBA) {
        for yy in y..<(y + h) {
            for xx in x..<(x + w) { set(xx, yy, color) }
        }
    }

    public func makeImage() -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for (i, p) in pixels.enumerated() {
            guard let p else { continue }
            // Premultiplied alpha, as CGImageAlphaInfo.premultipliedLast expects.
            let a = UInt16(p.a)
            bytes[i * 4] = UInt8(UInt16(p.r) * a / 255)
            bytes[i * 4 + 1] = UInt8(UInt16(p.g) * a / 255)
            bytes[i * 4 + 2] = UInt8(UInt16(p.b) * a / 255)
            bytes[i * 4 + 3] = p.a
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}

extension PixelCanvas {
    /// Copies the opaque pixels of `source` with its top-left at (x, y).
    mutating func blit(_ source: PixelCanvas, x: Int, y: Int) {
        for sy in 0..<source.height {
            for sx in 0..<source.width {
                if let color = source.pixel(sx, sy) { set(x + sx, y + sy, color) }
            }
        }
    }

    /// Copies `source` turned clockwise by `degrees`, with the source point (sourceCenterX, sourceCenterY)
    /// landing on (centerX, centerY). Each target pixel takes a vote over 3x3 samples (a light RotSprite):
    /// edges stay crisp without the holes and stray pixels of plain nearest-neighbour rotation.
    public mutating func blitRotated(_ source: PixelCanvas, centerX: Double, centerY: Double, degrees: Double,
                                     sourceCenterX: Double? = nil, sourceCenterY: Double? = nil) {
        let a = -degrees * .pi / 180, c = cos(a), s = sin(a)
        let mx = sourceCenterX ?? Double(source.width) / 2, my = sourceCenterY ?? Double(source.height) / 2
        let reach = Int((Double(source.width * source.width + source.height * source.height)).squareRoot() / 2) + 2
        let offsets = [1.0 / 6, 0.5, 5.0 / 6]
        let cy = Int(centerY.rounded(.down)), cx = Int(centerX.rounded(.down))
        var samples: [RGBA] = []
        samples.reserveCapacity(9)
        for y in cy - reach...cy + reach {
            for x in cx - reach...cx + reach {
                samples.removeAll(keepingCapacity: true)
                for oy in offsets {
                    for ox in offsets {
                        let dx = Double(x) + ox - centerX, dy = Double(y) + oy - centerY
                        let lx = dx * c - dy * s + mx, ly = dx * s + dy * c + my
                        if let color = source.pixel(Int(lx.rounded(.down)), Int(ly.rounded(.down))) { samples.append(color) }
                    }
                }
                // Mostly covered: take the most common color; ties go to the darker (outline-like) one, then by
                // value, so the result never depends on hashing order.
                guard samples.count >= 5 else { continue }
                var best = samples[0], bestCount = 0
                for candidate in samples {
                    let count = samples.reduce(0) { $0 + ($1 == candidate ? 1 : 0) }
                    if count > bestCount || (count == bestCount && darker(candidate, than: best)) {
                        best = candidate
                        bestCount = count
                    }
                }
                set(x, y, best)
            }
        }
    }

    /// Recolors the top `rows` interior rows of the pet's body as "empty": the 5-hour limit used up so far.
    /// The body top is the first row holding outline; only fill and highlight pixels change, so the face stays.
    public func drained(rows: Int, skin: Skin = .lavender) -> PixelCanvas {
        guard rows > 0, let top = (0..<height).first(where: { y in (0..<width).contains { pixel($0, y) == skin.outline } })
        else { return self }
        var out = self
        let body: Set<RGBA> = [skin.fill, skin.highlight, skin.rim]
        for y in (top + 1)...min(top + rows, height - 1) {
            for x in 0..<width where pixel(x, y).map(body.contains) == true {
                out.set(x, y, skin.empty)
            }
        }
        return out
    }
}

private func luminance(_ c: RGBA) -> Int { Int(c.r) * 3 + Int(c.g) * 6 + Int(c.b) }

private func darker(_ a: RGBA, than b: RGBA) -> Bool {
    let la = luminance(a), lb = luminance(b)
    if la != lb { return la < lb }
    return (Int(a.r) << 16 | Int(a.g) << 8 | Int(a.b)) < (Int(b.r) << 16 | Int(b.g) << 8 | Int(b.b))
}

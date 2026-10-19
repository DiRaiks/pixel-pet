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

    mutating func set(_ x: Int, _ y: Int, _ color: RGBA) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        pixels[y * width + x] = color
    }

    mutating func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: RGBA) {
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

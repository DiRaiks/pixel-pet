// Draws Resources/AppIcon.icns from the idle sprite: the cube large on a lavender tile in the tone of the
// installer window, with a few pixel twinkles. Usage:
//   .build/release/PixelPet --export-sprites /tmp/sprites && swift scripts/make-icon.swift /tmp/sprites
//   iconutil -c icns /tmp/sprites/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit
let dir = CommandLine.arguments[1]
let strip = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: "\(dir)/idle.png")))!
// The export paints a backdrop (the corner pixel's color) with the drop shadow darkening it. The first frame
// goes on a clear background without either: the tile is the cube's ground.
let backdrop = strip.colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!
let frame = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128, bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
var minX = 128, minY = 128, maxX = -1, maxY = -1
for y in 0..<128 { for x in 0..<128 {
    let c = strip.colorAt(x: x, y: y)!, rgb = c.usingColorSpace(.deviceRGB)!
    let r = rgb.redComponent / backdrop.redComponent, g = rgb.greenComponent / backdrop.greenComponent
    let b = rgb.blueComponent / backdrop.blueComponent
    if abs(r - g) < 0.02, abs(g - b) < 0.02, r > 0.6 {
        frame.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0), atX: x, y: y)
        continue
    }
    frame.setColor(c, atX: x, y: y)
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
let w = maxX - minX + 1, h = maxY - minY + 1
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255,
            alpha: alpha)
}
func render(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: color(0x8C86C4), ending: color(0x5E5994))!.draw(in: path, angle: -90)
    path.addClip()
    // Twinkles in the cube's highlight; too small to read below 64 pixels.
    if size >= 64 {
        color(0xC9C1FA, 0.7).setFill()
        let u = max(1, round(14 * s))
        for (cx, cy) in [(230.0, 760.0), (790.0, 700.0), (760.0, 250.0)] {
            NSRect(x: cx * s - u / 2, y: cy * s - u * 1.5, width: u, height: u * 3).fill()
            NSRect(x: cx * s - u * 1.5, y: cy * s - u / 2, width: u * 3, height: u).fill()
        }
    }
    // Whole multiples of the sprite's pixels (4 strip pixels each), as large as fits in 64% of the tile;
    // the smallest sizes can't hold a whole multiple and are scaled smoothly instead.
    let fit = 824 * s * 0.64 / (CGFloat(w) / 4)
    let unit = fit >= 1 ? floor(fit) : fit
    NSGraphicsContext.current?.imageInterpolation = fit >= 1 ? .none : .high
    let dw = CGFloat(w) / 4 * unit, dh = CGFloat(h) / 4 * unit
    let dest = NSRect(x: (CGFloat(size) - dw) / 2, y: (CGFloat(size) - dh) / 2 - 6 * s, width: dw, height: dh)
    let src = NSRect(x: minX, y: 128 - maxY - 1, width: w, height: h)
    let image = NSImage(size: NSSize(width: 128, height: 128))
    image.addRepresentation(frame)
    image.draw(in: dest, from: src, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
let set = "\(dir)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base)@2x.png"))
}
try! render(1024).write(to: URL(fileURLWithPath: "\(dir)/preview.png"))
print("frame \(w)x\(h)")

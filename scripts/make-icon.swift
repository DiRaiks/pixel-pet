// Draws Resources/AppIcon.icns from the idle sprite. Usage:
//   .build/release/PixelPet --export-sprites /tmp/sprites && swift scripts/make-icon.swift /tmp/sprites
//   iconutil -c icns /tmp/sprites/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit
let dir = CommandLine.arguments[1]
let strip = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: "\(dir)/idle.png")))!
// First frame on a clear background (the export paints a backdrop: the corner pixel's color).
let backdrop = strip.colorAt(x: 0, y: 0)!
let frame = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128, bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
var minX = 128, minY = 128, maxX = -1, maxY = -1
for y in 0..<128 { for x in 0..<128 {
    let c = strip.colorAt(x: x, y: y)!
    if c == backdrop || c.alphaComponent < 0.5 { frame.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0), atX: x, y: y); continue }
    frame.setColor(c, atX: x, y: y)
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
let w = maxX - minX + 1, h = maxY - minY + 1
func render(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1), ending: NSColor(red: 0.91, green: 0.89, blue: 0.84, alpha: 1))!.draw(in: path, angle: -90)
    NSGraphicsContext.current?.imageInterpolation = .none
    // Whole multiples of the sprite's pixels, as large as fits in 62% of the tile.
    let unit = max(1, floor(824 * s * 0.62 / CGFloat(max(w, h))))
    let dw = CGFloat(w) * unit, dh = CGFloat(h) * unit
    let dest = NSRect(x: (CGFloat(size) - dw) / 2, y: (CGFloat(size) - dh) / 2 - 10 * s, width: dw, height: dh)
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

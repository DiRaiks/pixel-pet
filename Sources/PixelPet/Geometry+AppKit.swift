import AppKit
import PetCore

extension PetPoint {
    init(_ p: NSPoint) { self.init(x: p.x, y: p.y) }
    var ns: NSPoint { NSPoint(x: x, y: y) }
}

extension PetSize {
    init(_ s: NSSize) { self.init(width: s.width, height: s.height) }
}

extension PetRect {
    init(_ r: NSRect) { self.init(x: r.minX, y: r.minY, width: r.width, height: r.height) }
    var ns: NSRect { NSRect(x: x, y: y, width: width, height: height) }
}

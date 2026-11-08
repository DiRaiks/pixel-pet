import Foundation

/// The paperclip: a two-pixel wire bent like a paperclip standing on end, in the color setting's tints,
/// with two round eyes in front of the wire.
///
/// Its lower part fills the usual body box (so desks, props and squashes line up with the cube's), and the
/// top loop rises above it like LM's diamond. The wire is lit from the upper left: the half facing the light
/// is the skin's highlight, the other half its outline, so it reads on light and dark wallpapers alike.
extension PixelCanvas {
    /// Rows the top loop rises above the body box: 60% of its height, at most 8, at least 4, and short of
    /// the rows there are (`headroom`) by one, so a high jump squashes the loop instead of cutting it off
    /// against the top of the canvas.
    static func clipRise(h: Int, headroom: Int) -> Int {
        Int(min(Double(h) * 0.6, 8, Double(max(headroom - 1, 4))).rounded(.down))
    }

    /// Where the face sits: the eyes' top row, half the rise above the box, and the mouth under them.
    static func clipFaceRows(h: Int, top: Int, headroom: Int) -> (eyes: Int, mouth: Int) {
        let eyes = top - clipRise(h: h, headroom: headroom) / 2
        return (eyes, min(eyes + 9, top + h - 5))
    }

    /// The wire's centre line as segments in the box's continuous coordinates (pixel centres at +0.5).
    /// Left to right the strands are: the outer left one (L), the innermost (J), the inner one (I) and the
    /// outer right one (R). The wire runs from R's free end down, round the bottom, up L, over the top loop,
    /// down I, round a smaller bend and up J to its free end.
    ///
    /// Both free ends stop in the box, clear below the eyes: R ends on the right with air above it, which is
    /// what tells a paperclip from a U-magnet. Ending behind the eyes they were hidden.
    private static func clipPath(x0: Double, top: Double, w: Int, h: Int, rise: Int) -> [WireSegment] {
        let yBot = top + Double(h), yTop = top - Double(rise)
        let left = x0 + 3, right = x0 + Double(w) - 3
        let inner = right - 3, innermost = min(inner - 2, left + 3)
        let rBot = (right - left) / 2, rTop = (inner - left) / 2, rIn = (inner - innermost) / 2
        let bend = yBot - 1 - rBot, topBend = yTop + 1 + rTop, innerBend = bend - 1
        let rightEnd = min(top + Double(h) * 0.43, bend), innermostEnd = min(top + Double(h) * 0.36, innerBend)
        return [
            .line(right, rightEnd, right, bend),
            .arc((left + right) / 2, bend, rBot, 0, .pi),
            .line(left, bend, left, topBend),
            .arc((left + inner) / 2, topBend, rTop, .pi, 2 * .pi),
            .line(inner, topBend, inner, innerBend),
            .arc((innermost + inner) / 2, innerBend, rIn, 0, .pi),
            .line(innermost, innerBend, innermost, innermostEnd),
        ]
    }

    mutating func drawClip(_ s: BodyStyle, at m: Int, face: Bool, headroom: Int) {
        let k = s.skin, rise = Self.clipRise(h: s.h, headroom: headroom)
        let path = Self.clipPath(x0: Double(m), top: Double(m), w: s.w, h: s.h, rise: rise)
        for y in (m - rise - 1)...(m + s.h) {
            for x in (m - 1)...(m + s.w) {
                let (distance, nx, ny) = WireSegment.nearest(path, Double(x) + 0.5, Double(y) + 0.5)
                guard distance <= 1 else { continue }
                let lit = -nx - ny > 0
                // The limit drains from the top down, through the loop too (-1: nothing drained).
                let drained = s.drain >= 0 && y - m <= s.drain
                set(x, y, lit ? (drained ? k.empty : k.highlight) : k.outline)
            }
        }
        let cx = m + s.w / 2
        let (eyeTop, _) = Self.clipFaceRows(h: s.h, top: m, headroom: headroom)
        // Headwear wraps the top loop, between the outer left strand and the inner one.
        let loopL = m + 1, loopW = s.w - 6, loopTop = m - rise
        if s.headband {
            // The knot hangs on the left: on the right it would cut into the eye.
            fill(loopL, eyeTop - 1, loopW, 1, Palette.capRed)
            set(loopL - 1, eyeTop - 1, Palette.capRed); set(loopL - 2, eyeTop, Palette.capRed)
        }
        if s.nightcap {
            // Pulled down over the whole loop to just above the eyes; on top of the loop alone it looked
            // like it floated, and its pompom left the canvas. The tip flops to the right.
            fill(loopL - 1, eyeTop - 1, loopW + 1, 1, Palette.white)
            fill(loopL, eyeTop - 2, loopW - 1, 1, Palette.capRed)
            fill(loopL + 1, eyeTop - 3, loopW - 3, 1, Palette.capRed)
            fill(loopL + 2, eyeTop - 4, loopW - 5, 1, Palette.capRed)
            fill(loopL + 4, eyeTop - 5, 3, 1, Palette.capRed)
            set(loopL + 7, eyeTop - 4, Palette.capRed)
            set(loopL + 8, eyeTop - 3, Palette.white); set(loopL + 9, eyeTop - 3, Palette.white)
        }
        if s.headset {
            let g = Palette.accessoryDark, right = m + s.w - 1
            fill(loopL, loopTop - 1, loopW, 1, g)
            set(loopL - 1, loopTop, g); set(loopL + loopW, loopTop, g)
            fill(m, eyeTop + 1, 2, 5, g); fill(right - 1, eyeTop + 1, 2, 5, g)
            // Mic boom from the left cup toward the mouth.
            for (x, y) in [(m + 1, eyeTop + 6), (m + 2, eyeTop + 7), (m + 3, eyeTop + 7)] { set(x, y, g) }
            set(m + 4, eyeTop + 7, Palette.capRed)
        }
        if face { clipFace(s, cx: cx, top: m, headroom: headroom) }
    }

    /// Two round eyes side by side in front of the wire, cheeks under them and a small mouth in the gap
    /// between the inner strands. Glances move the pupils, and a big glance the eyes a pixel too.
    mutating func clipFace(_ s: BodyStyle, cx: Int, top: Int, headroom: Int) {
        let k = s.skin
        let (eyeTop, mouthY) = Self.clipFaceRows(h: s.h, top: top, headroom: headroom)
        let ecx = cx + s.lookX / 2
        let dx = s.lookX.signum(), dy = s.lookY.signum()
        for (side, ex) in [(-1, ecx - 6), (1, ecx)] {
            clipEye(ex, eyeTop, s.eyes, dx: dx, dy: dy, side: side, k)
            if s.brow == .angry {
                // The lid comes down at the inner corner.
                let inner = side < 0 ? ex + 4 : ex + 1, next = side < 0 ? ex + 3 : ex + 2
                set(inner, eyeTop + 1, k.eye); set(next, eyeTop + 1, k.eye); set(inner, eyeTop + 2, k.eye)
            }
        }
        if s.blush > 0 {
            fill(ecx - 6, eyeTop + 7, s.blush, 1, k.blush)
            fill(ecx + 6 - s.blush, eyeTop + 7, s.blush, 1, k.blush)
        }
        mouth(ecx, mouthY, s.mouth, k)
    }

    /// One eye (`side` -1 left, 1 right): a 6×7 ring with cut corners and a white inside; lids are the skin's
    /// fill.
    mutating func clipEye(_ ex: Int, _ ey: Int, _ kind: Eyes, dx: Int, dy: Int, side: Int, _ k: Skin) {
        for y in 0..<7 {
            for x in 0..<6 where !((x == 0 || x == 5) && (y == 0 || y == 6)) {
                set(ex + x, ey + y, x == 0 || x == 5 || y == 0 || y == 6 ? k.outline : Palette.white)
            }
        }
        // Pupils go on white, so they take the darker of the face color and the fill: the night skin's face
        // is light, made for a dark body.
        func weight(_ c: RGBA) -> Int { Int(c.r) * 3 + Int(c.g) * 6 + Int(c.b) }
        let e = weight(k.eye) <= weight(k.fill) ? k.eye : k.fill, lid = k.fill
        let px = ex + 2 + dx, py = ey + 2 + dy
        switch kind {
        case .open:
            fill(px, py, 2, 3, e); set(px, py, k.eyeShine2)
        case .half:
            fill(ex + 1, ey + 1, 4, 2, lid); fill(ex + 1, ey + 3, 4, 1, k.outline); fill(px, ey + 4, 2, 2, e)
        case .blink:
            fill(ex + 1, ey + 1, 4, 4, lid); fill(ex + 1, ey + 5, 4, 1, e)
        case .wide:
            fill(px, py, 2, 2, e)
        case .happy:
            set(ex + 1, ey + 4, e); set(ex + 2, ey + 3, e); set(ex + 3, ey + 3, e); set(ex + 4, ey + 4, e)
        case .closed:
            fill(ex + 1, ey + 1, 4, 5, lid)
            set(ex + 1, ey + 3, e); set(ex + 2, ey + 4, e); set(ex + 3, ey + 4, e); set(ex + 4, ey + 3, e)
        case .worry:
            fill(px, ey + 3, 2, 2, e)
            fill(ex + 1, ey + 1, 4, 1, lid)
        case .cross:
            for i in 0..<4 { set(ex + 1 + i, ey + 1 + i, e); set(ex + 4 - i, ey + 1 + i, e) }
        case .glow:
            fill(ex + 1, ey + 1, 4, 5, Palette.glow)
        case .glowBlink:
            fill(ex + 1, ey + 1, 4, 5, lid); fill(ex + 1, ey + 4, 4, 1, Palette.glow)
        case .squeeze:
            // ">" on the left eye, "<" on the right, like the cube's.
            fill(ex + 1, ey + 1, 4, 5, lid)
            let (o, i) = side < 0 ? (ex + 2, ex + 3) : (ex + 3, ex + 2)
            set(o, ey + 2, e); set(i, ey + 3, e); set(o, ey + 4, e)
        case .spiral:
            for (x, y) in [(1, 1), (2, 1), (3, 1), (4, 1), (4, 2), (4, 3), (4, 4), (3, 4), (2, 4), (1, 4), (1, 3), (2, 2), (3, 2)] {
                set(ex + x, ey + y, e)
            }
        case .down:
            fill(px, ey + 3, 2, 2, e); set(px, ey + 3, k.eyeShine2)
        case .shy:
            fill(ex + 1, ey + 3, 2, 2, e)
        }
    }
}

/// A piece of a wire's centre line: a straight run or an arc (angles in radians, clockwise from +x in screen
/// coordinates, so 0...π is the lower half).
enum WireSegment {
    case line(Double, Double, Double, Double)
    case arc(Double, Double, Double, Double, Double)

    /// The distance from (x, y) to the nearest point of the path, and the offset from that point.
    static func nearest(_ path: [WireSegment], _ x: Double, _ y: Double) -> (Double, Double, Double) {
        var best = (Double.infinity, 0.0, 0.0)
        for segment in path {
            let (qx, qy) = segment.closest(to: x, y)
            let d = hypot(x - qx, y - qy)
            if d < best.0 { best = (d, x - qx, y - qy) }
        }
        return best
    }

    private func closest(to x: Double, _ y: Double) -> (Double, Double) {
        switch self {
        case let .line(x0, y0, x1, y1):
            let vx = x1 - x0, vy = y1 - y0, length = vx * vx + vy * vy
            let t = length == 0 ? 0 : max(0, min(1, ((x - x0) * vx + (y - y0) * vy) / length))
            return (x0 + t * vx, y0 + t * vy)
        case let .arc(cx, cy, r, from, to):
            var angle = atan2(y - cy, x - cx)
            while angle < from { angle += 2 * .pi }
            if angle <= to { return (cx + r * cos(angle), cy + r * sin(angle)) }
            let start = (cx + r * cos(from), cy + r * sin(from)), end = (cx + r * cos(to), cy + r * sin(to))
            return hypot(x - start.0, y - start.1) < hypot(x - end.0, y - end.1) ? start : end
        }
    }
}

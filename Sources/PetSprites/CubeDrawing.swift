/// Drawing primitives ported from docs/prototype/sprites.html (scene, eyes, mouth, props).

enum Eyes { case open, half, blink, wide, happy, closed, worry, cross, glow, glowBlink }
enum Mouth { case none, flat, smile, open, wobble }

struct BodyStyle {
    var w = 16, h = 14, dx = 0, dy = 0, cx = 16, by = 26, ground = 27
    var eyes = Eyes.open, mouth = Mouth.flat, lookX = 0, lookY = 0
    var drain = -1
    var shadow = true
    var fill = Palette.fill, highlight = Palette.highlight, shade = Palette.shade
}

struct BodyFrame { let x0, y0, cx: Int }

/// JavaScript's Math.round: halves round toward +infinity.
func jsRound(_ v: Double) -> Int { Int((v + 0.5).rounded(.down)) }

extension PixelCanvas {
    @discardableResult
    mutating func body(_ s: BodyStyle) -> BodyFrame {
        let cx = s.cx + s.dx, by = s.by + s.dy, x0 = cx - s.w / 2, y0 = by - s.h
        if s.shadow {
            let sw = max(4, s.w - 2 - jsRound(Double(s.ground - 1 - by) / 1.5))
            fill(s.cx + s.dx - sw / 2, s.ground, sw, 1, Palette.shadow)
        }
        for y in 0..<s.h {
            for x in 0..<s.w {
                let edgeX = x == 0 || x == s.w - 1, edgeY = y == 0 || y == s.h - 1
                if edgeX && edgeY { continue }
                let inner = (x == 1 || x == s.w - 2) && (y == 1 || y == s.h - 2)
                let color: RGBA
                if edgeX || edgeY || inner { color = Palette.outline }
                else if y <= s.drain { color = Palette.empty }
                else if y == s.h - 2 { color = s.shade }
                else if (y == 2 && (2...4).contains(x)) || (x == 2 && y == 3) { color = s.highlight }
                else { color = s.fill }
                set(x0 + x, y0 + y, color)
            }
        }
        let ey = y0 + max(3, jsRound(Double(s.h) * 0.3)) + s.lookY
        eyes(cx + s.lookX, ey, s.eyes)
        mouth(cx + s.lookX, ey + 4, s.mouth)
        return BodyFrame(x0: x0, y0: y0, cx: cx)
    }

    mutating func eyes(_ cx: Int, _ ey: Int, _ kind: Eyes) {
        let pair = [cx - 4, cx + 2], wide = [cx - 5, cx + 2]
        let e = Palette.eye
        switch kind {
        case .open: for x in pair { fill(x, ey, 2, 3, e); set(x, ey, Palette.glint) }
        case .half: for x in pair { fill(x, ey + 1, 2, 2, e) }
        case .blink: for x in pair { fill(x, ey + 2, 2, 1, e) }
        case .wide: for x in wide { fill(x, ey - 1, 3, 4, e); set(x, ey - 1, Palette.glint) }
        case .happy: for x in wide { set(x, ey + 2, e); set(x + 1, ey + 1, e); set(x + 2, ey + 2, e) }
        case .closed: for x in wide { set(x, ey + 1, e); set(x + 1, ey + 2, e); set(x + 2, ey + 1, e) }
        case .worry:
            for x in pair { fill(x, ey + 1, 2, 2, e); set(x, ey + 1, Palette.glint) }
            set(pair[0], ey - 1, e); set(pair[0] + 1, ey - 2, e)
            set(pair[1], ey - 2, e); set(pair[1] + 1, ey - 1, e)
        case .cross:
            for x in wide {
                set(x, ey, e); set(x + 2, ey, e); set(x + 1, ey + 1, e); set(x, ey + 2, e); set(x + 2, ey + 2, e)
            }
        case .glow: for x in pair { fill(x, ey, 2, 2, Palette.glow) }
        case .glowBlink: for x in pair { fill(x, ey + 1, 2, 1, Palette.glow) }
        }
    }

    mutating func mouth(_ cx: Int, _ y: Int, _ kind: Mouth) {
        let e = Palette.eye
        switch kind {
        case .none: break
        case .flat: fill(cx - 1, y, 2, 1, e)
        case .smile: set(cx - 2, y, e); fill(cx - 1, y + 1, 2, 1, e); set(cx + 1, y, e)
        case .open: fill(cx - 1, y, 2, 2, e)
        case .wobble: set(cx - 2, y + 1, e); set(cx - 1, y, e); set(cx, y + 1, e); set(cx + 1, y, e)
        }
    }

    /// 3x3 agent block; `spin` walks a lighter pixel around its edge.
    mutating func agentCube(_ x: Int, _ y: Int, _ color: RGBA, spin: Int? = nil) {
        fill(x, y, 3, 3, color)
        guard let spin else { return }
        let ring = [(0, 0), (1, 0), (2, 0), (2, 1), (2, 2), (1, 2), (0, 2), (0, 1)]
        let (rx, ry) = ring[spin % ring.count]
        set(x + rx, y + ry, Palette.tealLight)
    }

    mutating func sparkle(_ x: Int, _ y: Int, _ color: RGBA, big: Bool) {
        set(x, y, color)
        guard big else { return }
        set(x - 1, y, color); set(x + 1, y, color); set(x, y - 1, color); set(x, y + 1, color)
    }

    mutating func zee(_ x: Int, _ y: Int, _ color: RGBA) {
        fill(x, y, 3, 1, color); set(x + 1, y + 1, color); fill(x, y + 2, 3, 1, color)
    }
}

import Foundation

/// Drawing primitives for the cube: body with face, accessories and props.

enum Eyes { case open, half, blink, wide, happy, closed, worry, cross, glow, glowBlink, squeeze, spiral, down, shy }
enum Mouth { case none, flat, smile, open, wobble, yawn, pout, tiny }
enum Brow { case angry }

struct BodyStyle {
    var w = 16, h = 14, dx = 0, dy = 0, cx = 16, by = 26, ground = 27
    var eyes = Eyes.open, mouth = Mouth.flat, lookX = 0, lookY = 0
    var drain = -1
    var shadow = true
    var skin = Skin.lavender
    var accessory = Accessory.none
    var blush = 2
    var brow: Brow?
    /// Highlight drifts down a pixel on the in-breath: breathing without moving the outline.
    var highlightShift = 0
    var nightcap = false
    /// Red sweatband with its knot on the right, for long work.
    var headband = false
    /// A call headset with a mic; it takes the place of a head accessory while it's on.
    var headset = false
    /// Degrees clockwise, around the body's center.
    var rotation = 0.0

    init(look: Look) {
        skin = look.skin
        accessory = look.accessory
    }
}

struct BodyFrame { let x0, y0, cx: Int }

/// JavaScript's Math.round: halves round toward +infinity.
func jsRound(_ v: Double) -> Int { Int((v + 0.5).rounded(.down)) }

extension PixelCanvas {
    /// The body is drawn on its own canvas (with a margin for ears of props) and then copied in,
    /// rotated when asked, so face, blush and accessories turn with it.
    @discardableResult
    mutating func body(_ s: BodyStyle) -> BodyFrame {
        let cx = s.cx + s.dx, by = s.by + s.dy, x0 = cx - s.w / 2, y0 = by - s.h
        if s.shadow {
            let sw = max(4, s.w - 2 - jsRound(Double(s.ground - 1 - by) / 1.5))
            fill(s.cx + s.dx - sw / 2, s.ground, sw, 1, Palette.shadow)
        }
        let m = 5
        var local = PixelCanvas(width: s.w + 2 * m, height: s.h + 2 * m)
        local.drawCube(s, at: m, face: s.rotation == 0)
        if s.rotation == 0 {
            blit(local, x: x0 - m, y: y0 - m)
        } else {
            let centerY = Double(by) - Double(s.h) / 2
            blitRotated(local, centerX: Double(cx), centerY: centerY, degrees: s.rotation,
                        sourceCenterX: Double(m) + Double(s.w) / 2, sourceCenterY: Double(m) + Double(s.h) / 2)
            // A 1-pixel face falls apart when rotated; like hand-drawn spins, it stays upright on the turning body,
            // on the same rows as without rotation (props and blush turn with the body).
            let ey = y0 + max(3, jsRound(Double(s.h) * 0.3)) + s.lookY
            eyes(cx + s.lookX, ey, s.eyes, s.skin)
            mouth(cx + s.lookX, min(ey + 4, by - 4), s.mouth, s.skin)
        }
        return BodyFrame(x0: x0, y0: y0, cx: cx)
    }

    private mutating func drawCube(_ s: BodyStyle, at m: Int, face: Bool) {
        let k = s.skin, w = s.w, h = s.h, hl = s.highlightShift
        for y in 0..<h {
            for x in 0..<w {
                let edgeX = x == 0 || x == w - 1, edgeY = y == 0 || y == h - 1
                if edgeX && edgeY { continue }
                let inner = (x == 1 || x == w - 2) && (y == 1 || y == h - 2)
                let color: RGBA
                if edgeX || edgeY || inner { color = k.outline }
                else if y <= s.drain { color = k.empty }
                else if y == h - 2 { color = k.shade2 }
                else if y == h - 3 { color = k.shade }
                else if x == w - 2 && y > 1 { color = k.rim }
                else if (y == 2 + hl && (2...4).contains(x)) || ((x == 2 || x == 3) && y == 3 + hl) { color = k.highlight }
                else { color = k.fill }
                set(m + x, m + y, color)
            }
        }
        let cx = m + w / 2 + s.lookX
        let ey = m + max(3, jsRound(Double(h) * 0.3)) + s.lookY
        if face {
            eyes(cx, ey, s.eyes, k)
            // On a squashed body the mouth would fall onto (or below) the bottom edge; keep it inside.
            mouth(cx, min(ey + 4, m + h - 4), s.mouth, k)
        }
        if s.blush > 0 {
            fill(cx - 6, ey + 3, s.blush, 1, k.blush)
            fill(cx + 6 - s.blush, ey + 3, s.blush, 1, k.blush)
        }
        if face, s.brow == .angry {
            set(cx - 5, ey - 2, k.eye); set(cx - 4, ey - 1, k.eye)
            set(cx + 4, ey - 2, k.eye); set(cx + 3, ey - 1, k.eye)
        }
        let left = m, right = m + w - 1, top = m
        if s.headband, !s.accessory.isOnHead {
            fill(left + 1, top + 2, w - 2, 1, Palette.capRed)
            set(right + 1, top + 2, Palette.capRed); set(right + 2, top + 3, Palette.capRed)
        }
        if s.nightcap {
            fill(left + 1, top - 1, w - 7, 1, Palette.white)
            fill(left + 3, top - 2, w - 9, 1, Palette.capRed)
            fill(left + 5, top - 3, 3, 1, Palette.capRed)
            set(left + 7, top - 4, Palette.capRed)
            set(left + 8, top - 5, Palette.white); set(left + 9, top - 5, Palette.white)
            return
        }
        if s.headset {
            let g = Palette.accessoryDark
            fill(left + 1, top - 2, w - 2, 1, g)
            set(left, top - 1, g); set(right, top - 1, g)
            fill(left - 1, top + 3, 2, 5, g); fill(right, top + 3, 2, 5, g)
            // Mic boom from the left cup toward the mouth.
            for (x, y) in [(left, top + 8), (left + 1, top + 9), (left + 2, top + 9)] { set(x, y, g) }
            set(left + 3, top + 9, Palette.capRed)
            if s.accessory.isOnHead { return }
        }
        switch s.accessory {
        case .none: break
        case .glasses:
            let g = Palette.accessoryDark
            for x in [cx - 5, cx + 1] {
                fill(x, ey - 1, 4, 1, g); fill(x, ey + 3, 4, 1, g)
                set(x, ey, g); set(x, ey + 1, g); set(x, ey + 2, g)
                set(x + 3, ey, g); set(x + 3, ey + 1, g); set(x + 3, ey + 2, g)
            }
            fill(cx - 1, ey, 2, 1, g)
        case .headphones:
            let g = Palette.accessoryDark
            fill(left + 1, top - 2, w - 2, 1, g)
            set(left, top - 1, g); set(right, top - 1, g)
            fill(left - 1, top + 3, 2, 5, g); fill(right, top + 3, 2, 5, g)
        case .cap:
            fill(left + 3, top - 2, w - 6, 2, Palette.capRed)
            fill(left + 1, top - 1, w - 2, 1, Palette.capRed)
            fill(right - 1, top - 1, 3, 1, Palette.capRed)
        case .beanie:
            // Knit hat pulled over the top edge, ribbed brim, a pompom.
            fill(left + 2, top - 3, w - 4, 1, Palette.beanie)
            fill(left + 1, top - 2, w - 2, 2, Palette.beanie)
            for x in stride(from: left + 1, through: right - 1, by: 2) { set(x, top, Palette.beanieRib) }
            fill(left + 1, top, 1, 1, Palette.beanie)
            fill(cx - 1, top - 5, 2, 2, Palette.beanieRib)
        case .crown:
            fill(cx - 4, top - 2, 8, 2, Palette.crownGold)
            fill(cx - 4, top - 1, 8, 1, Palette.crownShade)
            set(cx - 4, top - 3, Palette.crownGold); set(cx - 1, top - 4, Palette.crownGold)
            set(cx, top - 4, Palette.crownGold); set(cx + 3, top - 3, Palette.crownGold)
            set(cx - 1, top - 2, Palette.capRed); set(cx, top - 2, Palette.capRed)
        case .bow:
            let bx = right - 4
            fill(bx, top - 2, 2, 3, Palette.bowPink); fill(bx + 3, top - 2, 2, 3, Palette.bowPink)
            fill(bx + 2, top - 1, 1, 1, Palette.capRed)
        case .flower:
            // A daisy tucked at the top-left corner: petals round a yellow middle, a leaf below.
            let (fx, fy) = (left + 3, top - 1)
            fill(fx - 1, fy - 2, 3, 5, Palette.petal)
            fill(fx - 2, fy - 1, 5, 3, Palette.petal)
            set(fx, fy, Palette.petalCenter); set(fx, fy - 1, Palette.petalCenter)
            set(fx - 1, fy, Palette.petalCenter); set(fx + 1, fy, Palette.petalCenter)
            set(fx + 3, fy + 1, Palette.teal); set(fx + 4, fy + 2, Palette.teal)
        case .propeller:
            fill(cx - 4, top - 1, 8, 2, Palette.capRed)
            fill(cx - 4, top - 1, 4, 1, Palette.propellerBlue)
            fill(cx, top, 4, 1, Palette.propellerBlue)
            set(cx - 1, top - 2, Palette.lamp); set(cx - 1, top - 3, Palette.lamp)
            fill(cx - 4, top - 4, 3, 1, Palette.crownGold); fill(cx, top - 4, 3, 1, Palette.crownGold)
        case .sunglasses:
            for x in [cx - 5, cx + 1] { fill(x, ey - 1, 4, 3, Palette.lens); set(x + 1, ey - 1, Palette.white) }
            fill(cx - 1, ey - 1, 2, 1, Palette.lens)
            set(left + 1, ey - 1, Palette.lens); set(right - 1, ey - 1, Palette.lens)
        case .scarf:
            fill(left, top + h - 5, w, 2, Palette.scarf)
            for x in stride(from: left + 1, to: right, by: 3) { set(x, top + h - 5, Palette.scarfStripe) }
            fill(right - 3, top + h - 3, 2, 3, Palette.scarf)
            set(right - 3, top + h - 1, Palette.scarfStripe)
        case .mustache:
            // Handlebar: a thick bar under the nose, the ends curling up.
            let my = ey + 3, color = Palette.mustache
            fill(cx - 3, my, 6, 1, color)
            fill(cx - 2, my + 1, 4, 1, color)
            set(cx - 4, my, color); set(cx + 3, my, color)
            set(cx - 5, my - 1, color); set(cx + 4, my - 1, color)
        }
    }

    mutating func eyes(_ cx: Int, _ ey: Int, _ kind: Eyes, _ k: Skin = .lavender) {
        let pair = [cx - 4, cx + 2], wide = [cx - 5, cx + 2]
        let e = k.eye
        switch kind {
        case .open:
            for x in pair { fill(x, ey, 2, 3, e); set(x, ey, k.eyeShine); set(x + 1, ey + 2, k.eyeShine2) }
        case .half: for x in pair { fill(x, ey + 1, 2, 2, e) }
        case .blink: for x in pair { fill(x, ey + 2, 2, 1, e) }
        case .wide: for x in wide { fill(x, ey - 1, 3, 4, e); set(x, ey - 1, k.eyeShine) }
        case .happy: for x in wide { set(x, ey + 2, e); set(x + 1, ey + 1, e); set(x + 2, ey + 2, e) }
        case .closed: for x in wide { set(x, ey + 1, e); set(x + 1, ey + 2, e); set(x + 2, ey + 1, e) }
        case .worry:
            for x in pair { fill(x, ey + 1, 2, 2, e); set(x, ey + 1, k.eyeShine) }
            set(pair[0], ey - 1, e); set(pair[0] + 1, ey - 2, e)
            set(pair[1], ey - 2, e); set(pair[1] + 1, ey - 1, e)
        case .cross:
            for x in wide { set(x, ey, e); set(x + 2, ey, e); set(x + 1, ey + 1, e); set(x, ey + 2, e); set(x + 2, ey + 2, e) }
        case .glow: for x in pair { fill(x, ey, 2, 2, Palette.glow) }
        case .glowBlink: for x in pair { fill(x, ey + 1, 2, 1, Palette.glow) }
        case .squeeze:
            for (i, x) in wide.enumerated() { set(x + (i == 0 ? 0 : 2), ey, e); set(x + 1, ey + 1, e); set(x + (i == 0 ? 0 : 2), ey + 2, e) }
        case .spiral:
            for x in wide {
                fill(x, ey - 1, 3, 1, e); set(x + 2, ey, e); set(x, ey, e); set(x, ey + 1, e); fill(x, ey + 2, 3, 1, e)
                set(x + 1, ey, k.eyeShine)
            }
        case .down: for x in pair { fill(x, ey + 1, 2, 2, e); set(x, ey + 2, k.eyeShine) }
        case .shy: for x in pair { fill(x - 1, ey + 1, 2, 2, e); set(x - 1, ey + 1, k.eyeShine) }
        }
    }

    mutating func mouth(_ cx: Int, _ y: Int, _ kind: Mouth, _ k: Skin = .lavender) {
        let e = k.eye
        switch kind {
        case .none: break
        case .flat: fill(cx - 1, y, 2, 1, e)
        case .smile: set(cx - 2, y, e); fill(cx - 1, y + 1, 2, 1, e); set(cx + 1, y, e)
        case .open: fill(cx - 1, y, 2, 2, e)
        case .wobble: set(cx - 2, y + 1, e); set(cx - 1, y, e); set(cx, y + 1, e); set(cx + 1, y, e)
        case .yawn: fill(cx - 2, y - 1, 4, 4, e); fill(cx - 1, y + 1, 2, 1, k.blush)
        case .pout: fill(cx - 1, y, 2, 2, e)
        case .tiny: set(cx, y, e)
        }
    }

    /// A small mug with its handle on the right; `steam` 0 for none, 1-2 for a wisp that drifts up.
    mutating func mug(_ x: Int, _ y: Int, steam: Int = 0, tea: Bool = false) {
        fill(x, y, 3, 3, Palette.mug)
        fill(x, y + 2, 3, 1, Palette.mugShade)
        fill(x, y, 3, 1, tea ? Palette.tea : Palette.coffee)
        // A tea bag's string and tag over the rim.
        if tea { set(x + 2, y - 1, Palette.mugShade); set(x + 3, y - 1, Palette.white) }
        set(x + 3, y + 1, Palette.mug)
        if steam > 0 { set(x + 1, y - 1 - steam, Palette.steam); set(x + 2 - steam % 2, y - 2 - steam, Palette.steam) }
    }

    /// A little copy of the pet for subagents: 5x4 in the skin's colors with two dot eyes.
    mutating func miniCube(_ x: Int, _ y: Int, _ skin: Skin) {
        fill(x, y, 5, 4, skin.outline)
        fill(x + 1, y + 1, 3, 2, skin.fill)
        set(x + 1, y + 1, skin.eye); set(x + 3, y + 1, skin.eye)
    }

    /// A battery seen from the side: 6x3 with a nub; `level` 0...4 cells filled.
    mutating func battery(_ x: Int, _ y: Int, level: Int, color: RGBA) {
        fill(x, y, 6, 3, Palette.accessoryDark)
        fill(x + 1, y + 1, 4, 1, Palette.mug)
        if level > 0 { fill(x + 1, y + 1, min(4, level), 1, color) }
        set(x + 6, y + 1, Palette.accessoryDark)
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

    mutating func circle(_ cx: Int, _ cy: Int, radius r: Int, _ color: RGBA) {
        for i in 0..<16 {
            let t = Double(i) / 16 * 2 * .pi
            set(cx + jsRound(cos(t) * Double(r)), cy + jsRound(sin(t) * Double(r)), color)
        }
    }
}

import PetCore

extension SpriteFactory {
    /// How far the body slides right to make room for the mic on its left.
    static let listenShift = 6

    /// Perks up (a squash and a little jump, eyes wide), then slides over as the mic comes out.
    static func listenIn(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.eyes = .wide
        switch i {
        case 0: s.w = 17; s.h = 13
        case 1: s.w = 15; s.h = 15; s.dy = -2
        default: s.dx = [2, 4, listenShift][i - 2]; s.lookX = -1
        }
        let b = c.body(s)
        if i >= 2 { listenMic(b, s, out: i - 1, &c) }
    }

    /// Eyes on the mic, mouth shut: the one talking is you. Waves travel in from the left edge.
    static func listening(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.dx = listenShift
        s.lookX = -1
        s.eyes = i == 7 ? .blink : .open
        let b = c.body(s)
        listenMic(b, s, out: 3, &c)
        listenWaves(b, phase: i, &c)
    }

    /// Quiet: no waves, it looks up and three dots come one by one, waiting for more.
    static func listenQuiet(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.dx = listenShift
        s.lookX = -1; s.lookY = -1
        let b = c.body(s)
        listenMic(b, s, out: 3, &c)
        // The dots come one by one over the mic's head: the body sits too far right for room beside it,
        // and over the head they'd meet a hat.
        let head = micHead(b)
        for d in 0..<(i % 4) { c.set(head.x + d * 2, head.y - 2, Palette.keyboard) }
    }

    /// Got it: two happy nods, the mic goes away, back to its spot.
    static func listenOut(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.eyes = .happy
        s.mouth = .smile
        if i < 4 {
            s.dx = listenShift
            s.dy = i % 2 == 0 ? 1 : 0
            s.blush = 3
            if s.dy == 1 { s.w = 17; s.h = 13 }
        } else {
            s.dx = [4, 2, 0][i - 4]
        }
        let b = c.body(s)
        listenMic(b, s, out: i < 4 ? 3 : [2, 1, 0][i - 4], &c)
    }

    /// The mic, held from the bottom-left corner and tilted up and out toward whoever speaks. `out` 0...3:
    /// the handle comes out first, then the head.
    static func listenMic(_ b: BodyFrame, _ s: BodyStyle, out: Int, _ c: inout PixelCanvas) {
        let ink = Palette.keyboard
        let corner = (x: b.x0 - 1, y: b.y0 + s.h - 3)
        for k in 0..<[0, 1, 2, 3][out] {
            c.set(corner.x - k, corner.y - k, ink)
            c.set(corner.x - k, corner.y - k + 1, ink)
        }
        guard out == 3 else { return }
        let head = micHead(b)
        c.pixelMap([
            ".###.",
            "#hgh#",
            "#ghg#",
            "#hgh#",
            ".###.",
        ], x: head.x, y: head.y, colors: ["#": ink, "h": Palette.steam, "g": Palette.keyboardTop])
    }

    static func micHead(_ b: BodyFrame) -> (x: Int, y: Int) { (b.x0 - 7, b.y0 + 4) }

    /// Two ")" fronts travel in from the left edge to the mic's head, a pixel per frame: taller far out,
    /// shorter and lighter as they reach it.
    static func listenWaves(_ b: BodyFrame, phase: Int, _ c: inout PixelCanvas) {
        let head = micHead(b)
        let cy = head.y + 2, span = head.x - 2
        guard span > 0 else { return }
        for k in 0..<2 {
            let x = 1 + (phase + k * 3) % span
            let r = x <= 2 ? 2 : 1
            let color = x >= span ? Palette.tealLight : Palette.note
            c.set(x - 1, cy - r - 1, color)
            for y in (cy - r)...(cy + r) { c.set(x, y, color) }
            c.set(x - 1, cy + r + 1, color)
        }
    }
}

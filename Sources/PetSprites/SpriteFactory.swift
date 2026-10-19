import CoreGraphics
import Foundation
import PetCore

/// Procedural frames for every PetState, ported from docs/prototype/sprites.html.
/// One deliberate difference: shadows with an odd width snap to whole pixels instead of the canvas's half-pixel blur.
/// Replaced by an Aseprite sprite sheet in M8; callers only see canvases and images.
public enum SpriteFactory {
    // [width, height, dy] keyframes: anticipation -> stretch -> airborne -> land squash -> settle.
    static let hop = [(16, 14, 0), (18, 13, 0), (18, 11, 0), (14, 16, -1), (14, 17, -4), (14, 16, -7), (14, 15, -8),
                      (14, 15, -8), (14, 16, -6), (14, 17, -3), (20, 10, 0), (18, 12, 0), (16, 15, 0), (16, 14, 0)]
    static let jump = [(16, 14, 0), (18, 12, 0), (20, 10, 0), (14, 17, -3), (14, 17, -7), (14, 16, -10), (14, 15, -11),
                       (14, 15, -11), (14, 16, -9), (14, 17, -5), (14, 16, -1), (20, 10, 0), (18, 12, 0), (16, 15, 0),
                       (16, 14, 0), (16, 14, 0)]

    public static func frames(for state: PetState) -> [PixelCanvas] {
        (0..<state.frameCount).map { i in
            var c = PixelCanvas()
            draw(state, frame: i, on: &c)
            return c
        }
    }

    /// 18x18 template icon: cube silhouette with the eyes and mouth punched out.
    public static func menuIcon() -> PixelCanvas {
        var c = PixelCanvas(width: 18, height: 18)
        let t = Palette.template
        c.fill(2, 2, 14, 14, t)
        for (x, y) in [(2, 2), (15, 2), (2, 15), (15, 15)] { c.pixels[y * 18 + x] = nil }
        for (x, y, w, h) in [(5, 7, 2, 3), (11, 7, 2, 3), (8, 12, 2, 1)] {
            for yy in y..<(y + h) { for xx in x..<(x + w) { c.pixels[yy * 18 + xx] = nil } }
        }
        return c
    }

    public static func images(for state: PetState) -> [CGImage] {
        frames(for: state).compactMap { $0.makeImage() }
    }

    static func draw(_ state: PetState, frame i: Int, on c: inout PixelCanvas) {
        switch state {
        case .idle: idle(i, &c)
        case .hop: hopFrame(i, &c)
        case .working: working(i, &c)
        case .alert: alert(i, &c)
        case .celebrate: celebrate(i, &c)
        case .sleep: sleep(i, &c)
        case .lowLimit: lowLimit(i, &c)
        case .error: error(i, &c)
        case .peek: peek(i, &c)
        case .dragged: dragged(i, &c)
        case .drop: drop(i, &c)
        case .talk: talk(i, &c)
        }
    }

    static func idle(_ i: Int, _ c: inout PixelCanvas) {
        let breath = (4...8).contains(i) || (16...19).contains(i) ? 1 : 0
        var s = BodyStyle()
        s.h = 14 + breath
        s.eyes = i == 10 || i == 12 ? .half : i == 11 ? .blink : .open
        s.lookX = (18...21).contains(i) ? -1 : 0
        c.body(s)
    }

    static func hopFrame(_ i: Int, _ c: inout PixelCanvas) {
        let (w, h, dy) = hop[i]
        var s = BodyStyle()
        s.w = w; s.h = h; s.dy = dy
        s.eyes = i == 1 || i == 2 ? .half : i == 10 ? .blink : .open
        s.lookY = dy < -2 ? -1 : 0
        s.mouth = dy < 0 ? .open : .flat
        c.body(s)
    }

    static func working(_ i: Int, _ c: inout PixelCanvas) {
        var s = BodyStyle()
        s.cx = 13; s.h = (i / 2) % 2 == 1 ? 13 : 14
        s.eyes = .half; s.lookX = 1; s.lookY = -1
        let b = c.body(s)
        let active = (i / 3) % 4
        for k in 0..<3 { c.set(b.cx - 3 + k * 3, b.y0 - 3 - (k == active ? 1 : 0), Palette.shade) }
        c.agentCube(25, 24, Palette.teal, spin: i)
        c.agentCube(25, 20, Palette.teal, spin: i + 4)
    }

    static func alert(_ i: Int, _ c: inout PixelCanvas) {
        let hops = [0, 0, -1, -2, -3, -2, -1, 0, 0, 0, 0, 0]
        var s = BodyStyle()
        s.cx = 14; s.dy = hops[i]
        s.w = i == 7 ? 18 : 16; s.h = i == 7 ? 12 : 14
        s.eyes = .wide; s.lookX = 1; s.mouth = .open
        let b = c.body(s)
        if i % 6 < 4 {
            c.fill(b.cx - 1, b.y0 - 7, 2, 3, Palette.amber)
            c.fill(b.cx - 1, b.y0 - 3, 2, 1, Palette.amber)
        }
        let cy = 24 - ((i + 6) % 12 < 3 ? 1 : 0)
        c.agentCube(26, cy, Palette.amber)
        if i % 4 < 2 { c.set(27, cy + 1, Palette.amberDark) }
    }

    static func celebrate(_ i: Int, _ c: inout PixelCanvas) {
        let (w, h, dy) = jump[i]
        var s = BodyStyle()
        s.w = w; s.h = h; s.dy = dy
        s.eyes = (3...12).contains(i) ? .happy : .open
        s.mouth = .smile
        c.body(s)
        guard (5...14).contains(i) else { return }
        let q = Double(i - 4)
        let offsets = [(-q - 2, -q / 2), (q + 2, -q / 2), (-q, q / 3 - 6), (q, q / 3 - 6)]
        for (k, (x, y)) in offsets.enumerated() {
            c.sparkle(16 + jsRound(x), 12 + jsRound(y), k % 2 == 1 ? Palette.amber : Palette.teal, big: q < 6)
        }
    }

    static func sleep(_ i: Int, _ c: inout PixelCanvas) {
        let exhale = i < 12 ? 0 : 1
        var s = BodyStyle()
        s.w = 16 + 2 * exhale; s.h = 14 - exhale
        s.eyes = .closed; s.mouth = exhale == 1 ? .open : .none
        c.body(s)
        for offset in [0, 12] {
            let f = (i + offset) % 24
            if f < 16 { c.zee(23 + f / 4, 9 - f / 2, f < 8 ? Palette.shade : Palette.highlight) }
        }
    }

    static func lowLimit(_ i: Int, _ c: inout PixelCanvas) {
        var s = BodyStyle()
        s.w = 14; s.h = 13
        s.dx = i < 6 && i % 2 == 1 ? 1 : 0
        s.eyes = .worry; s.mouth = .wobble; s.drain = 6
        let b = c.body(s)
        let y = b.y0 + 2 + i / 2
        if y < b.y0 + 12 {
            c.set(b.x0 + 14, y, Palette.sweat)
            c.set(b.x0 + 14, y + 1, Palette.sweatDark)
        }
    }

    static func error(_ i: Int, _ c: inout PixelCanvas) {
        let shake = [0, -2, 2, -2, 2, -1, 1, 0, 0, 0, 0, 0]
        var s = BodyStyle()
        s.cx = 14; s.dx = shake[i]
        s.eyes = .cross; s.mouth = .wobble
        if (1...5).contains(i) {
            s.fill = Palette.errorFill; s.highlight = Palette.errorHighlight; s.shade = Palette.errorShade
        }
        c.body(s)
        c.agentCube(26, 24, Palette.errorFill)
        if i % 4 < 2 { c.set(27, 25, Palette.errorDark) }
    }

    static func peek(_ i: Int, _ c: inout PixelCanvas) {
        var by = 6
        if (6...11).contains(i) {
            let t = 1 - Double(i - 5) / 6
            by = 6 + jsRound(10 * (1 - t * t * t))
        } else if (12...21).contains(i) {
            by = 16
        } else if (22...24).contains(i) {
            by = 16 - jsRound(10 * Double(i - 21) / 3)
        }
        var s = BodyStyle()
        s.by = by; s.shadow = false
        s.lookX = (13...16).contains(i) ? -1 : (17...20).contains(i) ? 1 : 0
        s.eyes = i == 21 ? .blink : .open
        c.body(s)
        c.fill(5, 0, 22, 5, Palette.notch)
        c.fill(6, 5, 20, 1, Palette.notch)
        c.fill(0, 0, 5, 2, Palette.menuBar)
        c.fill(27, 0, 5, 2, Palette.menuBar)
        if by <= 8 { c.eyes(16, 1, i == 3 || i == 26 ? .glowBlink : .glow) }
    }

    static func dragged(_ i: Int, _ c: inout PixelCanvas) {
        var s = BodyStyle()
        s.w = 14; s.h = 17; s.by = 23
        s.dx = jsRound(sin(Double(i) / 10 * .pi * 2) * 1.4)
        s.eyes = .wide; s.mouth = .open
        let b = c.body(s)
        let hand = ["1   ", "11  ", "121 ", "1221", "11  "]
        for (y, row) in hand.enumerated() {
            for (x, ch) in row.enumerated() where ch != " " {
                c.set(b.cx + 1 + x, b.y0 - 4 + y, ch == "1" ? Palette.outline : Palette.white)
            }
        }
    }

    static func drop(_ i: Int, _ c: inout PixelCanvas) {
        let keys = [(14, 16, 25), (20, 10, 26), (18, 12, 26), (16, 15, 26), (16, 14, 26), (16, 14, 26)]
        let (w, h, by) = keys[i]
        var s = BodyStyle()
        s.w = w; s.h = h; s.by = by
        s.eyes = i == 1 ? .blink : .open
        s.mouth = i == 0 ? .open : .flat
        c.body(s)
    }

    static func talk(_ i: Int, _ c: inout PixelCanvas) {
        let mouths: [Mouth] = [.open, .flat, .smile, .flat, .open, .flat, .flat, .smile]
        var s = BodyStyle()
        s.cx = 11; s.w = 14; s.lookX = 1
        s.eyes = i == 6 ? .blink : .open
        s.mouth = mouths[i]
        c.body(s)
        c.fill(19, 6, 12, 9, Palette.outline)
        c.fill(20, 7, 10, 7, Palette.white)
        c.set(19, 15, Palette.outline); c.set(18, 16, Palette.outline); c.set(20, 14, Palette.white)
        let first = min(7, (i + 1) * 2), second = max(0, min(5, (i - 2) * 2))
        c.fill(21, 9, first, 1, Palette.shade)
        if second > 0 { c.fill(21, 11, second, 1, Palette.shade) }
    }
}

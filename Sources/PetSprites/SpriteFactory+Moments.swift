import Foundation

/// Moments tied to what agents, limits, the battery and the user's hand are doing.
extension SpriteFactory {
    /// "?" bitmap, 4 wide and 7 tall.
    private static let questionMark = [" ## ", "#  #", "   #", "  # ", " #  ", "    ", " #  "]

    /// An agent asks something: leans to one side and back, eyes up toward a bobbing "?".
    static func question(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        let lean = i % 8 >= 4
        s.dx = lean ? 1 : 0
        s.h = lean ? 13 : 14
        s.lookX = lean ? 2 : 1; s.lookY = -1
        s.eyes = i == 8 ? .blink : .open
        s.mouth = .tiny
        let b = c.body(s)
        let bob = i % 4 < 2 ? 0 : -1
        for (y, row) in questionMark.enumerated() {
            for (x, ch) in row.enumerated() where ch == "#" { c.set(b.cx + 5 + x, b.y0 - 9 + y + bob, Palette.amber) }
        }
    }

    /// The 5-hour window reset: the drained body fills back up from the bottom with sparkles, then a stretch.
    static func refill(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        let stretch = [(16, 14), (15, 15), (14, 16), (16, 14)]
        if i >= 8 { (s.w, s.h) = stretch[i - 8] }
        s.eyes = i < 8 ? .open : .happy
        s.mouth = i < 8 ? .tiny : .smile
        s.lookY = i < 8 ? -1 : 0
        let b = c.body(s)
        if i < 8 { c = c.drained(rows: max(0, 10 - i - i / 2 * 2), skin: look.skin) }
        if (2...9).contains(i) {
            for (k, x) in [b.x0 + 3, b.x0 + 8, b.x0 + 12].enumerated() where (i + k) % 3 == 0 {
                c.sparkle(x, b.y0 - 2 - k % 2, k == 1 ? Palette.amberLight : Palette.tealLight, big: false)
            }
        }
    }

    /// A limit reached: lying flat and spent, a sweat drop, a little clock ticking toward the reset.
    static func exhausted(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.w = 20; s.h = i % 2 == 0 ? 9 : 10
        s.eyes = .closed; s.mouth = .wobble; s.blush = 0
        let b = c.body(s)
        c.set(b.x0 + 1, b.y0 + 3, Palette.sweat)
        // Clock: a ring with one hand going round.
        let (cx, cy) = (b.cx, b.y0 - 6)
        for (dx, dy) in [(-1, -2), (0, -2), (1, -2), (2, -1), (2, 0), (2, 1), (1, 2), (0, 2), (-1, 2), (-2, 1), (-2, 0), (-2, -1)] {
            c.set(cx + dx, cy + dy, look.skin.shade)
        }
        c.set(cx, cy, Palette.accessoryDark)
        let hand = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)][i % 8]
        c.set(cx + hand.0, cy + hand.1, Palette.accessoryDark)
    }

    /// Subagents start: two little copies pop out of the top and land on either side, then poof away to work.
    static func spawn(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.h = i < 2 ? 14 - i : 14
        s.eyes = i < 3 ? .wide : .happy
        s.mouth = i < 3 ? .open : .smile
        let b = c.body(s)
        // Up out of the top, over to the far sides, down onto the floor (y 21 puts their feet on it).
        let arc = [(0, 0), (2, -3), (4, -5), (7, -5), (9, -3), (11, 2), (12, 7), (12, 11)]
        if i < 8 {
            let (dx, dy) = arc[i]
            c.miniCube(b.cx - 3 - dx, b.y0 - 2 + dy, look.skin)
            c.miniCube(b.cx - 2 + dx, b.y0 - 2 + dy, look.skin)
        } else {
            for x in [b.cx - 13, b.cx + 12] { c.sparkle(x, 23, Palette.amberLight, big: i == 8) }
        }
    }

    /// Subagents done: the copies poof back in on either side, hop over and merge with a happy squish.
    static func recall(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        let merged = i >= 6
        (s.w, s.h) = i == 6 ? (18, 12) : (16, 14)
        s.eyes = merged ? .happy : .open
        s.mouth = merged ? .smile : .flat
        s.lookX = i < 3 ? -1 : i < 6 ? 1 : 0
        let b = c.body(s)
        guard !merged else { return }
        if i == 0 { for x in [b.cx - 13, b.cx + 12] { c.sparkle(x, 23, Palette.amberLight, big: true) } }
        let path = [(12, 0), (10, -3), (7, -4), (4, -3), (2, -1), (1, 0)]
        let (dx, dy) = path[i]
        c.miniCube(b.cx - 3 - dx, 21 + dy, look.skin)
        c.miniCube(b.cx - 2 + dx, 21 + dy, look.skin)
    }

    /// Context compaction: squeezed flat like an accordion with fold lines, then springs back.
    static func compact(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        let keys = [(16, 14), (18, 12), (20, 10), (22, 8), (20, 10), (14, 16), (17, 13), (16, 14)]
        let (w, h) = keys[i]
        var s = BodyStyle(look: look)
        s.w = w; s.h = h
        s.eyes = (1...4).contains(i) ? .squeeze : i == 5 ? .wide : .open
        s.mouth = (2...4).contains(i) ? .flat : .tiny
        s.blush = h <= 10 ? 0 : 2
        let b = c.body(s)
        guard (2...4).contains(i) else { return }
        for x in stride(from: b.x0 + 3, to: b.x0 + w - 2, by: 4) where abs(x - b.cx) > 3 {
            c.fill(x, b.y0 + 1, 1, h - 2, look.skin.shade)
        }
    }

    /// Battery low and not charging: droopy, slow blinks, a red battery flashing over the head.
    static func tired(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.h = 13; s.w = 17
        s.eyes = i % 8 == 5 ? .blink : .half
        s.mouth = .flat; s.blush = 0
        s.lookY = 1
        let b = c.body(s)
        c.battery(b.cx + 4, b.y0 - 5, level: i % 4 < 2 ? 1 : 0, color: Palette.batteryRed)
    }

    /// Plugged in: a lightning bolt, the battery filling up, a happy little bounce.
    static func plugIn(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.dy = [0, -1, -2, -1, 0, 0, 0, 0][i]
        s.eyes = i < 2 ? .wide : .happy
        s.mouth = .smile
        s.blush = 3
        let b = c.body(s)
        c.battery(b.cx + 4, b.y0 - 5, level: min(4, i / 2 + 1), color: Palette.batteryGreen)
        if (1...5).contains(i) {
            for (dx, dy) in [(1, -4), (0, -3), (-1, -2), (0, -2), (1, -2), (0, -1), (-1, 0)] {
                c.set(b.cx - 5 + dx, b.y0 - 2 + dy, Palette.amber)
            }
        }
    }

    /// Thrown hard: stretches off the hand, tucks into a ball and turns over in quarter turns (lossless, so
    /// the whole face goes round with it), with swoosh arcs at the corners, and opens up to land (`drop` or a
    /// `splat` follows).
    static func thrown(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        let keys: [(w: Int, h: Int, dy: Int, turns: Int, eyes: Eyes)] = [
            (12, 16, -2, 0, .wide), (14, 14, -4, 0, .squeeze), (14, 14, -5, 1, .squeeze), (14, 14, -5, 2, .squeeze),
            (14, 14, -5, 3, .squeeze), (14, 14, -5, 0, .squeeze), (14, 14, -4, 1, .squeeze), (14, 14, -3, 0, .wide),
        ]
        let k = keys[i]
        var s = BodyStyle(look: look)
        s.w = k.w; s.h = k.h; s.shadow = false
        s.eyes = k.eyes; s.mouth = k.eyes == .wide ? .open : .flat; s.blush = 0
        // A 14x14 ball centered exactly on the canvas (9...22 both ways), so quarter turns keep it in place;
        // the height in the air is added after turning.
        s.cx = 16; s.by = 23 - (k.h - 14) / 2
        var ball = PixelCanvas()
        ball.body(s)
        c.blit(ball.rotatedQuarter(k.turns), x: 0, y: k.dy)
        c.fill(13, 27, 6, 1, Palette.shadow)
        guard (2...6).contains(i) else { return }
        // Swoosh arcs trailing two opposite corners, turning with the ball.
        let arcs = [[(22, 8), (23, 9), (24, 11)], [(8, 22), (7, 21), (6, 19)]]
        for arc in arcs {
            var swoosh = PixelCanvas()
            for (x, y) in arc { swoosh.set(x, y, look.skin.highlight) }
            c.blit(swoosh.rotatedQuarter(i), x: 0, y: 0)
        }
    }

    /// Thrown into the right side of the screen (the window sits against it, so column 31 is the edge):
    /// flattened against it with eyes squeezed, slides down to the floor, peels off and shakes it off.
    /// The left side is this, mirrored.
    static func splat(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        let keys: [(w: Int, h: Int, cx: Int, by: Int, eyes: Eyes)] = [
            (11, 17, 26, 23, .squeeze), (10, 18, 27, 23, .squeeze), (10, 18, 27, 23, .squeeze), (10, 18, 27, 24, .squeeze),
            (10, 18, 27, 26, .squeeze), (13, 15, 25, 26, .wide), (17, 12, 23, 26, .wide), (15, 15, 21, 26, .cross),
            (16, 13, 19, 26, .cross), (16, 14, 17, 26, .open),
        ]
        let k = keys[i]
        var s = BodyStyle(look: look)
        s.w = k.w; s.h = k.h; s.cx = k.cx; s.by = k.by
        s.eyes = k.eyes; s.mouth = i < 5 ? .wobble : .open; s.blush = 0
        let b = c.body(s)
        // A few impact specks on the wall side while it hits.
        if i < 2 {
            for (dx, dy) in [(0, -2), (-1, 4), (0, 9)] { c.set(31 + dx, b.y0 + dy, Palette.white) }
        }
    }

    /// Shaken while dragged: lands with spiral eyes, sways, stars circling (the error's dizzy, without the red).
    static func dizzy(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        let squash = i < 2
        s.w = squash ? 18 : 16; s.h = squash ? 12 : 14
        s.dx = [0, 0, -1, 0, 1, 0, -1, 0, 1, 0, -1, 0, 0, 0][i]
        s.eyes = i < 12 ? .spiral : .half
        s.mouth = .wobble; s.blush = 0
        let b = c.body(s)
        guard i < 12 else { return }
        for n in 0..<3 {
            let t = (Double(i) / 6 + Double(n) / 3) * 2 * .pi
            let x = b.cx + jsRound(cos(t) * 5), y = b.y0 - 3 + jsRound(sin(t) * 2)
            c.sparkle(x, y, n % 2 == 1 ? Palette.amber : Palette.amberLight, big: true)
        }
    }
}

extension SpriteFactory {
    /// A hookah break: the pet sits a little to the left, the hookah on its right, clear of the Claude column.
    /// A long draw with eyes closed, the coal glowing and the water bubbling, cheeks puffed, then the smoke:
    /// two rings drifting up, or (`cloud`) one big cloud the pet disappears into for a moment.
    static func hookah(_ i: Int, _ look: Look, _ c: inout PixelCanvas, cloud: Bool = false) {
        let drawing = (1...3).contains(i), holding = i == 4 || i == 5
        var s = BodyStyle(look: look)
        s.cx = 12
        s.w = holding ? 17 : 16
        s.eyes = drawing || holding ? .closed : i >= 14 ? .happy : .half
        s.mouth = holding ? .pout : (6...9).contains(i) ? .open : i >= 14 ? .smile : .flat
        s.blush = holding ? 3 : 2
        let b = c.body(s)
        // Vase with water, stem, tray, clay bowl and its coal.
        c.fill(21, 20, 5, 6, Palette.hookahGlass)
        c.fill(22, 26, 3, 1, Palette.hookahGlass)
        c.fill(21, 23, 5, 3, Palette.hookahWater)
        if drawing { c.set(22 + i % 3, 22 - i % 2, Palette.white); c.set(23, 24, Palette.white) }
        c.fill(23, 10, 1, 10, Palette.lamp)
        c.fill(21, 12, 5, 1, Palette.lamp)
        c.fill(22, 8, 3, 2, Palette.hookahClay)
        c.set(23, 7, drawing ? Palette.amber : Palette.coal)
        if drawing { c.set(22, 7, Palette.amberLight); c.set(24, 7, Palette.amberLight) }
        // Hose from the stem round to the mouth.
        for (x, y) in [(21, 15), (20, 17), (20, 19), (19, 21), (18, 21)] { c.set(x, y, Palette.accessoryDark) }
        if i < 12 { c.set(b.cx + 5, min(b.y0 + 8, 25), Palette.accessoryDark) }
        if cloud { bigCloud(&c, b, i) } else { smokeRings(&c, b, i) }
    }

    /// One ring, then a second behind it, growing as they rise.
    private static func smokeRings(_ c: inout PixelCanvas, _ b: BodyFrame, _ i: Int) {
        for (start, dx) in [(6, 0), (9, -3)] where i >= start {
            let k = i - start
            guard k < 7 else { continue }
            let r = 1 + k / 3
            let (rx, ry) = (b.cx - 1 + dx - k / 2, b.y0 + 4 - k * 2)
            for (ox, oy) in [(-r, 0), (r, 0), (0, -r), (0, r), (-r + 1, -r + 1), (r - 1, -r + 1), (-r + 1, r - 1), (r - 1, r - 1)] {
                c.blend(rx + ox, ry + oy, Palette.smoke)
            }
        }
    }

    /// One big cloud that swallows the pet for a moment, then thins out and lets it peek through.
    private static func bigCloud(_ c: inout PixelCanvas, _ b: BodyFrame, _ i: Int) {
        guard (6...13).contains(i) else { return }
        let k = i - 6
        let grow = min(k, 3), thin = max(0, k - 4)
        let w = 10 + grow * 3 - thin * 2, h = 7 + grow * 2 - thin * 2
        let x = b.cx - w / 2 - 1, y = b.y0 + 2 - grow * 2
        guard w > 2, h > 1 else { return }
        c.fillBlend(x, y, w, h, (2...5).contains(k) ? Palette.smokeDense : Palette.smoke)
        c.fillBlend(x + 2, y - 2, w - 4, 2, Palette.smoke)
    }
}

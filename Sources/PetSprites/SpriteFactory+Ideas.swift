import PetCore

/// Animations under review: waving for attention, a rocket launch, being petted, a sneeze; tool icons above
/// the keyboard and holiday props on the floor.
extension PixelCanvas {
    /// An arm as a mitten: three pixels wide per row, outlined, capped at the top; `rows` go top to bottom.
    mutating func mitten(_ rows: [(x: Int, y: Int)], _ k: Skin) {
        guard let first = rows.first else { return }
        fill(first.x, first.y - 1, 3, 1, k.outline)
        for (x, y) in rows { set(x - 1, y, k.outline); set(x + 3, y, k.outline) }
        for (n, (x, y)) in rows.enumerated() {
            // Steps between leaning rows need the outline closed where the arm shifts.
            if n > 0, rows[n - 1].x != x { set(rows[n - 1].x + 3, y, k.outline); set(x - 1, y - 1, k.outline) }
            fill(x, y, 3, 1, k.fill)
        }
        set(first.x, first.y, k.highlight)
    }

    /// A round puff of mist with a grey edge; `r` 1 or 2.
    mutating func puff(_ x: Int, _ y: Int, _ r: Int) {
        for dy in -r...r {
            for dx in -r...r where dx * dx + dy * dy <= r * r + (r > 1 ? 1 : 0) {
                let edge = dx * dx + dy * dy >= r * r
                set(x + dx, y + dy, edge ? Palette.keyboardTop : Palette.menuBar)
            }
        }
    }
}

extension SpriteFactory {
    /// Milliseconds from the start of a state to frame `i`, in `step`s: props animate by the clock, not the beat.
    static func tick(_ state: PetState, _ i: Int, step: Double) -> Int {
        Int(state.durations.prefix(i).reduce(0, +) * 1000 / step)
    }

    /// States that stand on the desk floor, where a holiday prop can stand beside the pet: not at home, not in
    /// the air or against a wall.
    public static func showsFloorProps(_ state: PetState) -> Bool {
        switch state {
        case .burrowed, .peek, .peekHold, .dive, .touchKeyHome, .dragged, .drop, .thrown, .splatLeft, .splatRight,
             .launch:
            false
        default: true
        }
    }

    static func overlays(_ state: PetState, _ i: Int, _ props: WorkProps, _ c: inout PixelCanvas) {
        if state.isAtDesk {
            if props.contains(.toolRun) { terminalIcon(tick(state, i, step: 500), &c) }
            if props.contains(.toolSearch) { magnifierIcon(tick(state, i, step: 220), &c) }
            if props.contains(.toolRead) { bookIcon(tick(state, i, step: 200), &c) }
            if props.contains(.toolEdit) { pencilIcon(tick(state, i, step: 160), &c) }
        }
        guard showsFloorProps(state) else { return }
        if props.contains(.pumpkin) { pumpkin(tick(state, i, step: 240), &c) }
        if props.contains(.fir) { fir(tick(state, i, step: 300), &c) }
    }

    // MARK: Tool icons, in a thought bubble up and to the left of the head, clear of LM's diamond and above
    // the Codex blocks (only a 5+ overflow mark reaches row 8). The bubble keeps them readable on light and
    // dark wallpapers alike.

    /// A white bubble with a dark outline over x 1...10, y 1...8, and a two-dot tail toward the head.
    static func toolBubble(_ c: inout PixelCanvas) {
        let ink = Palette.keyboard
        c.fill(2, 1, 8, 1, ink); c.fill(2, 8, 8, 1, ink)
        c.fill(1, 2, 1, 6, ink); c.fill(10, 2, 1, 6, ink)
        c.fill(2, 2, 8, 6, Palette.white)
        c.set(11, 9, ink); c.set(12, 10, ink)
    }

    /// A terminal: a dark screen with a green prompt and a blinking cursor.
    static func terminalIcon(_ t: Int, _ c: inout PixelCanvas) {
        toolBubble(&c)
        c.fill(3, 3, 6, 4, Palette.terminal)
        for (x, y) in [(4, 4), (5, 5), (4, 6)] { c.set(x, y, Palette.prompt) }
        if t % 2 == 0 { c.set(7, 6, Palette.white) }
    }

    /// A magnifying glass sweeping left and right.
    static func magnifierIcon(_ t: Int, _ c: inout PixelCanvas) {
        toolBubble(&c)
        let x = 2 + [0, 1, 2, 1][t % 4], y = 2
        for (dx, dy) in [(1, 0), (2, 0), (0, 1), (3, 1), (0, 2), (3, 2), (1, 3), (2, 3)] {
            c.set(x + dx, y + dy, Palette.keyboard)
        }
        c.fill(x + 1, y + 1, 2, 2, Palette.water)
        c.set(x + 1, y + 1, Palette.waterLight)
        c.set(x + 3, y + 4, Palette.amberDark); c.set(x + 4, y + 5, Palette.amberDark)
    }

    /// Reading: the bubble is a page of text, and a teal highlight runs along the lines like an
    /// eye following them.
    static func bookIcon(_ t: Int, _ c: inout PixelCanvas) {
        toolBubble(&c)
        let ink = Palette.terminalBar
        let lines: [(y: Int, from: Int, to: Int, gap: Int)] = [(3, 3, 8, 6), (5, 3, 8, 5), (7, 3, 6, 9)]
        for l in lines {
            for x in l.from...l.to where x != l.gap { c.set(x, l.y, ink) }
        }
        let line = lines[(t / 3) % lines.count], step = t % 3
        let x = min(line.from + step * 2, line.to - 1)
        c.fill(x, line.y, 2, 1, Palette.cover)
    }

    /// A pencil writing a wavy line that grows and starts over.
    static func pencilIcon(_ t: Int, _ c: inout PixelCanvas) {
        toolBubble(&c)
        let len = 1 + t % 4, base = 7
        for k in 0..<len { c.set(2 + k, base - (k % 2), Palette.terminalBar) }
        let px = 2 + len, py = base - 1 - (len % 2)
        c.set(px, py, Palette.terminal)
        for k in 1...3 where py - k >= 2 {
            c.set(px + k, py - k, Palette.pencil)
            if px + k - 1 > px { c.set(px + k - 1, py - k, Palette.pencilShade) }
        }
        if py - 4 >= 2, px + 4 <= 9 { c.set(px + 4, py - 4, Palette.eraser) }
    }

    // MARK: Holiday props, on the floor in front of the pet's left corner.

    /// A jack-o'-lantern with a flickering candle inside.
    static func pumpkin(_ t: Int, _ c: inout PixelCanvas) {
        let x = 5, y = 22
        let glow = [0, 0, 1, 0, 1, 1, 0][t % 7] == 0 ? Palette.candle : Palette.candleDim
        c.set(x + 3, y - 1, Palette.stem); c.set(x + 2, y, Palette.stem)
        c.fill(x + 1, y + 1, 4, 1, Palette.pumpkin)
        c.fill(x, y + 2, 6, 2, Palette.pumpkin)
        c.fill(x + 1, y + 4, 4, 1, Palette.pumpkinDark)
        for dy in 2...3 { c.set(x, y + dy, Palette.pumpkinDark); c.set(x + 5, y + dy, Palette.pumpkinDark) }
        c.set(x + 3, y + 1, Palette.pumpkinDark)
        c.set(x + 1, y + 2, glow); c.set(x + 4, y + 2, glow)
        c.fill(x + 1, y + 3, 4, 1, glow)
        c.set(x + 2, y + 3, Palette.pumpkin)
    }

    /// A little fir with a star and blinking lights.
    static func fir(_ t: Int, _ c: inout PixelCanvas) {
        let x = 5, y = 19
        c.set(x + 2, y, Palette.candle)
        c.set(x + 2, y + 1, Palette.fir)
        c.fill(x + 1, y + 2, 3, 1, Palette.fir)
        c.fill(x + 1, y + 3, 3, 1, Palette.firDark)
        c.fill(x, y + 4, 5, 1, Palette.fir)
        c.fill(x, y + 5, 5, 1, Palette.firDark)
        c.fill(x + 1, y + 6, 3, 1, Palette.fir)
        c.set(x + 2, y + 7, Palette.trunk)
        let colors = [Palette.rocketRed, Palette.candle, Palette.tealLight, Palette.heartLight]
        for (k, (dx, dy)) in [(1, 2), (3, 3), (0, 4), (2, 5), (4, 4), (3, 6)].enumerated() {
            c.set(x + dx, y + dy, colors[(k + t) % colors.count])
        }
    }

    // MARK: Moments.

    /// "Hey, over here!": a hop, then a raised arm waving side to side with a "!" by the head, and a small
    /// hop back down. Played every ~45 s while an agent has been waiting on you for over a minute.
    static func wave(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        let dys = [0, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -2, -1, 0, 0]
        var s = BodyStyle(look: look)
        s.cx = 13; s.dy = dys[i]
        if i == 0 || i == 14 { s.w = 17; s.h = 13 }
        s.eyes = (2...9).contains(i) && i % 2 == 1 ? .happy : .wide
        s.mouth = .open
        s.blush = 2
        let b = c.body(s)
        // Arm: a little mitten, straight up (A) or leaning out (B), off the right side of the body.
        let pose = (2...10).contains(i) ? (i % 2 == 0 ? 2 : 1) : (i == 1 || i == 11 ? 1 : 0)
        if pose > 0 {
            let side = b.x0 + s.w, top = b.y0 - 1, bottom = b.y0 + 5
            let rows = (top...bottom).map { y in (x: side + (pose == 2 ? (bottom - y) / 3 : 0), y: y) }
            c.mitten(rows, look.skin)
            if pose == 2 {
                let tip = rows[0]
                // Swing marks arcing over the mitten.
                c.set(tip.x + 1, tip.y - 3, Palette.steam); c.set(tip.x + 2, tip.y - 3, Palette.steam)
                c.set(tip.x + 3, tip.y - 2, Palette.steam)
            }
        }
        if (2...10).contains(i), i % 4 < 3 {
            // The arm takes the right side; LM's "!" goes left of his diamond.
            let x = look.figure == .lidman ? b.cx - 8 : b.cx - 1
            c.fill(x, b.y0 - 7, 2, 3, Palette.amber)
            c.fill(x, b.y0 - 3, 2, 1, Palette.amber)
        }
    }

    /// `git push` went through: a rocket on the floor shakes, lights up and takes off in a trail of smoke,
    /// pops like a firework up top, and the pet cheers with a hop.
    static func launch(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        let hops = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -3, -2, 0, 0, 0]
        var s = BodyStyle(look: look)
        s.cx = 19; s.dy = hops[i]
        s.lookX = i < 17 ? -1 : 0
        s.lookY = (8...16).contains(i) ? -1 : 0
        s.eyes = i >= 17 ? .happy : (2...7).contains(i) ? .wide : .open
        s.mouth = i >= 17 ? .smile : (6...16).contains(i) ? .open : .flat
        s.blush = i >= 17 ? 2 : 0
        if i == 19 { s.h = 12 }
        c.body(s)
        // Smoke left on the floor, spreading and thinning out.
        if (6...16).contains(i) {
            let spread = min(i - 6, 4)
            c.fill(5, 26, 5 + spread, 1, Palette.steam)
            if i >= 8, i <= 13 { c.puff(6, 25, 1); c.puff(9, 25, 1) }
        }
        let lift = [0, 0, 0, 0, 0, 0, 0, 2, 5, 9, 14, 20, 27, 35]
        if i < lift.count, i < 13 {
            let shake = (2...6).contains(i) ? (i % 2 == 0 ? -1 : 1) : 0
            let x = 6 + shake, y = 19 - lift[i]
            rocket(x, y, flame: i >= 6 ? 3 : (2...5).contains(i) ? 1 : 0, &c)
            // Smoke puffs along the way up.
            if i >= 9 { for k in 1...2 { c.set(x + 2 + (k % 2 == 0 ? -1 : 1), y + 9 + 3 * k, Palette.steam) } }
        }
        // The pop up top.
        if (13...16).contains(i) {
            let r = i - 11, (fx, fy) = (9, 4)
            if r < 4 { c.set(fx, fy, Palette.white) }
            for (dx, dy) in [(r, 0), (-r, 0), (0, r), (0, -r)] { c.set(fx + dx, fy + dy, r < 4 ? Palette.amber : Palette.amberLight) }
            let d = r - 1
            for (dx, dy) in [(d, d), (-d, d), (d, -d), (-d, -d)] { c.set(fx + dx, fy + dy, r < 4 ? Palette.heart : Palette.heartLight) }
        }
    }

    static func rocket(_ x: Int, _ y: Int, flame: Int, _ c: inout PixelCanvas) {
        c.set(x + 2, y, Palette.rocketRed)
        c.fill(x + 1, y + 1, 3, 1, Palette.rocketRed)
        c.fill(x + 1, y + 2, 3, 4, Palette.rocket)
        for dy in 2...5 { c.set(x + 3, y + dy, Palette.rocketShade) }
        c.set(x + 2, y + 3, Palette.cover)
        c.set(x, y + 5, Palette.rocketRed); c.set(x + 4, y + 5, Palette.rocketRed)
        c.set(x, y + 6, Palette.rocketRed); c.set(x + 4, y + 6, Palette.rocketRed)
        c.fill(x + 1, y + 6, 3, 1, Palette.rocketShade)
        c.set(x + 2, y + 7, Palette.keyboard)
        if flame >= 1 { c.set(x + 2, y + 8, Palette.flame) }
        if flame >= 3 {
            c.set(x + 1, y + 8, Palette.amber); c.set(x + 3, y + 8, Palette.amber)
            c.set(x + 2, y + 9, Palette.amber); c.set(x + 2, y + 10, Palette.amberLight)
        }
    }

    /// Being petted (the cursor rubbed back and forth over it): eyes shut happily, a slow sway, two hearts
    /// floating up on either side.
    static func purr(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        let sway = [0, -1, -1, 0, 1, 1, 0, -1, -1, 0, 1, 1, 0, 0]
        var s = BodyStyle(look: look)
        s.dx = sway[i]
        if i % 3 == 1 { s.w = 17; s.h = 13 }
        s.eyes = i == 0 || i == 13 ? .open : .happy
        s.mouth = .smile
        s.blush = i == 0 ? 2 : 3
        c.body(s)
        if (2...11).contains(i) { heart(22 + (i % 4 < 2 ? 0 : -1), 11 - (i - 2), faded: i >= 10, &c) }
        if (5...13).contains(i) { heart(5 + (i % 4 < 2 ? 0 : 1), 10 - (i - 5), faded: i >= 12, &c) }
    }

    static func heart(_ x: Int, _ y: Int, faded: Bool, _ c: inout PixelCanvas) {
        let k = faded ? Palette.heartLight : Palette.heart
        c.set(x + 1, y, k); c.set(x + 3, y, k)
        c.fill(x, y + 1, 5, 1, k)
        c.fill(x + 1, y + 2, 3, 1, k)
        c.set(x + 2, y + 3, k)
        if !faded { c.set(x + 1, y + 1, Palette.heartLight) }
    }

    /// A sneeze: twitch, a long breath in with the head tipping back, a big "choo" off to the side (mist for
    /// the cube, water for LM), a head shake and a sniff.
    static func sneeze(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        let keys: [(w: Int, h: Int, dx: Int, eyes: Eyes, mouth: Mouth, lookY: Int)] = [
            (16, 14, 0, .open, .flat, 0), (16, 14, 0, .half, .tiny, 0), (15, 15, 0, .half, .open, -1),
            (15, 16, 0, .closed, .open, -1), (15, 16, 0, .closed, .open, -1), (18, 12, -1, .squeeze, .open, 0),
            (17, 13, -1, .squeeze, .open, 0), (16, 14, 0, .squeeze, .flat, 0), (16, 14, -1, .squeeze, .flat, 0),
            (16, 14, 1, .squeeze, .flat, 0), (16, 14, 0, .blink, .flat, 0), (16, 14, 0, .half, .tiny, 0),
            (16, 14, 0, .open, .flat, 0), (16, 14, 0, .open, .smile, 0),
        ]
        let k = keys[i]
        var s = BodyStyle(look: look)
        s.w = k.w; s.h = k.h; s.dx = k.dx; s.eyes = k.eyes; s.mouth = k.mouth; s.lookY = k.lookY
        s.lookX = (5...7).contains(i) ? 1 : 0
        s.blush = 0
        c.body(s)
        if look.figure == .lidman {
            // LM sneezes water: a fan of drops.
            let drops: [Int: [(Int, Int)]] = [
                5: [(24, 18), (25, 20), (24, 22), (26, 22)],
                6: [(25, 16), (26, 19), (25, 21), (26, 23), (24, 24)],
                7: [(26, 15), (26, 19), (25, 23), (24, 26)],
            ]
            for (x, y) in drops[i] ?? [] { c.fill(x, y, 1, 2, Palette.water) }
        } else {
            switch i {
            case 5: c.puff(24, 20, 2)
            case 6: c.puff(24, 19, 2); c.puff(25, 23, 1)
            case 7: c.puff(25, 18, 1); c.set(26, 22, Palette.keyboardTop); c.set(24, 23, Palette.keyboardTop)
            default: break
            }
        }
    }
}

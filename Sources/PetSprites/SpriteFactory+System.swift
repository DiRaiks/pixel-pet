import PetCore

/// The Mac around the pet (under review): headphones, music, the mic or camera in use, heat, low power,
/// the network, a full battery, screenshots and the system theme.
extension PixelCanvas {
    /// Over-ear headphones: a dark band over the head (over LM's diamond) and a cup on each side.
    /// `dy` lifts them (putting them on and taking them off).
    mutating func headphones(x0: Int, y0: Int, w: Int, h: Int, figure: Figure, skin: Skin, dy: Int = 0) {
        let band = Palette.accessoryDark
        let left = x0 - 1, right = x0 + w
        let cupTop = y0 + h / 3 + dy
        if figure == .lidman {
            // The band arcs high enough to clear the diamond.
            let top = y0 - 9 + dy
            for y in (top + 4)...(cupTop - 1) { set(left, y, band); set(right, y, band) }
            for k in 0..<4 { set(left + k + 1, top + 3 - k, band); set(right - k - 1, top + 3 - k, band) }
            fill(left + 5, top, right - left - 9, 1, band)
        } else {
            // An arch a little above the head, rounded at the corners.
            for y in (y0 - 1 + dy)...(cupTop - 1) { set(left, y, band); set(right, y, band) }
            set(left + 1, y0 - 2 + dy, band); set(right - 1, y0 - 2 + dy, band)
            fill(left + 2, y0 - 3 + dy, right - left - 3, 1, band)
        }
        for x in [left - 1, right - 1] {
            fill(x, cupTop, 3, 6, band)
            fill(x + 1, cupTop + 1, 1, 4, Palette.cushion)
        }
        _ = skin
    }

    /// A striped party cone with a pompom, standing on `top` (the head; LM's diamond tip gets a small one).
    mutating func partyHat(cx: Int, top: Int, small: Bool = false) {
        let rows = small ? 5 : 7
        let outline = Palette.keyboard
        for k in 0..<rows {
            // Widens one pixel a row, alternating sides, so it stays centered on the head.
            let w = k + 1, x = cx - k / 2 - (k % 2 == 1 ? 1 : 0)
            let y = top - rows + k
            fill(x, y, w, 1, (k / 2) % 2 == 0 ? Palette.hatStripe : Palette.hatBase)
            set(x - 1, y, outline); set(x + w, y, outline)
        }
        fill(cx - 1, top - rows - 2, 2, 2, Palette.sun)
    }

    /// Draws a pixel map with its own colors; characters not in `colors` are left alone.
    mutating func pixelMap(_ rows: [String], x: Int, y: Int, colors: [Character: RGBA]) {
        for (dy, row) in rows.enumerated() {
            for (dx, ch) in row.enumerated() {
                if let color = colors[ch] { set(x + dx, y + dy, color) }
            }
        }
    }

    /// Emoji colors for the hand-drawn ✌️.
    static let emojiColors: [Character: RGBA] = [
        "o": RGBA(0xC27A12), "Y": RGBA(0xFFCB3D), "y": RGBA(0xF5A623), "e": RGBA(0x5B3A1A),
        "h": RGBA(0xF2A93B), "H": RGBA(0xFFD56B),
    ]

    /// ✌️ drawn by hand at 9×11: a yellow hand, two fingers up in a V.
    mutating func peaceEmoji(x: Int, y: Int) {
        pixelMap([
            "oo.....oo",
            "oHo...oHo",
            "oHo...oHo",
            ".oHo.oHo.",
            ".oHo.oHo.",
            "..oHoHo..",
            ".ooHHHHo.",
            "oHoHHHHHo",
            "oHHoHHHHo",
            ".oHHHHHo.",
            "..ooooo..",
        ], x: x, y: y, colors: Self.emojiColors)
    }

    /// A microphone with a red recording dot, in the tool bubble.
    mutating func micBubble(rec: Bool) {
        SpriteFactory.toolBubble(&self)
        let ink = Palette.keyboard
        pixelMap([
            "..##..",
            "..##..",
            "#.##.#",
            ".#..#.",
            "..##..",
            ".####.",
        ], x: 2, y: 2, colors: ["#": ink])
        if rec { fill(8, 3, 2, 2, Palette.rec) }
    }


    /// A small eighth note.
    mutating func note(_ x: Int, _ y: Int, _ color: RGBA) {
        fill(x, y + 2, 2, 2, color)
        fill(x + 1, y - 1, 1, 3, color)
        set(x + 2, y - 1, color)
    }

    /// Dark lenses over both eyes with a bridge between them and a glint.
    mutating func shades(cx: Int, ey: Int) {
        for x in [cx - 5, cx + 1] {
            fill(x, ey, 4, 3, Palette.lens)
            set(x + 1, ey, Palette.white)
        }
        fill(cx - 1, ey, 2, 1, Palette.lens)
    }
}

extension SpriteFactory {
    /// Rows of the face for a body (eyes, mouth), by figure.
    static func faceRows(_ s: BodyStyle, y0: Int, by: Int) -> (eyes: Int, mouth: Int) {
        if s.figure == .lidman {
            let ey = y0 + PixelCanvas.lidEyeRow(s.h) + s.lookY
            return (ey, min(ey + 5, by - 3))
        }
        let ey = y0 + max(3, jsRound(Double(s.h) * 0.3)) + s.lookY
        return (ey, min(ey + 4, by - 4))
    }

    /// Headphones float down onto the head, it squashes a little as they land, a happy bob and a note.
    static func headphonesOn(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var plain = look
        plain.extras.remove(.headphones)
        let lift = [-12, -10, -8, -6, -4, -2, 0, 0, 0, 0, 0, 0][i]
        var s = BodyStyle(look: plain)
        s.lookY = i < 5 ? -1 : 0
        s.eyes = i == 6 ? .squeeze : i >= 7 ? .happy : .open
        s.mouth = i >= 7 ? .smile : .open
        s.blush = i >= 7 ? 2 : 0
        if i == 6 { s.w = 17; s.h = 13 }
        s.dy = [0, 0, 0, 0, 0, 0, 0, 0, -1, 0, -1, 0][i]
        let b = c.body(s)
        c.headphones(x0: b.x0, y0: b.y0, w: s.w, h: s.h, figure: look.figure, skin: look.skin, dy: lift)
        if i >= 8 { c.note(min(b.x0 + s.w + 1, 24), b.y0 - 2 - (i - 8), Palette.note) }
    }

    /// Taken off: lifted up and away, a blink.
    static func headphonesOff(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var plain = look
        plain.extras.remove(.headphones)
        let lift = [0, 0, -2, -4, -7, -10, -14, -20, -30][i]
        var s = BodyStyle(look: plain)
        s.lookY = (2...6).contains(i) ? -1 : 0
        s.eyes = i == 7 ? .blink : .open
        s.mouth = .flat
        let b = c.body(s)
        c.headphones(x0: b.x0, y0: b.y0, w: s.w, h: s.h, figure: look.figure, skin: look.skin, dy: lift)
    }

    /// Sound is playing: a bob to the beat, eyes shut happily, notes drifting up on both sides.
    static func music(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.dy = i % 2 == 0 ? 0 : -1
        if i % 4 == 0 { s.w = 17; s.h = 13 }
        s.eyes = .happy
        s.mouth = .smile
        s.blush = 2
        s.dx = [0, 0, 1, 1, 0, 0, -1, -1][i]
        c.body(s)
        c.note(23 + (i % 4 < 2 ? 0 : 1), 10 - i, Palette.note)
        c.note(6 - (i % 4 < 2 ? 0 : 1), 13 - ((i + 4) % 8), Palette.noteAlt)
    }

    /// The mic or camera is in use: the pet keeps quiet (lips pressed) under a bubble with a microphone and
    /// a blinking recording dot.
    static func onAir(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.eyes = i == 4 ? .blink : .open
        s.lookX = -1; s.lookY = -1
        s.mouth = .tiny
        s.blush = 2
        c.body(s)
        c.micBubble(rec: i % 2 == 0)
    }

    /// Running hot: a thermometer by the head with its red column creeping up, heat shimmering on the other
    /// side, flushed cheeks, panting and sweat.
    static func overheated(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.eyes = i % 4 == 3 ? .blink : .half
        s.mouth = i % 2 == 0 ? .open : .wobble
        s.blush = 3
        if i % 2 == 1 { s.w = 17; s.h = 13 }
        let b = c.body(s)
        // Sweat: a drop running down each side.
        for (x, phase) in [(b.x0 + 1, 0), (b.x0 + s.w - 2, 2)] {
            let y = b.y0 + 3 + ((i + phase) % 4) * 2
            c.set(x, y, Palette.sweat); c.set(x, y + 1, Palette.sweatDark)
        }
        // Thermometer: tube, bulb, and a column that wobbles near the top.
        let (tx, ty) = (6, 2)
        c.fill(tx, ty, 3, 8, Palette.keyboardTop)
        c.fill(tx + 1, ty + 1, 1, 6, Palette.white)
        c.fill(tx - 1, ty + 7, 5, 3, Palette.keyboardTop)
        c.fill(tx, ty + 8, 3, 1, Palette.rec)
        let level = [3, 4, 5, 6, 6, 5, 6, 6][i]
        c.fill(tx + 1, ty + 7 - level, 1, level, Palette.rec)
        // Heat shimmer rising on the right.
        for row in 0..<4 {
            let y = 9 - row * 2 - (i % 2)
            c.set(24 + ((row + i) % 2), y, row % 2 == 0 ? Palette.heat : Palette.heatLight)
            c.set(26 - ((row + i) % 2), y + 1, Palette.heatLight)
        }
    }

    /// Low power mode: slow, sleepy breathing next to a yellow battery, the way the menu bar shows that
    /// mode.
    static func lowPower(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.eyes = i == 5 ? .blink : .half
        s.mouth = .flat
        if i % 4 >= 2 { s.h = 13; s.w = 17 }
        c.body(s)
        c.battery(5, 6, level: 3, color: Palette.sun)
    }

    /// Offline: a bubble with Wi-Fi arcs struck through, the pet looking up at it, worried.
    static func offline(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.lookX = -1; s.lookY = -1
        s.eyes = i == 6 ? .blink : .worry
        s.mouth = .wobble
        c.body(s)
        toolBubble(&c)
        // Wi-Fi: two arcs over a dot, struck through in red (the slash blinks now and then).
        let ink = Palette.keyboard
        c.fill(4, 3, 5, 1, ink); c.set(3, 4, ink); c.set(9, 4, ink)
        c.fill(5, 5, 3, 1, ink); c.set(4, 6, ink); c.set(8, 6, ink)
        c.set(6, 7, ink)
        if i % 4 < 3 { for k in 0..<6 { c.set(3 + k, 2 + k, Palette.rec) } }
    }

    /// Charged to 100%: a battery fills up by the head, sparkles, and the pet hops.
    static func batteryFull(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.dy = [0, 0, 0, 0, 0, 0, -2, -3, -1, 0, 0, 0][i]
        if i == 9 { s.w = 17; s.h = 13 }
        s.eyes = i >= 5 ? .happy : .open
        s.mouth = i >= 5 ? .smile : .flat
        s.lookY = i < 5 ? -1 : 0
        s.blush = i >= 5 ? 2 : 0
        let b = c.body(s)
        // LM's diamond takes the middle and the right is the Claude column: his battery goes on the left.
        let x = look.figure == .lidman ? 5 : b.cx + 4, y = b.y0 - 5
        c.battery(x, y, level: min(4, i + 1), color: Palette.batteryGreen)
        if i >= 5, i % 2 == 1 {
            c.sparkle(x + 1, y - 2, Palette.amberLight, big: false)
            c.sparkle(x + 6, y - 1, Palette.tealLight, big: false)
        }
    }

    /// A screenshot: a white flash, a squint, then a smile for the picture next to a hand-drawn ✌️.
    static func screenshot(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.eyes = i == 3 ? .squeeze : i >= 4 ? .happy : .open
        s.mouth = i >= 4 ? .smile : .flat
        s.blush = i >= 4 ? 3 : 0
        s.lookX = i < 2 ? -1 : 0; s.lookY = i < 2 ? -1 : 0
        let b = c.body(s)
        if i >= 4 { c.peaceEmoji(x: 5, y: i == 4 ? 1 : 0) }
        if i >= 5, i % 2 == 1 { c.sparkle(b.x0 + s.w + 1, b.y0, Palette.amberLight, big: true) }
        if i == 2 { c.fillBlend(0, 0, 32, 32, Palette.flash) }
    }

    /// Dark mode: a crescent moon and two stars come out; the pet goes sleepy-eyed and says "oh".
    static func darkMode(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.lookX = -1; s.lookY = -1
        s.eyes = i >= 5 ? (i == 7 ? .blink : .half) : .open
        s.mouth = i >= 3 ? .tiny : .flat
        c.body(s)
        let rise = max(0, 3 - i)
        let (x, y) = (5, 3 + rise)
        c.fill(x + 1, y, 2, 1, Palette.moon)
        c.fill(x, y + 1, 2, 3, Palette.moon)
        c.fill(x + 1, y + 4, 2, 1, Palette.moon)
        if i >= 3 { c.sparkle(10, 2, Palette.moon, big: i % 2 == 0) }
        if i >= 5 { c.sparkle(8, 9, Palette.white, big: false) }
    }

    /// Light mode: the sun comes up and the pet flips on a pair of shades.
    static func lightMode(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.lookX = i < 4 ? -1 : 0
        s.lookY = i < 4 ? -1 : 0
        s.eyes = i == 4 ? .squeeze : .open
        s.mouth = i >= 6 ? .smile : .flat
        let b = c.body(s)
        let rise = max(0, 3 - i)
        let (x, y) = (7, 3 + rise)
        c.fill(x, y, 4, 4, Palette.sun)
        c.set(x, y, Palette.sunRay); c.set(x + 3, y + 3, Palette.sunRay)
        if i % 2 == 0 {
            for (dx, dy) in [(-2, 1), (5, 2), (1, -2), (2, 5), (-1, -1), (4, 4), (4, -1), (-1, 4)] {
                c.set(x + dx, y + dy, Palette.sunRay)
            }
        }
        if i >= 5 {
            let rows = faceRows(s, y0: b.y0, by: b.y0 + s.h)
            c.shades(cx: b.cx, ey: rows.eyes - (i == 5 ? 2 : 0))
        }
    }
}

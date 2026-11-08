import PetCore

/// A new version, as a shipping box with the update arrow on its side: it floats down on a balloon, waits by
/// the pet until clicked, is unpacked while the update downloads and installs, and after the restart the pet
/// pops out of a big one.
extension SpriteFactory {
    static let kraft = RGBA(0xD3A465), kraftLight = RGBA(0xEBC890), kraftDark = RGBA(0x8F6534), tape = RGBA(0xF3DDB0)
    static let balloon = RGBA(0xE24B4A), balloonDark = RGBA(0xA32D2D), balloonShine = RGBA(0xF7B5B4)
    static let dust = RGBA(0xC9C3B6)

    /// The update arrow, 5×5.
    static let updateArrow = ["..#..", ".###.", "#####", "..#..", "..#.."]

    /// The box stands in columns 20-26, a little in front of the pet stepped 3 aside (more would take it into
    /// the Codex column), clear of the agent blocks.
    static let boxX = 20

    static func stamp(_ c: inout PixelCanvas, _ rows: [String], x: Int, y: Int, _ color: RGBA) {
        for (dy, row) in rows.enumerated() {
            for (dx, ch) in row.enumerated() where ch == "#" { c.set(x + dx, y + dy, color) }
        }
    }

    /// A shipping box 7×7, tape over the top and the arrow on its side; `open` (1, 2) folds the flaps out.
    static func updateBox(_ c: inout PixelCanvas, x: Int = boxX, bottom: Int, lit: Bool = false, open: Int = 0) {
        let top = bottom - 6
        c.fill(x, top, 7, 7, kraft)
        c.fill(x + 6, top, 1, 7, kraftDark)
        c.fill(x, bottom, 7, 1, kraftDark)
        if open == 0 {
            c.fill(x, top, 7, 1, kraftLight)
            c.fill(x + 3, top, 1, 2, tape)
        } else {
            c.fill(x, top, 7, 1, kraftDark)
            // The right flap stops at the box's edge: column 27 belongs to the agent blocks.
            c.fill(x - open, top - open, 2 + open, 1, kraftLight)
            c.fill(x + 5, top - open, 2, 1, kraftLight)
        }
        stamp(&c, updateArrow, x: x + 1, y: top + 2, lit ? Palette.tealLight : Palette.teal)
    }

    /// A round balloon on a short string whose end is at (x, y).
    static func balloon(_ c: inout PixelCanvas, x: Int, y: Int, sway: Int = 0) {
        let bx = x - 2 + sway, by = y - 9
        c.fill(bx + 1, by, 3, 1, balloon)
        c.fill(bx, by + 1, 5, 3, balloon)
        c.fill(bx + 1, by + 4, 3, 1, balloon)
        c.fill(bx + 4, by + 1, 1, 3, balloonDark)
        c.set(bx + 1, by + 1, balloonShine)
        c.set(bx + 2, by + 5, balloonDark)
        for k in 0..<3 { c.set(x + (k == 1 ? sway : 0), y - 3 + k, Palette.keyboardTop) }
    }

    /// The box floats down on a balloon; the pet steps aside and looks up, starts at the landing, and the
    /// balloon lets go and floats off.
    static func updateArrive(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        let land = 11, landed = i >= land
        var s = BodyStyle(look: look)
        s.dx = -min(3, i / 2)
        s.lookX = 1; s.lookY = landed ? 0 : -1
        s.eyes = i == land ? .wide : .open
        s.mouth = i == land ? .open : (i > land + 1 ? .smile : .flat)
        if i == land + 1 { s.dy = -2; s.h = 15 }
        let b = c.body(s)
        let bottom = landed ? 26 : 26 - (land - i) * 2
        updateBox(&c, bottom: bottom, lit: landed && i % 2 == 0)
        if !landed {
            balloon(&c, x: boxX + 3, y: bottom - 7, sway: [0, 1, 0, -1][i % 4])
        } else if i < land + 5 {
            balloon(&c, x: boxX + 3, y: 19 - (i - land + 1) * 5, sway: 1)
        }
        if i == land || i == land + 1 {
            let x = b.cx + 1 - look.headMarkShift
            c.fill(x, b.y0 - 7, 2, 3, Palette.amber); c.fill(x, b.y0 - 3, 2, 1, Palette.amber)
        }
    }

    /// Waiting to be opened: the pet beside it glances over now and then, and the arrow glows in turn.
    static func updateWait(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.dx = -3
        s.lookX = (5...8).contains(i) ? 1 : 0
        s.eyes = i == 12 ? .blink : .open
        s.mouth = .flat
        if i % 8 == 4 { s.highlightShift = 1 }
        c.body(s)
        updateBox(&c, bottom: 26, lit: (5...8).contains(i))
    }

    /// Downloading and installing: the flaps open, the pet peeking in, sparkles rising out in turn.
    static func updateUnpack(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.dx = -3; s.lookX = 1; s.lookY = 1
        s.eyes = i == 9 ? .blink : .open
        s.mouth = .smile
        if i % 4 == 2 { s.h = 13 }
        c.body(s)
        updateBox(&c, bottom: 26 - (i % 6 == 3 ? 1 : 0), lit: i % 4 < 2, open: 1)
        let colors = [Palette.teal, Palette.amber, Palette.tealLight, Palette.crownGold]
        for k in 0..<2 {
            let rise = (i + k * 6) % 12
            let x = boxX + 1 + [1, 4, 2, 3][(i / 3 + k) % 4]
            c.sparkle(x, 17 - rise, colors[(i / 3 + k) % 4], big: rise > 3 && rise < 8)
        }
    }

    /// The big box the new version came in, 20 wide at columns 6-25: its back, and its side with the arrow
    /// drawn over the pet while it's inside.
    static func bigBoxBack(_ c: inout PixelCanvas, top: Int, open: Int) {
        c.fill(6, top, 20, 27 - top, kraftDark)
        guard open > 0 else { return }
        // The flaps fold out to columns 5 and 26 at most: 4 and 27 belong to the agent blocks.
        c.fill(5, top - open, 6, 1, kraftLight)
        c.fill(21, top - open, 6, 1, kraftLight)
    }

    static func bigBoxFront(_ c: inout PixelCanvas, top: Int, open: Int, shake: Int = 0) {
        let x = 6 + shake
        c.fill(x, top, 20, 27 - top, kraft)
        c.fill(x + 19, top, 1, 27 - top, kraftDark)
        c.fill(x, 26, 20, 1, kraftDark)
        c.fill(x, top, 20, 1, open == 0 ? kraftLight : kraftDark)
        if open == 0 { c.fill(x + 8, top, 4, 2, tape) }
        if top <= 21 { stamp(&c, updateArrow, x: x + 8, y: top + 2, Palette.teal) }
    }

    /// After the restart: the box shakes, the flaps burst open, the pet peeks over the rim, jumps clear and
    /// lands in front; the box folds down into a puff of dust and a check mark shows over the pet.
    static func updateDone(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        // Inside, the pet is squeezed down so its bottom stays on the floor and nothing shows under the box.
        s.dy = [0, 0, 0, 0, -2, -5, -9, -12, -10, -5, 0, 0, 0, 0, 0, 0, 0, 0][i]
        if i <= 2 { s.h = 6 }
        if i == 3 { s.h = 12 }
        s.eyes = i <= 2 ? .closed : (i == 3 ? .open : (i >= 10 ? .happy : .wide))
        s.mouth = i >= 5 ? .open : .flat
        if i == 4 || i == 5 { s.h = 15 }
        if i == 10 { s.w = 18; s.h = 12 }
        if i >= 11 { s.mouth = .smile; s.blush = 3 }
        s.shadow = i >= 10
        let open = i >= 2 ? (i == 2 ? 2 : 1) : 0
        let top = min(26, 19 + max(0, i - 10) * 3)
        let boxShown = i < 14
        if boxShown { bigBoxBack(&c, top: top, open: i >= 10 ? 0 : open) }
        if i >= 9 {
            if boxShown { bigBoxFront(&c, top: top, open: open) }
            c.body(s)
        } else {
            c.body(s)
            bigBoxFront(&c, top: top, open: open, shake: i < 2 ? [1, -1][i] : 0)
        }
        if i == 2 { for (x, y) in [(5, 15), (26, 15), (9, 14), (22, 14)] { c.set(x, y, dust) } }
        if (5...11).contains(i) {
            let bits: [(Int, Int, RGBA)] = [(6, 2, Palette.teal), (25, 4, Palette.amber), (9, 7, Palette.capRed),
                                            (22, 1, Palette.crownGold), (5, 10, Palette.tealLight), (26, 9, Palette.capRed)]
            for (k, (x, y, color)) in bits.enumerated() where (k + i) % 3 != 0 { c.set(x, y + (i - 5), color) }
        }
        if i == 13 || i == 14 {
            for (x, y) in [(5, 25), (7, 23), (24, 24), (26, 25), (6, 22), (25, 22)] { c.set(x, y - (i - 13), dust) }
        }
        if i >= 15 { for (x, y) in [(20, 8), (21, 9), (22, 8), (23, 7), (24, 6)] { c.set(x, y, Palette.teal) } }
    }
}

import PetCore

/// What the user is doing on the Mac while no agent works: typing, the app in front (a game, a video, code),
/// apps opening and quitting, a USB stick, a new display, the keyboard layout. New art keeps out of the agent
/// columns (0-4 and 27-31) below row 8. (Quick Space switches reuse `dizzy`.)
extension SpriteFactory {
    // MARK: Typing

    /// The user types and no agent works: over the head, left and right in turn, a keycap with a letter pops
    /// up, rises and fades; the pet watches and nods on every stroke.
    static func typingAlong(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        let nod = i % 3 == 0
        s.dy = nod ? 1 : 0
        if nod { s.w = 17; s.h = 13 }
        s.lookX = i % 6 < 3 ? -1 : 1
        s.lookY = -1
        s.eyes = i == 11 ? .blink : .open
        s.mouth = i >= 6 ? .smile : .flat
        let b = c.body(s)
        let top = figureTop(c, b, s)
        for (n, x) in [6, 20].enumerated() {
            let t = (i + n * 3) % 6
            guard t < 4 else { continue }
            let letter = keyLetters[((i + n * 3) / 6 * 2 + n) % keyLetters.count]
            // Tall figures' tops reach higher: the keys rise from beside them, never over the head itself.
            let y = min(5, top - 6) - t
            keycap(&c, x: x, y: max(0, y), letter: letter, fade: t == 3)
            if t == 0 { c.sparkle(x - 1, max(1, y + 6), Palette.amberLight, big: false) }
        }
    }

    static let keyLetters = ["A", "S", "D", "F", "J", "K"]

    /// A 5×6 keycap: a dark rim, a white face with a letter, a grey front edge.
    static func keycap(_ c: inout PixelCanvas, x: Int, y: Int, letter: String, fade: Bool) {
        c.fill(x, y, 5, 5, fade ? Palette.steam : Palette.keyboard)
        c.fill(x + 1, y + 1, 3, 3, fade ? Palette.mist : Palette.white)
        c.fill(x, y + 5, 5, 1, fade ? Palette.mist : Palette.keyboardTop)
        guard !fade, let glyph = keyGlyphs[letter] else { return }
        c.pixelMap(glyph, x: x + 1, y: y + 1, colors: ["#": Palette.keyboard])
    }

    static let keyGlyphs: [String: [String]] = [
        "A": [".#.", "###", "#.#"], "S": [".##", ".#.", "##."], "D": ["##.", "#.#", "##."],
        "F": ["###", "##.", "#.."], "J": ["..#", "#.#", ".#."], "K": ["#.#", "##.", "#.#"],
    ]

    // MARK: The app in front

    /// A game in front: a gamepad held low, buttons blinking, eyes on the screen, now and then a "whoa".
    static func gamepad(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.by = 25
        s.lookY = -1
        s.eyes = i == 5 ? .wide : i == 7 ? .blink : .open
        s.mouth = i == 5 ? .open : .tiny
        s.blush = i == 5 ? 3 : 2
        let b = c.body(s)
        let red = i % 3 == 0 ? Palette.capRed : Palette.errorDark
        c.pixelMap([
            ".DDDDDDDDDD.",
            "DDLDDDDDDYDD",
            "DLLLDDDDRDBD",
            "DDLDDDDDDGDD",
            ".DDD....DDD.",
        ], x: 10, y: 21 + i % 2, colors: [
            "D": Palette.accessoryDark, "L": Palette.keyboardTop, "Y": Palette.sun,
            "R": red, "B": Palette.blue, "G": Palette.green,
        ])
        if i == 5 { c.sparkle(b.x0 + s.w, max(1, b.y0 - 3), Palette.amberLight, big: true) }
    }

    /// A video in front: a striped popcorn bucket by its side, a kernel now and then, eyes on the screen.
    static func popcorn(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.cx = 15
        s.lookX = -1; s.lookY = -1
        s.eyes = i == 6 ? .blink : .open
        s.mouth = [.flat, .flat, .flat, .open, .open, .flat, .open, .flat][i]
        let b = c.body(s)
        let (x, y) = (21, 19)
        for k in 0..<5 { c.fill(x + k, y + 1, 1, 7, k % 2 == 0 ? Palette.capRed : Palette.white) }
        c.fill(x, y + 7, 5, 1, Palette.errorDark)
        c.pixelMap([".K.k.", "kKkKk"], x: x, y: y - 1, colors: ["K": Palette.petal, "k": Palette.petalCenter])
        // One kernel on its way to the mouth.
        let mouth = faceRows(s, y0: b.y0, by: b.y0 + s.h).mouth
        let path = [(22, 17), (20, 15), (18, 16), (b.cx, mouth)]
        if (2...4).contains(i) {
            let (px, py) = path[i - 1]
            c.set(px, py, Palette.petalCenter); c.set(px + 1, py, Palette.petal)
        }
    }

    /// Code in front: glasses on (the cube's own; LM and the paperclip wear none) and a terminal in the bubble.
    static func coding(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        if look.figure == .cube { s.accessory = .glasses }
        s.lookX = -1; s.lookY = -1
        s.eyes = i == 4 ? .blink : .open
        s.mouth = .flat
        c.body(s)
        terminalIcon(i, &c)
    }

    // MARK: Apps opening and quitting

    /// An app opens: its icon bounces at the top left the way it does in the Dock, the pet's eyes going up and
    /// down with it; then the running dot lights under it, a sparkle, a hop.
    static func appLaunched(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        let bounce = [6, 3, 1, 0, 1, 3, 6, 3, 1, 3, 6, 6, 6, 6]
        let y = 7 - bounce[i]
        var s = BodyStyle(look: look)
        // As far right as the squash (17 wide) keeps clear of the Claude column, away from the icon.
        s.cx = 18
        s.lookX = -1
        s.lookY = i < 10 && y >= 4 ? 0 : -1
        s.eyes = i >= 11 ? (i == 13 ? .blink : .happy) : .wide
        s.mouth = i < 10 ? .open : .smile
        s.dy = i == 11 ? -2 : i == 12 ? -1 : 0
        if i == 10 { s.w = 17; s.h = 13 }
        c.body(s)
        appIcon(&c, x: 5, y: min(y, 3))
        if i >= 10 { c.fill(8, 12, 2, 1, Palette.keyboard) }
        if i == 11 || i == 13 { c.sparkle(14, 1, Palette.amberLight, big: true) }
    }

    /// An app quits after a long time together: its running dot goes out, the icon shrinks into a puff, and
    /// the pet waves it goodbye with its right mitten.
    static func appQuit(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        // A pixel left of `usbIn`: the leaning mitten's outline would reach the Claude column.
        s.cx = 13
        s.lookX = -1; s.lookY = -1
        s.eyes = i == 9 ? .blink : i < 2 ? .open : .happy
        s.mouth = i < 2 ? .flat : .smile
        let b = c.body(s)
        if (2...8).contains(i) { waveMitten(&c, b, s, look, lean: i % 2 == 0, from: b.y0 - 1) }
        if i < 1 { c.fill(8, 12, 2, 1, Palette.keyboard) }
        switch i {
        case 0...2: appIcon(&c, x: 5, y: 3)
        case 3: appIcon(&c, x: 5, y: 3, shrink: 1)
        case 4: appIcon(&c, x: 5, y: 3, shrink: 2)
        case 5: c.puff(9, 6, 2)
        case 6: c.puff(9, 5, 1); c.set(12, 3, Palette.steam)
        default: break
        }
    }

    /// The right mitten raised, straight up or leaning out (as in `wave`), from row `from` to the body's middle.
    static func waveMitten(_ c: inout PixelCanvas, _ b: BodyFrame, _ s: BodyStyle, _ look: Look, lean: Bool, from top: Int) {
        let side = b.x0 + s.w, bottom = b.y0 + 5
        c.mitten((top...bottom).map { y in (x: side + (lean ? (bottom - y) / 3 : 0), y: y) }, look.skin)
        if lean { c.set(side + 3, top - 3, Palette.steam); c.set(side + 4, top - 2, Palette.steam) }
    }

    /// An app icon, 8×8 like a Dock tile: a rounded square, lighter on top, with a little window on it.
    /// `shrink` 1...2 draws it smaller around the same center.
    static func appIcon(_ c: inout PixelCanvas, x: Int, y: Int, shrink: Int = 0) {
        let size = 8 - shrink * 2, x = x + shrink, y = y + shrink
        c.fill(x, y, size, size, Palette.blue)
        c.fill(x, y, size, size / 2, Palette.propellerBlue)
        c.fill(x, y + size - 1, size, 1, Palette.sweatDark)
        for (dx, dy) in [(0, 0), (size - 1, 0), (0, size - 1), (size - 1, size - 1)] { c.clear(x + dx, y + dy) }
        guard size >= 6 else { return }
        c.fill(x + 2, y + 2, size - 4, size - 4, Palette.white)
        c.fill(x + 2, y + 2, size - 4, 1, Palette.keyboard)
    }

    // MARK: A USB stick, a display

    /// A USB stick standing up: a metal plug with a hole on a blue body with a white label.
    static func usbStick(_ c: inout PixelCanvas, x: Int, y: Int) {
        c.pixelMap([
            ".mmm.",
            ".mkm.",
            ".mmm.",
            "BBBBB",
            "BbWbB",
            "BbWbB",
            "BbbbB",
            ".BBB.",
        ], x: x, y: y, colors: [
            "m": Palette.keyboardTop, "k": Palette.keyboard, "B": Palette.beanie,
            "b": Palette.beanieRib, "W": Palette.white,
        ])
    }

    /// A stick plugged in: it drops into the pet's raised mitten, a happy wiggle, sparkles.
    static func usbIn(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.cx = 14
        s.lookX = 1; s.lookY = -1
        s.eyes = i < 3 ? .wide : (i == 9 ? .blink : .happy)
        s.mouth = i < 3 ? .open : .smile
        s.dy = [0, 0, 0, 1, 0, -1, 0, -1, 0, 0][i]
        s.blush = i >= 3 ? 3 : 2
        let b = c.body(s)
        let side = b.x0 + s.w
        waveMitten(&c, b, s, look, lean: false, from: b.y0 - 1)
        let drop = [12, 6, 1, 0, 0, 0, 0, 0, 0, 0][i]
        let y = b.y0 - 9 - drop + (i == 3 ? 1 : 0)
        if y > -8 { usbStick(&c, x: side - 1, y: y) }
        if i == 4 || i == 6 { c.sparkle(side + 4, max(1, b.y0 - 10), Palette.amberLight, big: true) }
        if i == 5 || i == 7 { c.sparkle(side - 3, max(1, b.y0 - 7), Palette.tealLight, big: false) }
    }

    /// Ejected: an eject sign in the bubble, the stick flies up and away, the pet waves after it.
    static func usbOut(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.cx = 13
        s.lookX = 1; s.lookY = -1
        s.eyes = i == 9 ? .blink : i >= 3 ? .happy : .open
        s.mouth = i >= 3 ? .smile : .flat
        let b = c.body(s)
        waveMitten(&c, b, s, look, lean: i >= 4 && i % 2 == 0, from: b.y0 - 1)
        let lift = [0, 0, 0, 3, 8, 15, 30, 30, 30, 30][i]
        if lift < 20 { usbStick(&c, x: b.x0 + s.w - 1, y: b.y0 - 9 - lift) }
        if (1...5).contains(i) {
            toolBubble(&c)
            c.pixelMap(["...#...", "..###..", ".#####.", ".......", ".#####."], x: 2, y: 2,
                       colors: ["#": Palette.keyboard])
        }
    }

    /// A display connected: a screen drops in at the top right, lights up and shows a little copy of the pet;
    /// the pet stares, then waves at itself.
    static func newDisplay(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.cx = 13
        s.lookX = i >= 2 ? 1 : 0; s.lookY = i >= 2 ? -1 : 0
        s.eyes = (2...5).contains(i) ? .wide : i >= 6 ? (i == 11 ? .blink : .happy) : .open
        s.mouth = (2...5).contains(i) ? .open : i >= 6 ? .smile : .flat
        let b = c.body(s)
        let drop = [9, 5, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0][i]
        let (x, y) = (16, 1 - drop)
        c.fill(x, y, 11, 8, Palette.accessoryDark)
        let screen: RGBA = i < 3 ? Palette.terminal : i == 3 ? Palette.white : Palette.bubble
        c.fill(x + 1, y + 1, 9, 6, screen)
        if i >= 4 { c.fill(x + 1, y + 1, 9, 1, Palette.waterLight) }
        c.fill(x + 5, y + 8, 1, 1, Palette.accessoryDark)
        c.fill(x + 3, y + 9, 5, 1, Palette.accessoryDark)
        if i >= 5 { c.miniCube(x + 3, y + 2, look.skin) }
        if i >= 8, i % 2 == 0 { c.set(x + 8, y + 2, look.skin.outline) }
        if i >= 7 { waveMitten(&c, b, s, look, lean: i % 2 == 1, from: b.y0 + 1) }
        if i == 6 { c.sparkle(14, 2, Palette.amberLight, big: true) }
    }

    // MARK: Keyboard layout

    /// The layout switched: a badge like the menu bar's input source flips over from the old code to the new
    /// one (`WorkProps.layout(from:to:)`; EN to RU when none is given); the pet blinks with the flip and smiles.
    static func layoutSwitch(_ i: Int, _ look: Look, _ props: WorkProps, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.lookX = -1; s.lookY = -1
        s.eyes = i == 4 ? .blink : i >= 6 ? .happy : .open
        s.mouth = i >= 6 ? .smile : .flat
        s.dy = i == 6 ? -1 : 0
        c.body(s)
        let codes = props.layoutCodes ?? (from: "EN", to: "RU")
        let height = [7, 7, 7, 5, 1, 5, 7, 7, 7, 7][i]
        layoutBadge(&c, code: i >= 4 ? codes.to : codes.from, height: height)
        if i == 6 || i == 8 { c.sparkle(13, 1, Palette.amberLight, big: true) }
    }

    /// The badge at x 1...11, y 1...7 (squashed around row 4 while it flips): white letters on the code's color.
    static func layoutBadge(_ c: inout PixelCanvas, code: String, height: Int) {
        let (x, w) = (1, 11)
        let y = 4 - height / 2
        let (face, edge) = badgeColors(code)
        c.fill(x, y, w, height, face)
        if height > 2 {
            c.fill(x, y + height - 1, w, 1, edge)
            for (dx, dy) in [(0, 0), (w - 1, 0), (0, height - 1), (w - 1, height - 1)] { c.clear(x + dx, y + dy) }
        }
        guard height == 7 else { return }
        let glyphs = code.compactMap { letterGlyphs[$0] }
        let width = glyphs.map { $0[0].count }.reduce(0, +) + max(0, glyphs.count - 1)
        var gx = x + (w - width + 1) / 2
        for glyph in glyphs {
            c.pixelMap(glyph, x: gx, y: y + 1, colors: ["#": Palette.white])
            gx += glyph[0].count + 1
        }
    }

    /// English blue, Russian red, the rest by their first letter.
    static func badgeColors(_ code: String) -> (RGBA, RGBA) {
        switch code {
        case "EN": return (Palette.blue, Palette.sweatDark)
        case "RU": return (Palette.capRed, Palette.errorDark)
        default:
            let others = [(Palette.teal, Palette.keyboard), (Palette.amber, Palette.amberDark), (Palette.pink, Palette.keyboard)]
            return others[Int(code.unicodeScalars.first?.value ?? 0) % others.count]
        }
    }

    /// A 5-row pixel font for the badge, 3 wide (M, N and W 4).
    static let letterGlyphs: [Character: [String]] = [
        "A": [".#.", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
        "C": [".##", "#..", "#..", "#..", ".##"], "D": ["##.", "#.#", "#.#", "#.#", "##."],
        "E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
        "G": [".##", "#..", "#.#", "#.#", ".##"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
        "I": ["###", ".#.", ".#.", ".#.", "###"], "J": ["..#", "..#", "..#", "#.#", ".#."],
        "K": ["#.#", "#.#", "##.", "#.#", "#.#"], "L": ["#..", "#..", "#..", "#..", "###"],
        "M": ["#..#", "####", "####", "#..#", "#..#"], "N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
        "O": [".#.", "#.#", "#.#", "#.#", ".#."], "P": ["##.", "#.#", "##.", "#..", "#.."],
        "Q": [".#.", "#.#", "#.#", "##.", ".##"], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
        "S": [".##", "#..", ".#.", "..#", "##."], "T": ["###", ".#.", ".#.", ".#.", ".#."],
        "U": ["#.#", "#.#", "#.#", "#.#", "###"], "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
        "W": ["#..#", "#..#", "####", "####", "#..#"], "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
        "Y": ["#.#", "#.#", ".#.", ".#.", ".#."], "Z": ["###", "..#", ".#.", "#..", "###"],
    ]
}

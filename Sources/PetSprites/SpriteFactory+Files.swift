import PetCore

extension SpriteFactory {
    /// A file dragged over the pet: eyes up at it, mouth wide open, a little bounce.
    static func catchOpen(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.eyes = .wide
        s.lookY = -1
        s.mouth = .yawn
        s.blush = 2
        s.dy = i % 2 == 0 ? 0 : -1
        c.body(s)
    }

    /// Dropped: the page shrinks into the mouth, two chews with puffed cheeks, then a "?" for the question.
    static func swallow(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        switch i {
        case 0...2:
            s.eyes = .wide; s.lookY = -1; s.mouth = .yawn
        case 3, 5:
            s.eyes = .happy; s.mouth = .flat; s.w = 17; s.h = 13; s.blush = 3
        case 4, 6:
            s.eyes = .happy; s.mouth = .flat; s.blush = 3
        default:
            s.eyes = .open; s.lookY = -1; s.mouth = .smile
        }
        let b = c.body(s)
        let mouthY = b.y0 + (look.figure == .lidman ? 11 : 8)
        switch i {
        // Over the head, then already small in the mouth: the eyes stay in sight.
        case 0: page(&c, x: b.cx - 3, bottom: b.y0 - 1, w: 5, h: 6)
        case 1: page(&c, x: b.cx - 2, bottom: mouthY + 1, w: 3, h: 3)
        case 2: page(&c, x: b.cx - 1, bottom: mouthY + 1, w: 2, h: 2)
        case 7, 8:
            for (y, row) in questionMark.enumerated() {
                for (x, ch) in row.enumerated() where ch == "#" { c.set(b.cx + 5 + x, b.y0 - 9 + y - (i == 8 ? 1 : 0), Palette.amber) }
            }
        default: break
        }
    }

    /// Not a file it can take (a folder, an app, an archive): eyes shut, a quick shake of the head.
    static func shakeHead(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.dx = [-1, 1, -1, 1, 0, 0][i]
        s.eyes = i < 4 ? .closed : .open
        s.mouth = .flat
        c.body(s)
    }

    /// A small sheet of paper: outlined, white, a grey line when there's room.
    private static func page(_ c: inout PixelCanvas, x: Int, bottom: Int, w: Int, h: Int) {
        let y = bottom - h + 1
        c.fill(x, y, w, h, Palette.newsInk)
        c.fill(x + 1, y + 1, max(1, w - 2), max(1, h - 2), Palette.newsPage)
        if w >= 5 { c.fill(x + 1, y + 2, w - 3, 1, Palette.newsLine) }
    }
}

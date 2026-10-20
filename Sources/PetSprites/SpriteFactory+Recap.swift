import PetCore

extension SpriteFactory {
    /// The weekly recap: takes out a folded newspaper and opens it up in front, eyes over the top.
    static func newspaperOpen(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        let b = c.body(s)
        switch i {
        case 0: foldedPaper(&c, b, look)
        case 1: paper(&c, from: b.cx - 6, to: b.cx + 5, top: paperTop(b, look), print: false, look: look)
        default: paper(&c, from: b.cx - 9, to: b.cx + 8, top: paperTop(b, look), print: true, look: look)
        }
    }

    /// Reading it until clicked: eyes over the top, a blink, and now and then a page turned over.
    static func newspaper(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.eyes = i == 6 ? .blink : .open
        let b = c.body(s)
        let flip: Double? = switch i {
        case 8: 1.0 / 3
        case 9: 2.0 / 3
        case 10: 1
        default: nil
        }
        paper(&c, from: b.cx - 9, to: b.cx + 8, top: paperTop(b, look), print: true, flip: flip, look: look)
    }

    /// Just under the eyes: LM's sit two rows lower in his drop than the cube's.
    private static func paperTop(_ b: BodyFrame, _ look: Look) -> Int {
        b.y0 + (look.figure == .lidman ? 9 : 7)
    }

    /// Open paper from column `a` to `b` (outline included), 10 rows from `top`, held by a hand on each side.
    /// `flip` turns the right-hand page over toward the fold (0 to 1).
    private static func paper(_ c: inout PixelCanvas, from a: Int, to b: Int, top: Int, print: Bool, flip: Double? = nil,
                              look: Look) {
        let w = b - a + 1
        c.fill(a, top, w, 10, Palette.newsInk)
        c.fill(a + 1, top + 1, w - 2, 8, Palette.newsPaper)
        let mid = (a + b + 1) / 2
        if print {
            c.fill(a + 2, top + 2, w - 4, 1, Palette.newsInk)   // the masthead
            c.fill(a + 2, top + 4, mid - a - 3, 1, Palette.newsLine)
            c.fill(mid + 1, top + 4, b - mid - 2, 1, Palette.newsLine)
            c.fill(a + 2, top + 6, mid - a - 3, 1, Palette.newsLine)
            c.fill(mid + 1, top + 6, max(1, b - mid - 4), 1, Palette.newsLine)
            c.fill(mid, top + 4, 1, 4, Palette.newsFold)
        }
        if let flip {
            let edge = Int((Double(b - 1) - Double(b - 1 - mid) * flip).rounded())
            c.fill(mid + 1, top + 1, max(1, edge - mid), 8, Palette.newsPage)
            c.fill(edge, top + 1, 1, 8, Palette.newsFold)
        }
        hands(&c, left: a - 1, right: b, y: top + 3, look: look)
    }

    private static func foldedPaper(_ c: inout PixelCanvas, _ b: BodyFrame, _ look: Look) {
        let x = b.cx - 4, y = b.y0 + 10
        c.fill(x, y, 8, 7, Palette.newsInk)
        c.fill(x + 1, y + 1, 6, 5, Palette.newsPaper)
        c.fill(x + 2, y + 2, 4, 1, Palette.newsInk)
        hands(&c, left: x - 1, right: x + 7, y: y, look: look)
    }

    /// Little hands in the skin's colors: an outlined 2×3 nub with the fill showing on the outer side.
    private static func hands(_ c: inout PixelCanvas, left: Int, right: Int, y: Int, look: Look) {
        c.fill(left, y, 2, 3, look.skin.outline)
        c.set(left, y + 1, look.skin.fill)
        c.fill(right, y, 2, 3, look.skin.outline)
        c.set(right + 1, y + 1, look.skin.fill)
    }
}

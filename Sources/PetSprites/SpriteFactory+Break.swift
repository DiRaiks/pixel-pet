import PetCore

extension SpriteFactory {
    /// Time for a break: the bubble with a steaming mug, a look out at you and a blink now and then.
    static func breakHint(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.eyes = i == 9 ? .blink : .open
        s.lookX = -1; s.lookY = -1
        s.mouth = .tiny
        s.blush = 2
        c.body(s)
        mugBubble(steam: i % 2, &c)
    }

    /// The shared tool bubble with a mug of coffee and two wisps of steam that sway every frame.
    static func mugBubble(steam: Int, _ c: inout PixelCanvas) {
        toolBubble(&c)
        // A teal mug with a dark outline, coffee at the top and a handle, under two wisps of teal steam:
        // the old 4x4 brown mug with grey steam was a blob at 64 pt.
        c.pixelMap([
            "DDDDD.",
            "DCCCDD",
            "DMMMD.D",
            "DMMMDD",
        ], x: 3, y: 4, colors: ["D": Palette.keyboard, "C": Palette.coffee, "M": Palette.note])
        let wisps = steam == 0 ? [(4, 3), (5, 2), (6, 3)] : [(5, 3), (4, 2), (6, 2)]
        for (x, y) in wisps { c.set(x, y, Palette.tealLight) }
    }
}

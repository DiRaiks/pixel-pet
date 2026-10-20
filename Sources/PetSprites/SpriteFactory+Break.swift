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
        let ink = Palette.keyboard
        c.fill(3, 4, 4, 4, ink)
        c.fill(4, 5, 2, 2, Palette.mug)
        c.fill(4, 5, 2, 1, Palette.coffee)
        c.set(7, 5, ink); c.set(8, 6, ink); c.set(7, 7, ink)   // the handle
        let wisps = steam == 0 ? [(4, 3), (5, 2)] : [(5, 3), (4, 2)]
        for (x, y) in wisps { c.set(x, y, Palette.mugShade) }
    }
}

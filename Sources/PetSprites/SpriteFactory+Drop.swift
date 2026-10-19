import PetCore

/// LM's idle fidgets, in place of the cube's roll.
extension SpriteFactory {
    /// A drop falls from above onto his diamond and splashes into two arcs of spray; he jiggles like jelly,
    /// blinks, and is pleased, while the spray lands as two little puddles that dry up.
    static func drip(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        guard look.figure == .lidman else { return still(look, &c) }
        let keys: [(w: Int, h: Int, eyes: Eyes, mouth: Mouth)] = [
            (16, 14, .open, .flat), (16, 14, .open, .flat), (16, 14, .open, .flat), (17, 13, .squeeze, .open),
            (15, 15, .wide, .open), (17, 13, .wide, .open), (16, 14, .open, .open), (16, 14, .blink, .flat),
            (16, 14, .happy, .smile), (16, 14, .happy, .smile), (16, 14, .open, .smile), (16, 14, .open, .flat),
        ]
        let k = keys[i]
        var s = BodyStyle(look: look)
        s.w = k.w; s.h = k.h; s.eyes = k.eyes; s.mouth = k.mouth
        s.lookY = i < 3 ? -1 : 0
        s.blush = (8...10).contains(i) ? 2 : 0
        c.body(s)
        // The falling drop, its tip on the diamond's apex.
        if i == 1 { c.waterDrop(15, -2) }
        if i == 2 { c.waterDrop(15, 0) }
        // Spray flying out both ways and down.
        let spray: [Int: [(Int, Int)]] = [
            3: [(3, 3), (2, 2)], 4: [(5, 4), (4, 3)], 5: [(7, 7)], 6: [(8, 11)], 7: [(9, 16)],
        ]
        for (dx, y) in spray[i] ?? [] {
            c.fill(16 - dx, y, 1, 2, Palette.water); c.fill(15 + dx, y, 1, 2, Palette.water)
        }
        if i == 3 { c.set(15, 3, Palette.waterLight); c.set(16, 3, Palette.waterLight) }
        // Puddles where the spray landed, drying up.
        let puddle = [8: 3, 9: 2, 10: 1][i] ?? 0
        if puddle > 0 {
            c.fill(7 - puddle / 2, 27, puddle, 1, Palette.water)
            c.fill(25 - puddle / 2, 27, puddle, 1, Palette.water)
        }
    }

    /// Melts into a puddle: sinks and spreads, lies there blinking, then gathers up with a "bloop" into a
    /// tall drop and wobbles back to shape.
    static func melt(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        guard look.figure == .lidman else { return still(look, &c) }
        let keys: [(w: Int, h: Int, eyes: Eyes, mouth: Mouth)] = [
            (16, 14, .open, .flat), (17, 13, .half, .flat), (19, 11, .half, .wobble), (22, 8, .half, .wobble),
            (25, 6, .open, .wobble), (26, 5, .open, .wobble), (26, 5, .blink, .wobble), (26, 5, .open, .wobble),
            (20, 9, .wide, .open), (13, 17, .wide, .open), (18, 12, .squeeze, .smile), (15, 15, .open, .smile),
            (17, 13, .open, .smile), (16, 14, .open, .smile),
        ]
        let k = keys[i]
        var s = BodyStyle(look: look)
        s.w = k.w; s.h = k.h; s.eyes = k.eyes; s.mouth = k.mouth
        s.shadow = k.h >= 8
        c.body(s)
        // Ripples on the floor while he's a puddle.
        if (5...7).contains(i) {
            let r = 14 + (i - 5)
            c.set(16 - r, 26, Palette.waterLight); c.set(15 + r, 26, Palette.waterLight)
        }
    }
}

extension SpriteFactory {
    /// The cube has no diamond to drip on and no face for a puddle; it just stands there.
    static func still(_ look: Look, _ c: inout PixelCanvas) {
        c.body(BodyStyle(look: look))
    }
}

extension PixelCanvas {
    /// A falling drop of water, 3 wide and 4 tall, with a light glint.
    mutating func waterDrop(_ x: Int, _ y: Int) {
        set(x + 1, y, Palette.water)
        fill(x, y + 1, 3, 2, Palette.water)
        set(x + 1, y + 3, Palette.water)
        set(x, y + 1, Palette.waterLight)
    }
}

import CoreGraphics
import Foundation
import PetCore

/// Procedural frames for every PetState. Started as a port of docs/prototype/sprites.html; v2 adds the
/// hue-shifted style, skins and accessories, per-frame timing (see PetState) and the newer moves.
/// Shadows with an odd width snap to whole pixels instead of the prototype canvas's half-pixel blur.
/// Can be replaced by an Aseprite sprite sheet later; callers only see canvases and images.
public enum SpriteFactory {
    /// `gaze` points the eyes (cursor following, glances); only states with a plain open-eyed face use it.
    public static func frames(for state: PetState, agentCubes: Bool = true, gaze: Gaze? = nil,
                              look: Look = .standard, props: WorkProps = []) -> [PixelCanvas] {
        (0..<state.frameCount).map { frame(for: state, index: $0, agentCubes: agentCubes, gaze: gaze, look: look, props: props) }
    }

    /// One frame on its own, for variants made on demand (gaze, drain, look) without redrawing the whole state.
    /// `props` only shows at the keyboard (working and its moments).
    public static func frame(for state: PetState, index i: Int, agentCubes: Bool = true, gaze: Gaze? = nil,
                             look: Look = .standard, props: WorkProps = []) -> PixelCanvas {
        var c = PixelCanvas()
        draw(state, frame: i, cubes: agentCubes, gaze: state == .idle ? gaze : nil, look: look, props: props, on: &c)
        return c
    }

    /// 18x18 template icon: cube silhouette with the eyes and mouth punched out.
    public static func menuIcon() -> PixelCanvas {
        var c = PixelCanvas(width: 18, height: 18)
        let t = Palette.template
        c.fill(2, 2, 14, 14, t)
        for (x, y) in [(2, 2), (15, 2), (2, 15), (15, 15)] { c.pixels[y * 18 + x] = nil }
        for (x, y, w, h) in [(5, 7, 2, 3), (11, 7, 2, 3), (8, 12, 2, 1)] {
            for yy in y..<(y + h) { for xx in x..<(x + w) { c.pixels[yy * 18 + xx] = nil } }
        }
        return c
    }

    // [width, height, dy] keyframes: anticipation -> stretch -> airborne -> land squash -> settle.
    static let hop = [(16, 14, 0), (18, 13, 0), (18, 11, 0), (14, 16, -1), (14, 17, -4), (14, 16, -7), (14, 15, -8),
                      (14, 15, -8), (14, 16, -6), (14, 17, -3), (20, 10, 0), (18, 12, 0), (16, 15, 0), (16, 14, 0)]
    static let jump = [(16, 14, 0), (18, 12, 0), (20, 10, 0), (14, 17, -3), (14, 17, -7), (14, 16, -10), (14, 15, -11),
                       (14, 15, -11), (14, 16, -9), (14, 17, -5), (14, 16, -1), (20, 10, 0), (18, 12, 0), (16, 15, 0),
                       (16, 14, 0), (16, 14, 0)]

    public static func images(for state: PetState) -> [CGImage] {
        frames(for: state).compactMap { $0.makeImage() }
    }

    static func draw(_ state: PetState, frame i: Int, cubes: Bool, gaze: Gaze?, look: Look, props: WorkProps = [],
                     on c: inout PixelCanvas) {
        switch state {
        case .idle: idle(i, look, gaze, &c)
        case .hop: hopFrame(i, look, &c)
        case .working: working(i, cubes, look, props, &c)
        case .workSip: workSip(i, look, props, &c)
        case .workStretch: workStretch(i, look, props, &c)
        case .workThink: workThink(i, look, props, &c)
        case .workRush: workRush(i, look, props, &c)
        case .glanceLeft: glance(i, -1, look, props, &c)
        case .glanceRight: glance(i, 1, look, props, &c)
        case .touchKey: touchKey(i, look, &c)
        case .touchDone: touchDone(i, look, &c)
        case .touchKeyHome: touchKeyHome(i, cubes, look, &c)
        case .newspaperOpen: newspaperOpen(i, look, &c)
        case .newspaper: newspaper(i, look, &c)
        case .breakHint: breakHint(i, look, &c)
        case .catchOpen: catchOpen(i, look, &c)
        case .swallow: swallow(i, look, &c)
        case .shakeHead: shakeHead(i, look, &c)
        case .question: question(i, look, &c)
        case .refill: refill(i, look, &c)
        case .exhausted: exhausted(i, look, &c)
        case .spawn: spawn(i, look, &c)
        case .recall: recall(i, look, &c)
        case .compact: compact(i, look, &c)
        case .tired: tired(i, look, &c)
        case .plugIn: plugIn(i, look, &c)
        case .thrown: thrown(i, look, &c)
        case .dizzy: dizzy(i, look, &c)
        case .splatRight: splat(i, look, &c)
        case .hookah: hookah(i, look, &c)
        case .hookahCloud: hookah(i, look, &c, cloud: true)
        case .meetingSoon: meetingSoon(i, look, &c)
        case .meetingNow: meetingNow(i, look, &c)
        case .splatLeft:
            var right = PixelCanvas()
            splat(i, look, &right)
            c.blit(right.mirrored(), x: 0, y: 0)
        case .alert: alert(i, cubes, look, &c)
        case .celebrate: celebrate(i, look, &c)
        case .sleep: sleep(i, look, &c)
        case .lowLimit: lowLimit(i, look, &c)
        case .error: error(i, cubes, look, &c)
        case .peek: peek(i, cubes, look, &c)
        case .burrowed: burrowed(i, cubes, &c)
        case .peekHold: peekHold(i, cubes, look, &c)
        case .dive: dive(i, cubes, look, &c)
        case .dragged: dragged(i, look, &c)
        case .drop: drop(i, look, &c)
        case .talk: talk(i, look, &c)
        case .yawn: yawn(i, look, &c)
        case .shy: shy(i, look, &c)
        case .angry: angry(i, look, &c)
        case .flip: flip(i, look, &c)
        case .tumble: tumble(i, look, &c)
        case .drip: drip(i, look, &c)
        case .melt: melt(i, look, &c)
        case .wave: wave(i, look, &c)
        case .launch: launch(i, look, &c)
        case .purr: purr(i, look, &c)
        case .sneeze: sneeze(i, look, &c)
        case .headphonesOn: headphonesOn(i, look, &c)
        case .headphonesOff: headphonesOff(i, look, &c)
        case .music: music(i, look, &c)
        case .onAir: onAir(i, look, &c)
        case .overheated: overheated(i, look, &c)
        case .lowPower: lowPower(i, look, &c)
        case .offline: offline(i, look, &c)
        case .batteryFull: batteryFull(i, look, &c)
        case .screenshot: screenshot(i, look, &c)
        case .darkMode: darkMode(i, look, &c)
        case .lightMode: lightMode(i, look, &c)
        }
        overlays(state, i, props, &c)
    }

    /// Breathes with the highlight instead of the outline, blinks twice now and then, glances around.
    static func idle(_ i: Int, _ look: Look, _ gaze: Gaze?, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.highlightShift = i % 8 < 4 ? 0 : 1
        s.eyes = i == 10 || i == 12 ? .half : i == 11 ? .blink : .open
        // Its own glance around (frames 18-21) gives way to whatever it's looking at.
        s.lookX = gaze?.x ?? ((18...21).contains(i) ? -1 : 0)
        s.lookY = gaze?.y ?? 0
        c.body(s)
    }

    static func hopFrame(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        let (w, h, dy) = hop[i]
        var s = BodyStyle(look: look)
        s.w = w; s.h = h; s.dy = dy
        s.eyes = i == 1 || i == 2 ? .half : i == 10 ? .squeeze : .open
        s.lookY = dy < -2 ? -1 : 0
        s.mouth = dy < 0 ? .open : .flat
        c.body(s)
    }

    /// Focused typing, played from `TypingScript`: bursts of uneven length and pace with pauses between them.
    /// No smile here: seen every second for hours it got old; smiles come with the moments.
    static func working(_ i: Int, _ cubes: Bool, _ look: Look, _ props: WorkProps = [], _ c: inout PixelCanvas) {
        let beat = TypingScript.beats[i].beat
        var s = deskBody(look, props)
        var lit: [Int] = []
        switch beat {
        case .down(let key): s.h = 13; lit = [9 + 2 * key]
        case .up, .hitch: break
        case .read: s.lookY = 0; s.eyes = .open
        case .blink: s.lookY = 0; s.eyes = .blink
        }
        if beat != .read, beat != .blink { s.eyes = .down }
        s.mouth = .flat
        c.body(s)
        // Beats run 50–650 ms, so steam and spinning blocks follow the clock (100 ms steps), not the beat.
        let tick = Int(TypingScript.starts[i] / 100)
        desk(&c, props, lit: lit, steam: tick % 6 < 3 ? tick % 3 : 0)
        guard cubes else { return }
        c.agentCube(25, 24, Palette.teal, spin: tick)
        c.agentCube(25, 20, Palette.teal, spin: tick + 4)
    }

    /// The body at the desk: lower, eyes on the keys, the headband once work has gone on long.
    static func deskBody(_ look: Look, _ props: WorkProps) -> BodyStyle {
        var s = BodyStyle(look: look)
        s.by = 25; s.lookY = 1
        s.headband = props.contains(.headband)
        return s
    }

    /// The keyboard sits in front, hiding the bottom of the body: it reads as typing at a desk. Columns 24+
    /// (and 0-4) belong to the agent stacks, so the desk stays within 8...23. The mug stands at its right end.
    static func desk(_ c: inout PixelCanvas, _ props: WorkProps, lit: [Int] = [], steam: Int = 0, mugShown: Bool = true) {
        c.fill(8, 22, 16, 4, Palette.keyboard)
        c.fill(9, 22, 14, 1, Palette.keyboardTop)
        for x in stride(from: 9, through: 22, by: 2) { c.set(x, 23, Palette.keyboardTop) }
        for x in lit { c.set(x, 23, Palette.tealLight) }
        if props.contains(.mug), mugShown { c.mug(19, 19, steam: steam, tea: props.contains(.tea)) }
        if props.contains(.lamp) { deskLamp(&c) }
    }

    /// An architect's desk lamp: base and pole in the gap left of the body, the arm reaching over the head,
    /// a cone shade with a lit bulb, and a warm beam falling over the pet and the keys.
    static func deskLamp(_ c: inout PixelCanvas) {
        let metal = Palette.lamp
        c.fill(5, 25, 4, 1, metal)                       // base
        c.fill(6, 8, 1, 17, metal)                       // pole
        for (x, y) in [(7, 7), (8, 7), (9, 6), (10, 6)] { c.set(x, y, metal) }   // arm
        c.fill(11, 5, 4, 1, metal)                       // shade, top
        c.fill(10, 6, 6, 1, metal)
        c.fill(9, 7, 8, 1, metal)                        // shade, rim
        c.fill(11, 8, 4, 1, Palette.keyGoldLit)          // bulb
        // The beam widens as it falls; translucent, so the pet shows through it.
        for y in 9...22 {
            let half = 1 + (y - 9) / 4
            for x in (13 - half)...(12 + half) where (8...23).contains(x) { c.tint(x, y, Palette.lampLight) }
        }
    }

    /// A sip of coffee: stops typing, lifts the mug to the mouth, eyes closed, a contented sigh. Brings its own
    /// mug when there isn't one on the desk yet.
    static func workSip(_ i: Int, _ look: Look, _ props: WorkProps, _ c: inout PixelCanvas) {
        let mugAt = [(19, 19), (18, 17), (16, 16), (15, 15), (15, 15), (15, 15), (17, 17), (19, 19), (19, 19), (19, 19)]
        var s = deskBody(look, props)
        s.lookY = 0
        s.eyes = i == 0 ? .open : (2...5).contains(i) ? .closed : (6...8).contains(i) ? .happy : .down
        s.mouth = (7...8).contains(i) ? .smile : .flat
        s.blush = (4...8).contains(i) ? 3 : 2
        if i == 0 { s.lookX = 1 }
        c.body(s)
        desk(&c, props, mugShown: false)
        let (x, y) = mugAt[i]
        c.mug(x, y, steam: (3...5).contains(i) ? 1 + i % 2 : 0, tea: props.contains(.tea))
    }

    /// A stretch at the desk: grows tall and thin with eyes squeezed shut, a little crackle at the sides.
    static func workStretch(_ i: Int, _ look: Look, _ props: WorkProps, _ c: inout PixelCanvas) {
        let keys: [(Int, Int, Eyes, Mouth)] = [
            (16, 14, .open, .flat), (15, 15, .half, .flat), (14, 17, .closed, .open), (13, 18, .squeeze, .open),
            (13, 18, .closed, .open), (14, 17, .closed, .flat), (17, 13, .blink, .flat), (16, 14, .half, .flat),
            (16, 14, .open, .smile), (16, 14, .down, .flat),
        ]
        let (w, h, eyes, mouth) = keys[i]
        var s = deskBody(look, props)
        s.w = w; s.h = h; s.eyes = eyes; s.mouth = mouth; s.lookY = 0
        let b = c.body(s)
        desk(&c, props)
        guard (3...4).contains(i) else { return }
        // Crackle: two tiny sparks beside the top corners.
        for x in [b.x0 - 2, b.x0 + w + 1] {
            c.set(x, b.y0 + 1, Palette.white)
            c.set(x + (x < b.x0 ? -1 : 1), b.y0, Palette.white)
        }
    }

    /// Stops typing to think: eyes up and to the side, thought dots appear one by one, then an idea lights
    /// up with a smile and the typing starts again.
    static func workThink(_ i: Int, _ look: Look, _ props: WorkProps, _ c: inout PixelCanvas) {
        var s = deskBody(look, props)
        let idea = (8...9).contains(i)
        s.lookX = i >= 10 ? 0 : 1
        s.lookY = i >= 10 ? 1 : -1
        s.eyes = i >= 10 ? .down : idea ? .wide : (i == 5 ? .blink : .open)
        s.mouth = idea || i >= 10 ? .smile : .tiny
        c.body(s)
        desk(&c, props, lit: i >= 10 ? [13 + (i - 10) * 6] : [])
        let dots = min(3, max(0, i - 1))
        if !idea, i < 10 {
            for k in 0..<dots { c.set(19 + k * 2, 8 - k, Palette.shade) }
        }
        if idea {
            c.set(23, 4, Palette.amber); c.fill(22, 5, 3, 1, Palette.amber); c.set(23, 6, Palette.amber)
            if i == 8 { c.set(21, 3, Palette.amber); c.set(25, 3, Palette.amber) }
        }
    }

    /// A burst of fast typing: every frame a key, a little shake, speed lines beside the keyboard.
    static func workRush(_ i: Int, _ look: Look, _ props: WorkProps, _ c: inout PixelCanvas) {
        var s = deskBody(look, props)
        let done = i == 16
        s.dx = done ? 0 : (i % 4 == 1 ? 1 : i % 4 == 3 ? -1 : 0)
        s.h = done ? 14 : 14 - i % 2
        s.eyes = done ? .happy : .down
        s.mouth = done ? .smile : .flat
        c.body(s)
        let keys = [9, 21, 13, 17, 11, 19, 15, 9, 21, 11, 17, 13, 19, 15, 21, 9]
        desk(&c, props, lit: done ? [] : [keys[i], keys[(i + 5) % keys.count]])
        guard !done else { return }
        if i % 2 == 0 { c.set(6, 23, Palette.keyboardTop); c.set(25, 23, Palette.keyboardTop) }
        else { c.set(6, 24, Palette.keyboardTop); c.set(25, 24, Palette.keyboardTop) }
    }

    /// Looks over at the agent blocks on one side (-1: Codex on the left, 1: Claude on the right), then back
    /// to the keys.
    static func glance(_ i: Int, _ side: Int, _ look: Look, _ props: WorkProps, _ c: inout PixelCanvas) {
        var s = deskBody(look, props)
        let away = (1...5).contains(i)
        s.lookX = away ? side * 2 : (i == 0 || i == 6 ? side : 0)
        s.lookY = away ? 0 : 1
        s.dx = away ? side : 0
        s.eyes = i == 4 ? .blink : i == 7 ? .down : .open
        c.body(s)
        desk(&c, props)
    }

    /// Holds up a little YubiKey in front: looks down at it, then up at you, the gold pad blinking like the
    /// real one and rings pulsing out of it, until it's touched.
    static func touchKey(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        let atKey = i < 4
        s.lookY = atKey ? 1 : 0
        s.lookX = atKey ? 0 : 0
        s.eyes = atKey ? .down : (i == 6 ? .blink : .wide)
        s.mouth = atKey ? .flat : .open
        s.blush = 2
        let b = c.body(s)
        let bob = i % 4 < 2 ? 0 : -1
        yubiKey(&c, x: b.cx - 4, y: 21 + bob, lit: i % 2 == 0)
        // Rings around the pad: one pixel out, then two, then gone.
        let (px, py) = (b.cx + 1, 21 + bob + 1)
        let r = i % 4
        if r == 1 || r == 2 {
            let d = r + 1
            for (dx, dy) in [(-d, 0), (d + 1, 0), (0, -d), (1, -d), (0, d + 1), (1, d + 1)] {
                c.set(px + dx, py + dy - (dy > 0 ? 1 : 0), Palette.keyGoldLit)
            }
        }
    }

    /// From home: out of the hole with the key held up under it, pad blinking.
    static func touchKeyHome(_ i: Int, _ props: Bool, _ look: Look, _ c: inout PixelCanvas) {
        home(&c, look: look, by: 16, lookX: 0, eyes: i < 4 ? .down : (i == 6 ? .blink : .wide), props: props, glow: .glow)
        let bob = i % 4 < 2 ? 0 : -1
        yubiKey(&c, x: 12, y: 17 + bob, lit: i % 2 == 0)
        if i % 4 == 1 || i % 4 == 2 {
            let y = 17 + bob + 1
            c.set(15, y, Palette.keyGoldLit); c.set(20, y, Palette.keyGoldLit)
        }
    }

    /// Touched: the key goes away, a little hop and a check mark.
    static func touchDone(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        let hop = [0, -1, -2, -1, 0, 0, 0, 0]
        var s = BodyStyle(look: look)
        s.dy = hop[i]
        s.eyes = i < 2 ? .open : .happy
        s.mouth = .smile
        s.blush = i >= 3 ? 3 : 2
        let b = c.body(s)
        if i < 2 { yubiKey(&c, x: b.cx - 4, y: 22 + i, lit: false) }
        guard i >= 3 else { return }
        // Check mark above the head.
        let (x, y) = (b.cx + 6, b.y0 - 5)
        for (dx, dy) in [(0, 2), (1, 3), (2, 2), (3, 1), (4, 0)] { c.set(x + dx, y + dy, Palette.tealLight) }
        for (dx, dy) in [(0, 3), (1, 4), (2, 3), (3, 2), (4, 1)] { c.set(x + dx, y + dy, Palette.teal) }
    }

    /// A YubiKey lying sideways: plug on the left, black body, round gold pad near the right end.
    static func yubiKey(_ c: inout PixelCanvas, x: Int, y: Int, lit: Bool) {
        c.fill(x, y + 1, 2, 2, Palette.keyPlug)
        c.fill(x + 2, y, 8, 4, Palette.keyBody)
        c.fill(x + 5, y + 1, 2, 2, lit ? Palette.keyGoldLit : Palette.keyGold)
        c.set(x + 9, y, Palette.keyPlug)   // the key ring hole
    }

    static func alert(_ i: Int, _ cubes: Bool, _ look: Look, _ c: inout PixelCanvas) {
        let hops = [0, 0, -1, -2, -3, -2, -1, 0, 0, 0, 0, 0]
        var s = BodyStyle(look: look)
        s.cx = 14; s.dy = hops[i]
        s.w = i == 7 ? 18 : 16; s.h = i == 7 ? 12 : 14
        s.eyes = .wide; s.lookX = 1; s.mouth = .open; s.blush = 0
        let b = c.body(s)
        if i % 6 < 4 {
            let x = b.cx - 1 + look.headMarkShift
            c.fill(x, b.y0 - 7, 2, 3, Palette.amber)
            c.fill(x, b.y0 - 3, 2, 1, Palette.amber)
        }
        guard cubes else { return }
        let cy = 24 - ((i + 6) % 12 < 3 ? 1 : 0)
        c.agentCube(26, cy, Palette.amber)
        if i % 4 < 2 { c.set(27, cy + 1, Palette.amberDark) }
    }

    static func celebrate(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        let (w, h, dy) = jump[i]
        var s = BodyStyle(look: look)
        s.w = w; s.h = h; s.dy = dy
        s.eyes = (3...12).contains(i) ? .happy : .open
        s.mouth = .smile
        s.blush = i >= 11 ? 3 : 2
        c.body(s)
        guard (5...14).contains(i) else { return }
        let q = Double(i - 4)
        let offsets = [(-q - 2, -q / 2), (q + 2, -q / 2), (-q, q / 3 - 6), (q, q / 3 - 6)]
        for (k, (x, y)) in offsets.enumerated() {
            c.sparkle(16 + jsRound(x), 12 + jsRound(y), k % 2 == 1 ? Palette.amber : Palette.teal, big: q < 6)
        }
    }

    /// Asleep in a nightcap, a bubble growing and popping at the nose.
    static func sleep(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        let exhale = i % 4 < 2 ? 0 : 1
        var s = BodyStyle(look: look)
        s.w = 16 + 2 * exhale; s.h = 14 - exhale
        s.eyes = .closed; s.mouth = .none; s.nightcap = true
        let b = c.body(s)
        let radius = [0, 0, 1, 1, 2, 2, 3, 3, 0, 0, 0, 0][i]
        let bx = b.cx + 5, by = b.y0 + 9
        if radius > 0 {
            c.circle(bx, by, radius: radius, Palette.bubble)
            c.set(bx - 1, by - radius + 1, Palette.white)
        }
        if i == 8 { c.sparkle(bx, by, Palette.bubble, big: true) }
    }

    static func lowLimit(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.w = 14; s.h = 13
        s.dx = i < 6 && i % 2 == 1 ? 1 : 0
        s.eyes = .worry; s.mouth = .wobble; s.drain = 6; s.blush = 0
        let b = c.body(s)
        let y = b.y0 + 2 + i / 2
        if y < b.y0 + 12 {
            c.set(b.x0 + 14, y, Palette.sweat)
            c.set(b.x0 + 14, y + 1, Palette.sweatDark)
        }
    }

    /// A red flash and a shake, then dizzy: spiral eyes, stars circling the head.
    static func error(_ i: Int, _ cubes: Bool, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.blush = 0
        if i < 6 {
            let shake = [-2, 2, -2, 2, -1, 1]
            s.cx = 14; s.dx = shake[i]; s.eyes = .cross; s.mouth = .wobble
            if (1...4).contains(i) { s.skin = .error }
            c.body(s)
        } else {
            let k = i - 6
            let sway = [0, 1, 1, 0, -1, -1, 0, 1, 0, 0][k]
            s.cx = 14; s.dx = sway; s.eyes = .spiral; s.mouth = .wobble
            let b = c.body(s)
            for n in 0..<3 {
                let t = (Double(k) / 10 + Double(n) / 3) * 2 * .pi
                let x = b.cx + jsRound(cos(t) * 5), y = b.y0 - 3 + jsRound(sin(t) * 2)
                c.sparkle(x, y, n % 2 == 1 ? Palette.amber : Palette.amberLight, big: true)
            }
        }
        guard cubes else { return }
        c.agentCube(26, 24, Palette.errorFill)
        if i % 4 < 2 { c.set(27, 25, Palette.errorDark) }
    }

    static func peek(_ i: Int, _ props: Bool, _ look: Look, _ c: inout PixelCanvas) {
        var by = 6
        if (6...11).contains(i) {
            let t = 1 - Double(i - 5) / 6
            by = 6 + jsRound(10 * (1 - t * t * t))
        } else if (12...21).contains(i) {
            by = 16
        } else if (22...24).contains(i) {
            by = 16 - jsRound(10 * Double(i - 21) / 3)
        }
        let lookX = (13...16).contains(i) ? -1 : (17...20).contains(i) ? 1 : 0
        home(&c, look: look, by: by, lookX: lookX, eyes: i == 21 ? .blink : .open, props: props,
             glow: i == 3 || i == 26 ? .glowBlink : .glow)
    }

    /// Hidden at home: only two glowing eyes in the dark, glancing around and blinking now and then.
    static func burrowed(_ i: Int, _ props: Bool, _ c: inout PixelCanvas) {
        let look = (4...6).contains(i) ? -1 : (12...13).contains(i) ? 1 : 0
        drawHole(&c, props: props)
        c.eyes(16 + look, 1, i == 10 ? .glowBlink : .glow)
    }

    /// Half out of the hole, watching: used while an agent waits or something failed.
    static func peekHold(_ i: Int, _ props: Bool, _ look: Look, _ c: inout PixelCanvas) {
        let looks = [-1, -1, -1, 0, 1, 1, 1, 0, 0, 0]
        home(&c, look: look, by: 16, lookX: looks[i], eyes: i == 8 ? .blink : .wide, props: props, glow: .glow)
    }

    /// Pulled into the hole after a drop near home: squash, then a fast slide up.
    static func dive(_ i: Int, _ props: Bool, _ look: Look, _ c: inout PixelCanvas) {
        let keys = [(18, 12, 16), (14, 16, 15), (14, 16, 12), (14, 15, 9), (16, 14, 7), (16, 14, 6)]
        let (w, h, by) = keys[i]
        home(&c, look: look, by: by, w: w, h: h, lookX: 0, eyes: i == 0 ? .squeeze : .open, props: props, glow: .glow)
    }

    /// LM comes out of the hole 2 rows less than the cube: just his eyes and the round bottom of the drop.
    static let lidManPeekRaise = 2

    static func home(_ c: inout PixelCanvas, look: Look, by: Int, w: Int = 16, h: Int = 14, lookX: Int,
                             eyes: Eyes, props: Bool, glow: Eyes) {
        var s = BodyStyle(look: look)
        s.by = by - (look.figure == .lidman ? lidManPeekRaise : 0); s.w = w; s.h = h; s.shadow = false
        s.inHole = true
        s.lookX = lookX
        s.eyes = eyes
        c.body(s)
        drawHole(&c, props: props)
        if by <= 8 { c.eyes(16, 1, glow) }
    }

    /// The black hole: the hardware notch, or the burrow drawn on screens without one.
    private static func drawHole(_ c: inout PixelCanvas, props: Bool) {
        c.fill(5, 0, 22, 5, Palette.notch)
        c.fill(6, 5, 20, 1, Palette.notch)
        if props {
            c.fill(0, 0, 5, 2, Palette.menuBar)
            c.fill(27, 0, 5, 2, Palette.menuBar)
        }
    }

    /// Held by the middle: dangles a little and swings, nothing drawn over its head.
    static func dragged(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.w = 14; s.h = 17; s.by = 23
        s.dx = jsRound(sin(Double(i) / 10 * .pi * 2) * 1.4)
        s.eyes = .wide; s.mouth = .open
        c.body(s)
    }

    /// Let go: falls, squashes flat, then wobbles like jelly with bounces that die down.
    static func drop(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        let keys = [(14, 16, -9), (14, 17, -6), (14, 17, -3), (14, 16, -1), (22, 8, 0), (12, 18, -2),
                    (19, 11, 0), (14, 16, -1), (17, 12, 0), (15, 15, 0), (16, 13, 0), (16, 14, 0)]
        let (w, h, dy) = keys[i]
        var s = BodyStyle(look: look)
        s.w = w; s.h = h; s.dy = dy
        s.eyes = i == 4 ? .squeeze : i < 4 ? .wide : .open
        s.mouth = i < 5 ? .open : .smile
        s.blush = i >= 6 ? 2 : 0
        c.body(s)
    }

    static func talk(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        let mouths: [Mouth] = [.open, .flat, .smile, .flat, .open, .flat, .flat, .smile]
        var s = BodyStyle(look: look)
        // Shifted toward the bubble, but clear of the Codex column on the left.
        s.cx = 12; s.w = 14; s.lookX = 1
        s.eyes = i == 6 ? .blink : .open
        s.mouth = mouths[i]
        c.body(s)
        c.fill(19, 6, 12, 9, look.skin.outline)
        c.fill(20, 7, 10, 7, Palette.white)
        c.set(19, 15, look.skin.outline); c.set(18, 16, look.skin.outline); c.set(20, 14, Palette.white)
        let first = min(7, (i + 1) * 2), second = max(0, min(5, (i - 2) * 2))
        c.fill(21, 9, first, 1, look.skin.shade)
        if second > 0 { c.fill(21, 11, second, 1, look.skin.shade) }
    }

    /// A rare idle fidget: stretches tall with a big yawn, a tear, then settles.
    static func yawn(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        let keys: [(Int, Int, Eyes, Mouth)] = [
            (16, 14, .open, .flat), (17, 13, .half, .flat), (13, 17, .closed, .open), (12, 19, .closed, .yawn),
            (12, 19, .closed, .yawn), (13, 17, .closed, .open), (18, 12, .closed, .flat), (16, 14, .blink, .flat),
            (16, 14, .half, .flat), (16, 14, .open, .smile),
        ]
        let (w, h, eyes, mouth) = keys[i]
        var s = BodyStyle(look: look)
        s.w = w; s.h = h; s.eyes = eyes; s.mouth = mouth
        let b = c.body(s)
        if (4...6).contains(i) { c.set(b.x0 + 1, b.y0 + 6, Palette.sweat) }
    }

    /// Fussed over (cursor lingering): looks, then looks away blushing, a little heart.
    static func shy(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        var s = BodyStyle(look: look)
        s.eyes = i <= 3 ? .open : i <= 7 ? .shy : .happy
        s.blush = i <= 3 ? 2 : 3
        s.lookX = i <= 3 ? min(1, i) : -1
        s.mouth = i >= 4 ? .wobble : .flat
        c.body(s)
        if (5...7).contains(i) { c.set(6, 9, Palette.pink); c.set(5, 8, Palette.pink); c.set(7, 8, Palette.pink) }
    }

    /// Clicked too often: flinches, then puffs up with a frown, a cross mark and steam.
    static func angry(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        let flinch = i < 6 && i % 2 == 1, puffed = i >= 6
        var s = BodyStyle(look: look)
        s.w = puffed ? 18 : 16; s.h = puffed ? 15 : 14
        s.eyes = i < 6 ? (flinch ? .squeeze : .open) : .half
        s.brow = i >= 5 ? .angry : nil
        s.mouth = puffed ? .pout : .flat
        s.blush = 0
        let b = c.body(s)
        guard puffed else { return }
        let r = Palette.errorFill, mx = b.x0 + s.w - 3, my = b.y0 - 1
        c.set(mx - 1, my, r); c.set(mx + 1, my, r); c.set(mx, my - 1, r); c.set(mx, my + 1, r)
        for k in 0..<2 {
            let t = (i - 6 + k * 2) % 6
            c.set(b.x0 + 2 + k * 11, b.y0 - 2 - t, Palette.steam)
            c.set(b.x0 + 3 + k * 11, b.y0 - 3 - t, Palette.steam)
        }
    }

    /// Big task done: a somersault at the top of the jump and confetti raining down.
    static func flip(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        // While turning, the body is square and the jump peaks lower, so the corners stay on the canvas.
        let keys = [(16, 14, 0, 0.0), (18, 12, 0, 0), (20, 10, 0, 0), (14, 17, -5, 0), (14, 14, -8, 60),
                    (14, 14, -9, 150), (14, 14, -9, 240), (14, 14, -8, 320), (14, 17, -5, 360), (20, 10, 0, 0),
                    (18, 12, 0, 0), (16, 15, 0, 0), (16, 14, 0, 0), (16, 14, 0, 0), (16, 14, 0, 0), (16, 14, 0, 0)]
        let (w, h, dy, angle) = keys[i]
        var s = BodyStyle(look: look)
        s.w = w; s.h = h; s.dy = dy
        s.rotation = angle.truncatingRemainder(dividingBy: 360)
        s.eyes = i >= 3 ? .happy : .open
        s.mouth = .smile
        s.blush = i >= 9 ? 3 : 2
        c.body(s)
        guard i >= 6 else { return }
        let colors = [Palette.amber, Palette.teal, Palette.pink, Palette.blue, Palette.amberLight, Palette.green]
        let t = Double(i - 6)
        for p in 0..<14 {
            let x = Double((p * 37) % 30 + 1) + Double((p * 13) % 5 - 2) * t * 0.3
            let y = 2 + t * 1.3 + Double((p * 7) % 4) + t * t * 0.12
            if y < 27 { c.set(jsRound(x), jsRound(y), colors[p % colors.count]) }
        }
    }

    /// A roll over its own edge to the right and back, pivoting on the bottom corner.
    static func tumble(_ i: Int, _ look: Look, _ c: inout PixelCanvas) {
        let dir = i < 7 ? 1.0 : -1.0, k = i % 7, start = i < 7 ? 9.0 : 23.0
        let angles = [0.0, 0, 22, 45, 68, 90, 90]
        let side = 14.0
        let squash = k == 1 || k == 5
        var s = BodyStyle(look: look)
        s.w = squash ? 16 : 14; s.h = squash ? 12 : 14
        s.eyes = (2...4).contains(k) ? .squeeze : .open
        s.mouth = (2...4).contains(k) ? .open : .flat
        if (2...4).contains(k) {
            // Pivot at the bottom corner in the direction of travel.
            let a = angles[k] * dir * .pi / 180
            let px = start + dir * side / 2, py = 26.0
            let vx = -dir * side / 2, vy = -side / 2
            let cx = px + vx * cos(a) - vy * sin(a), cy = py + vx * sin(a) + vy * cos(a)
            s.cx = jsRound(cx); s.by = jsRound(cy + Double(s.h) / 2)
            s.rotation = angles[k] * dir
        } else {
            s.cx = Int(k >= 5 ? start + dir * side : start)
        }
        c.body(s)
    }
}

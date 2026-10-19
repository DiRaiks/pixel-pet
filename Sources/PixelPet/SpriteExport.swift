import AppKit
import ImageIO
import PetCore
import PetSprites
import UniformTypeIdentifiers

/// Debug aid (`--export-sprites <dir> [skin] [accessory]`): every state as a ×4 PNG strip of its frames,
/// for reviewing the art without running each animation.
enum SpriteExport {
    static func run(to directory: URL, look: Look) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scale = 4, gap = 2
        for state in PetState.allCases {
            let frames = SpriteFactory.frames(for: state, agentCubes: false, look: look)
            let width = frames.count * (32 + gap) * scale, height = 32 * scale
            guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.interpolationQuality = .none
            ctx.setFillColor(CGColor(red: 0.945, green: 0.937, blue: 0.91, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            for (i, frame) in frames.enumerated() {
                guard let image = frame.makeImage() else { continue }
                ctx.draw(image, in: CGRect(x: i * (32 + gap) * scale, y: 0, width: 32 * scale, height: 32 * scale))
            }
            guard let strip = ctx.makeImage(),
                  let out = CGImageDestinationCreateWithURL(directory.appendingPathComponent("\(state.rawValue).png") as CFURL,
                                                            UTType.png.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(out, strip, nil)
            CGImageDestinationFinalize(out)
        }
    }
}

/// `--export-readme <dir>`: the animated pictures in the README, drawn by the same code as the app so they
/// never drift from it. Animated PNG rather than GIF: the soft shadow needs real alpha, and GitHub plays APNG.
/// Each clip sits on a rounded light tile, so it reads the same on light and dark pages.
enum ReadmeExport {
    struct Clip {
        var state: PetState
        /// Seconds to play; nil plays the state once (one-shots) or one full loop.
        var seconds: Double?
        var cubes: [AgentCube] = []
        /// Codex agents, in the left column.
        var codex: [AgentCube] = []
        var look = Look.standard
        var drain = 0
        /// Home states hang from the top edge of the screen: draw the menu bar above them.
        var menuBar = false
    }

    static let background = CGColor(red: 0.945, green: 0.937, blue: 0.91, alpha: 1)
    static let stackBeat = 0.1
    static let minDelay = 0.02

    static func run(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let work: [AgentCube] = [.init(status: .working, subagents: 1), .init(status: .working, subagents: 0),
                                 .init(status: .idle, subagents: 0)]
        let rest = Clip(state: .idle, seconds: 0.8)
        let codex: [AgentCube] = [.init(status: .working, subagents: 0), .init(status: .idle, subagents: 0)]
        let clips: [(String, [Clip])] = [
            ("idle", [Clip(state: .idle)]),
            ("working", [Clip(state: .working, seconds: 3, cubes: work)]),
            ("claude-and-codex", [Clip(state: .working, seconds: 3, cubes: work, codex: codex)]),
            ("alert", [Clip(state: .alert, seconds: 3, cubes: [.init(status: .waiting, subagents: 0)] + work.prefix(1))]),
            ("error", [Clip(state: .error, seconds: nil, cubes: [.init(status: .failed, subagents: 0)]), rest]),
            ("low-limit", [Clip(state: .lowLimit, seconds: 3.2, drain: 7)]),
            ("sleep", [Clip(state: .sleep)]),
            ("celebrate", [Clip(state: .celebrate), rest]),
            ("flip", [Clip(state: .flip), rest]),
            ("hop", [Clip(state: .hop), rest]),
            ("dragged", [Clip(state: .dragged, seconds: 2), Clip(state: .drop), rest]),
            ("yawn", [Clip(state: .yawn), rest]),
            ("tumble", [Clip(state: .tumble), rest]),
            ("shy", [Clip(state: .shy), rest]),
            ("angry", [Clip(state: .angry), rest]),
            ("talk", [Clip(state: .talk, seconds: 1.6)]),
            ("home", [Clip(state: .burrowed, seconds: 2, menuBar: true), Clip(state: .peekHold, seconds: 2.5, menuBar: true)]),
        ]
        for (name, list) in clips {
            write(render(list, scale: 4), to: directory.appendingPathComponent("\(name).png"))
        }
        // Showreel for the top of the README: a working day in ten seconds.
        let reel: [Clip] = [
            Clip(state: .idle, seconds: 1.6), Clip(state: .hop),
            Clip(state: .working, seconds: 2.4, cubes: work),
            Clip(state: .alert, seconds: 1.8, cubes: [.init(status: .waiting, subagents: 0)] + work.prefix(2)),
            Clip(state: .working, seconds: 1.2, cubes: work),
            Clip(state: .flip, cubes: [.init(status: .done, subagents: 0)]),
            Clip(state: .idle, seconds: 1.2),
        ]
        write(render(reel, scale: 6), to: directory.appendingPathComponent("showreel.png"))
        // Every look, idling side by side.
        let looks = [Skin.lavender, .mint, .peach, .mono].map { Look(skin: $0) }
            + [Accessory.glasses, .headphones, .cap].map { Look(skin: .lavender, accessory: $0) }
        write(lineup(looks, scale: 3), to: directory.appendingPathComponent("looks.png"))
    }

    /// Frames with their delays. Boundaries are the state's own frame ends, plus the agent stack's 10 Hz beat
    /// when blocks are shown.
    static func timeline(_ clip: Clip) -> [(index: Int, tick: Int, delay: Double)] {
        let durations = clip.state.durations
        let length = clip.seconds ?? clip.state.totalDuration
        var cuts: Set<Double> = [length]
        var t = 0.0, i = 0
        while t < length {
            t += durations[i % durations.count]
            i += 1
            if t < length { cuts.insert((t * 1000).rounded() / 1000) }
        }
        if !clip.cubes.isEmpty || !clip.codex.isEmpty {
            var b = stackBeat
            while b < length { cuts.insert((b * 1000).rounded() / 1000); b += stackBeat }
        }
        var out: [(Int, Int, Double)] = []
        var start = 0.0
        for end in cuts.sorted() {
            // Browsers stretch delays of 10 ms or less to 100 ms, so a sliver where a frame end and a beat
            // nearly meet stays with the previous frame instead.
            if end - start < minDelay, let last = out.popLast() {
                out.append((last.0, last.1, last.2 + end - start))
            } else {
                out.append((frameIndex(at: start, durations), Int(start / stackBeat + 0.001), end - start))
            }
            start = end
        }
        return out
    }

    private static func frameIndex(at time: Double, _ durations: [Double]) -> Int {
        var t = time.truncatingRemainder(dividingBy: durations.reduce(0, +)) + 0.0001
        for (i, d) in durations.enumerated() {
            if t < d { return i }
            t -= d
        }
        return durations.count - 1
    }

    private static func render(_ clips: [Clip], scale: Int) -> [(CGImage, Double)] {
        clips.flatMap { clip in
            timeline(clip).compactMap { step -> (CGImage, Double)? in
                var body = SpriteFactory.frame(for: clip.state, index: step.index, agentCubes: false, look: clip.look)
                if clip.drain > 0 { body = body.drained(rows: clip.drain, skin: clip.look.skin) }
                let stack = clip.cubes.isEmpty && clip.codex.isEmpty
                    ? nil : AgentStack.canvas(for: clip.cubes, left: clip.codex, tick: step.tick)
                guard let image = tile([(body, stack)], scale: scale, menuBar: clip.menuBar) else { return nil }
                return (image, step.delay)
            }
        }
    }

    private static func lineup(_ looks: [Look], scale: Int) -> [(CGImage, Double)] {
        let frames = looks.map { SpriteFactory.frames(for: .idle, agentCubes: false, look: $0) }
        return PetState.idle.durations.enumerated().compactMap { i, delay in
            tile(frames.map { ($0[i], nil) }, scale: scale).map { ($0, delay) }
        }
    }

    /// Sprites side by side on one rounded tile.
    private static func tile(_ sprites: [(PixelCanvas, PixelCanvas?)], scale: Int, menuBar: Bool = false) -> CGImage? {
        let pad = 4 * scale, cell = 32 * scale
        let width = sprites.count * cell + 2 * pad, height = cell + 2 * pad
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        let radius = CGFloat(6 * scale)
        let shape = CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                           cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(shape)
        ctx.setFillColor(background)
        ctx.fillPath()
        if menuBar {
            // CoreGraphics' origin is bottom-left: the band is the top `pad` rows, clipped to the tile.
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            let bar = Palette.menuBar
            ctx.setFillColor(CGColor(red: CGFloat(bar.r) / 255, green: CGFloat(bar.g) / 255, blue: CGFloat(bar.b) / 255, alpha: 1))
            ctx.fill(CGRect(x: 0, y: height - pad, width: width, height: pad))
            ctx.restoreGState()
        }
        for (k, (body, stack)) in sprites.enumerated() {
            let rect = CGRect(x: pad + k * cell, y: pad, width: cell, height: cell)
            for layer in [body, stack].compactMap({ $0 }) {
                if let image = layer.makeImage() { ctx.draw(image, in: rect) }
            }
        }
        return ctx.makeImage()
    }

    private static func write(_ frames: [(CGImage, Double)], to url: URL) {
        guard let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, frames.count, nil)
        else { return }
        let loop = [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]] as CFDictionary
        CGImageDestinationSetProperties(out, loop)
        for (image, delay) in frames {
            let props = [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: delay]] as CFDictionary
            CGImageDestinationAddImage(out, image, props)
        }
        if !CGImageDestinationFinalize(out) { NSLog("PixelPet: failed to write \(url.path)") }
    }
}

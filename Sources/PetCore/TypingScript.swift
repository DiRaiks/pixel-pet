/// The typing loop at the keyboard, written out beat by beat. Bursts of different lengths, an uneven pace,
/// now and then a key held a little longer mid-burst, and different pauses between bursts (a look up at the
/// screen, with or without a blink, or a short stop). It's generated from a fixed seed: about 12 s long, so the repeat goes
/// unnoticed, yet every frame stays deterministic. `PetState.working` takes its durations from here and
/// `SpriteFactory` its poses.
public enum TypingScript {
    public enum Beat: Equatable, Sendable {
        /// A key goes down; `key` is one of `keyCount` columns on the keyboard.
        case down(key: Int)
        /// Fingers up, eyes still on the keys.
        case up
        /// Looking up at the screen.
        case read
        case blink
        /// A short stop with eyes on the keys.
        case hitch
    }

    public static let keyCount = 7
    public static let bursts = [6, 11, 4, 9, 13, 7]

    public static let beats: [(beat: Beat, ms: Double)] = {
        var seed: UInt32 = 0x2545_F491
        func next(_ n: Int) -> Int {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Int(seed >> 16) % n
        }
        let pauses: [[(Beat, Double)]] = [
            [(.read, 450), (.blink, 110), (.read, 300)],
            [(.hitch, 260)],
            [(.read, 650)],
            [(.hitch, 180), (.read, 380), (.blink, 110), (.read, 200)],
            [(.hitch, 320)],
            [(.read, 520), (.blink, 110), (.read, 160)],
        ]
        var out: [(beat: Beat, ms: Double)] = []
        for (n, taps) in bursts.enumerated() {
            for _ in 0..<taps {
                out.append((.down(key: next(keyCount)), Double(60 + next(50))))
                // One key up in six lingers: a tiny hesitation inside the burst.
                out.append((.up, next(6) == 0 ? 170 : Double(50 + next(40))))
            }
            out += pauses[n % pauses.count].map { (beat: $0.0, ms: $0.1) }
        }
        return out
    }()

    /// When each beat starts, in ms from the start of the loop.
    public static let starts: [Double] = beats.indices.map { i in beats[..<i].reduce(0) { $0 + $1.ms } }
}

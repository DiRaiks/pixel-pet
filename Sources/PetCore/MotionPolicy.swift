/// System Settings → Accessibility → Display → Reduce motion: no jumps, shakes or swings. The pet still
/// shows what's going on through its face and colors (spec §3.2).
public enum MotionPolicy {
    /// States whose animation is mostly movement hold one telling frame instead.
    public static func stillFrame(for state: PetState) -> Int? {
        switch state {
        case .alert: 0        // wide eyes and the "!"
        case .error: 6        // dizzy: spiral eyes, stars
        case .dragged: 0      // hanging under the cursor, no swing
        case .lowLimit: 8     // drained, worried, sweat drop, no shiver
        default: nil
        }
    }

    /// One-shots that are pure movement are skipped altogether.
    public static func allowsOneShot(_ state: PetState) -> Bool {
        switch state {
        case .hop, .celebrate, .drop, .dive, .peek, .flip, .tumble, .yawn, .shy, .angry: false
        default: true
        }
    }

    /// A held frame shown for a moment instead of a skipped one-shot, so the event still registers.
    public struct Cue: Equatable, Sendable {
        public let state: PetState
        public let frame: Int
    }

    public static func cue(for oneShot: PetState) -> Cue? {
        switch oneShot {
        case .celebrate, .flip: Cue(state: .celebrate, frame: 12)   // happy face, feet on the ground
        case .peek: Cue(state: .peekHold, frame: 0)          // out of the hole, looking
        case .shy: Cue(state: .shy, frame: 6)                // blushing, eyes away
        case .angry: Cue(state: .angry, frame: 8)            // puffed up, frowning
        default: nil
        }
    }
}


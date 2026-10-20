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
        case .touchKey, .touchKeyHome: 0     // holding the key up, pad lit
        case .question: 0     // "?" over a tilted head
        case .exhausted: 0    // lying spent, clock above
        case .meetingNow: 0   // headset on, the alarm ringing
        case .music: 0        // eyes shut, notes on both sides, no bob
        case .onAir: 0        // the mic bubble with its red dot
        case .overheated: 2   // thermometer high, flushed, sweating
        case .lowPower: 0     // sleepy beside the yellow battery
        case .offline: 0      // the struck-through Wi-Fi bubble
        case .newspaper: 0    // reading, eyes over the paper
        case .breakHint: 0    // the mug in its bubble
        case .catchOpen: 0    // mouth open, looking up
        default: nil
        }
    }

    /// One-shots that are pure movement are skipped altogether.
    public static func allowsOneShot(_ state: PetState) -> Bool {
        switch state {
        case .hop, .celebrate, .drop, .dive, .peek, .flip, .tumble, .drip, .melt, .yawn, .shy, .angry,
             .wave, .launch, .purr, .sneeze, .headphonesOn, .headphonesOff, .batteryFull, .screenshot,
             .darkMode, .lightMode,
             .workSip, .workStretch, .workThink, .workRush, .glanceLeft, .glanceRight, .touchDone,
             .refill, .spawn, .recall, .compact, .plugIn, .thrown, .dizzy, .splatLeft, .splatRight, .hookah, .hookahCloud: false
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
        case .touchDone: Cue(state: .touchDone, frame: 6)    // happy, check mark
        case .refill: Cue(state: .refill, frame: 10)         // full again, stretching
        case .plugIn: Cue(state: .plugIn, frame: 5)          // lightning bolt, happy
        case .dizzy: Cue(state: .dizzy, frame: 8)            // spiral eyes, stars
        default: nil
        }
    }
}


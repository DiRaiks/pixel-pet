/// Frame clock for the pet: a looping base state plus an optional one-shot played on top of it.
public struct PetPlayer: Sendable {
    public private(set) var base: PetState
    public private(set) var oneShot: PetState?
    public private(set) var frame = 0
    private var accumulator = 0.0

    /// Caps catch-up after the app was suspended so we don't spin through thousands of frames.
    private static let maxCatchUp = 10.0

    public var state: PetState { oneShot ?? base }

    public init(base: PetState) {
        self.base = base
    }

    public mutating func setBase(_ state: PetState) {
        guard state != base else { return }
        base = state
        if oneShot == nil { restart() }
    }

    public mutating func play(_ state: PetState) {
        if state.loops {
            oneShot = nil
            base = state
        } else {
            oneShot = state
        }
        restart()
    }

    /// Returns true when the visible frame changed.
    @discardableResult
    public mutating func advance(by seconds: Double) -> Bool {
        accumulator = min(accumulator + seconds, Self.maxCatchUp)
        var changed = false
        while accumulator >= 1 / state.fps - 1e-9 {
            accumulator -= 1 / state.fps
            changed = true
            if frame + 1 < state.frameCount {
                frame += 1
            } else if oneShot != nil {
                // Hand back to the base on its first frame; leftover one-shot time must not skip it.
                oneShot = nil
                restart()
                break
            } else {
                frame = 0
            }
        }
        return changed
    }

    private mutating func restart() {
        frame = 0
        accumulator = 0
    }
}

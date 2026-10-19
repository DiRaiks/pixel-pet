import CoreGraphics
import PetCore
import PetSprites

/// Renders every state's frames once at launch; frames are tiny (32x32), so all of them fit in a few hundred KB.
@MainActor
final class SpriteLibrary {
    struct Frame {
        let image: CGImage
        let canvas: PixelCanvas
    }

    private let frames: [PetState: [Frame]]

    init() {
        var all: [PetState: [Frame]] = [:]
        for state in PetState.allCases {
            all[state] = SpriteFactory.frames(for: state, agentCubes: false).enumerated().map { index, canvas in
                // A missing frame would shift every later index; failing loudly at launch is better.
                guard let image = canvas.makeImage() else { fatalError("PixelPet: cannot render \(state) frame \(index)") }
                return Frame(image: image, canvas: canvas)
            }
        }
        frames = all
    }

    private struct DrainKey: Hashable {
        let state: PetState
        let index: Int
        let rows: Int
    }

    private var drainedFrames: [DrainKey: Frame] = [:]

    /// `drain` empties the top body rows (used 5-hour limit). Drained variants are made on demand and cached;
    /// the drain level changes rarely, so the cache stays small.
    func frame(_ state: PetState, _ index: Int, drain: Int = 0) -> Frame {
        let list = frames[state]!
        let base = list[min(index, list.count - 1)]
        guard drain > 0 else { return base }
        let key = DrainKey(state: state, index: index, rows: drain)
        if let cached = drainedFrames[key] { return cached }
        let canvas = base.canvas.drained(rows: drain)
        guard let image = canvas.makeImage() else { return base }
        if drainedFrames.count > 2_000 { drainedFrames.removeAll() }
        let frame = Frame(image: image, canvas: canvas)
        drainedFrames[key] = frame
        return frame
    }
}

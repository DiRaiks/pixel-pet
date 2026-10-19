import CoreGraphics
import PetCore
import PetSprites

/// Renders frames in the current look and keeps them: base frames for every state at once (a few
/// hundred KB), variants (drain, gaze) on demand with a bounded cache.
@MainActor
final class SpriteLibrary {
    struct Frame {
        let image: CGImage
        let canvas: PixelCanvas
    }

    private(set) var look = Look.standard
    private var frames: [PetState: [Frame]] = [:]

    init(look: Look = .standard) {
        self.look = look
        rebuild()
    }

    func setLook(_ look: Look) {
        guard look != self.look else { return }
        self.look = look
        rebuild()
    }

    private func rebuild() {
        var all: [PetState: [Frame]] = [:]
        for state in PetState.allCases {
            all[state] = SpriteFactory.frames(for: state, agentCubes: false, look: look).enumerated().map { index, canvas in
                // A missing frame would shift every later index; failing loudly at launch is better.
                guard let image = canvas.makeImage() else { fatalError("PixelPet: cannot render \(state) frame \(index)") }
                return Frame(image: image, canvas: canvas)
            }
        }
        frames = all
        variants.removeAll()
    }

    private struct VariantKey: Hashable {
        let state: PetState
        let index: Int
        let rows: Int
        let gaze: Gaze?
    }

    private var variants: [VariantKey: Frame] = [:]

    /// `drain` empties the top body rows (used 5-hour limit); `gaze` points the idle face.
    func frame(_ state: PetState, _ index: Int, drain: Int = 0, gaze: Gaze? = nil) -> Frame {
        let list = frames[state]!
        let i = min(index, list.count - 1)
        let base = list[i]
        let gaze = state == .idle ? gaze : nil
        guard drain > 0 || gaze != nil else { return base }
        let key = VariantKey(state: state, index: i, rows: drain, gaze: gaze)
        if let cached = variants[key] { return cached }
        let looking = gaze.map { SpriteFactory.frame(for: .idle, index: i, agentCubes: false, gaze: $0, look: look) }
        let canvas = (looking ?? base.canvas).drained(rows: drain, skin: look.skin)
        guard let image = canvas.makeImage() else { return base }
        if variants.count > 2_000 { variants.removeAll() }
        let frame = Frame(image: image, canvas: canvas)
        variants[key] = frame
        return frame
    }
}

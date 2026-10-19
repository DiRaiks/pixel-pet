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

    func frame(_ state: PetState, _ index: Int) -> Frame {
        let list = frames[state]!
        return list[min(index, list.count - 1)]
    }
}

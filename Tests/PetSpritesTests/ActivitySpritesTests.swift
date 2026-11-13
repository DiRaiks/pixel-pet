import Testing
import PetCore
@testable import PetSprites

/// What the user does on the Mac: Spaces, typing, the app in front, apps opening and quitting, a USB stick, a
/// display, the keyboard layout.
@Suite struct ActivitySpritesTests {
    let looks = [Look.standard, Look(figure: .lidman), Look(figure: .clip)]
    let states: [PetState] = [.typingAlong, .gamepad, .popcorn, .coding, .appLaunched, .appQuit,
                              .usbIn, .usbOut, .newDisplay, .layoutSwitch]

    func has(_ f: PixelCanvas, _ color: RGBA) -> Bool { f.pixels.contains(color) }

    /// Columns 0-4 and 27-31 belong to the agent blocks below row 8; above it the bubble, icon and badge may
    /// reach the edge. The tool bubble's bottom edge sits on row 8 on the left, as at the keyboard: only the
    /// Codex stack's overflow mark reaches it.
    @Test func keepsClearOfTheAgentColumns() {
        for look in looks {
            for state in states {
                for (i, f) in SpriteFactory.frames(for: state, agentCubes: false, look: look).enumerated() {
                    for y in 8..<32 {
                        let columns = y == 8 ? [27, 28, 29, 30, 31] : [0, 1, 2, 3, 4, 27, 28, 29, 30, 31]
                        for x in columns where f.pixel(x, y) != nil {
                            Issue.record("\(state) frame \(i) (\(look.figure)) draws at \(x),\(y)")
                        }
                    }
                }
            }
        }
    }

    /// Every frame draws the pet; none is left empty.
    @Test func everyFrameDrawsThePet() {
        for look in looks {
            for state in states {
                for (i, f) in SpriteFactory.frames(for: state, agentCubes: false, look: look).enumerated() {
                    #expect(has(f, look.skin.outline), "\(state) frame \(i) (\(look.figure))")
                }
            }
        }
    }

    /// The props carry the layout codes both ways; anything but two letters A–Z carries nothing.
    @Test func layoutCodesRoundTrip() {
        let props = WorkProps.layout(from: "EN", to: "RU")
        #expect(props.layoutCodes?.from == "EN" && props.layoutCodes?.to == "RU")
        #expect(WorkProps.layoutBits.contains(props))
        #expect(WorkProps.layout(from: "ENG", to: "RU").isEmpty)
        #expect(WorkProps.layout(from: "en", to: "RU").isEmpty)
        #expect(WorkProps([.mug, .candle]).layoutCodes == nil)
        // It stays clear of the other props' bits.
        #expect(WorkProps.layoutBits.isDisjoint(with: [.mug, .headband, .lamp, .tea, .toolRun, .toolEdit, .pumpkin, .fir,
                                                       .candle(melted: 3), .strain(3)]))
    }

    /// The badge shows the old layout's color before the flip and the new one's after.
    @Test func badgeFlipsToTheNewLayout() {
        let props = WorkProps.layout(from: "EN", to: "DE")
        let before = SpriteFactory.frame(for: .layoutSwitch, index: 0, agentCubes: false, props: props)
        let after = SpriteFactory.frame(for: .layoutSwitch, index: 7, agentCubes: false, props: props)
        let (en, _) = SpriteFactory.badgeColors("EN"), (de, _) = SpriteFactory.badgeColors("DE")
        #expect(before.pixel(5, 1) == en)
        #expect(after.pixel(5, 1) == de)
        #expect(SpriteFactory.letterGlyphs.count == 26)
    }

    /// A game, a video and code each bring their prop: the gamepad, the bucket, the terminal bubble.
    @Test func appPropsShow() {
        #expect(has(SpriteFactory.frame(for: .gamepad, index: 0, agentCubes: false), Palette.accessoryDark))
        #expect(has(SpriteFactory.frame(for: .popcorn, index: 0, agentCubes: false), Palette.capRed))
        #expect(has(SpriteFactory.frame(for: .coding, index: 0, agentCubes: false), Palette.terminal))
    }
}

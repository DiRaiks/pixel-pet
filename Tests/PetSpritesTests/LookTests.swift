import Testing
import PetCore
@testable import PetSprites

@Suite struct SkinTests {
    @Test func skinsChangeTheBodyColors() {
        for skin in Skin.all {
            let frame = SpriteFactory.frame(for: .idle, index: 0, agentCubes: false, look: Look(skin: skin, accessory: .none))
            #expect(frame.pixels.contains(skin.fill), "\(skin.name)")
            #expect(frame.pixel(9, 12) == skin.outline, "\(skin.name)")
        }
        #expect(Skin.named("peach") == .peach)
        #expect(Skin.named("nonsense") == .lavender)
    }

    @Test func newStyleHasTwoShadesRimAndBlush() {
        let s = Skin.lavender
        let idle = SpriteFactory.frame(for: .idle, index: 0, agentCubes: false)
        // Body 16x14 at x0=8, y0=12: rows y0+h-3 / y0+h-2 are the two shades, column x0+w-2 the rim.
        #expect(idle.pixel(12, 23) == s.shade)
        #expect(idle.pixel(12, 24) == s.shade2)
        #expect(idle.pixel(22, 18) == s.rim)
        #expect(idle.pixels.contains(s.blush))
    }

    @Test func accessoriesAddPixelsAndFollowTheBody() {
        let plain = SpriteFactory.frame(for: .idle, index: 0, agentCubes: false)
        for accessory in Accessory.allCases where accessory != .none {
            let worn = SpriteFactory.frame(for: .idle, index: 0, agentCubes: false, look: Look(skin: .lavender, accessory: accessory))
            #expect(worn != plain, "\(accessory)")
        }
        #expect(Accessory(rawValue: "glasses") == .glasses)
    }
}

@Suite struct RotationTests {
    @Test func rotatingAQuarterTurnMovesACornerMarker() {
        var sprite = PixelCanvas(width: 8, height: 8)
        sprite.fill(0, 0, 8, 8, Palette.fill)
        sprite.set(1, 1, Palette.eye)
        var upright = PixelCanvas()
        upright.blitRotated(sprite, centerX: 16, centerY: 16, degrees: 0)
        var turned = PixelCanvas()
        turned.blitRotated(sprite, centerX: 16, centerY: 16, degrees: 90)
        #expect(upright.pixel(13, 13) == Palette.eye)
        // A quarter turn clockwise carries the top-left marker to the top-right.
        #expect(turned.pixel(18, 13) == Palette.eye)
        #expect(turned.opaquePixelCount == 64)
    }
}

@Suite struct NewAnimationTests {
    @Test func flipTurnsInTheAirAndThrowsConfetti() {
        let frames = SpriteFactory.frames(for: .flip, agentCubes: false)
        let colors = Set(frames[9].pixels.compactMap { $0 })
        #expect(colors.contains(Palette.amber) || colors.contains(Palette.teal))
    }

    @Test func tumbleRollsAwayAndBack() {
        let frames = SpriteFactory.frames(for: .tumble, agentCubes: false)
        func leftmost(_ c: PixelCanvas) -> Int { (0..<32).first { x in (0..<27).contains { c.pixel(x, $0) == Palette.outline } } ?? -1 }
        #expect(leftmost(frames[6]) > leftmost(frames[0]))
        #expect(leftmost(frames[13]) == leftmost(frames[0]))
    }

    @Test func sleepWearsANightcap() {
        #expect(SpriteFactory.frame(for: .sleep, index: 0, agentCubes: false).pixels.contains(Palette.capRed))
    }

    @Test func errorTurnsDizzyAfterTheShake() {
        let dizzy = SpriteFactory.frame(for: .error, index: 8, agentCubes: false)
        #expect(dizzy.pixels.contains(Palette.amber))
        #expect(!dizzy.pixels.contains(Palette.errorFill))
    }

    @Test func workingTypesOnAKeyboard() {
        #expect(SpriteFactory.frame(for: .working, index: 0, agentCubes: false).pixels.contains(Palette.keyboard))
    }

    @Test func shyBlushesMoreAndAngryFrowns() {
        let shy = SpriteFactory.frame(for: .shy, index: 6, agentCubes: false).pixels.filter { $0 == Skin.lavender.blush }.count
        let calm = SpriteFactory.frame(for: .idle, index: 0, agentCubes: false).pixels.filter { $0 == Skin.lavender.blush }.count
        #expect(shy > calm)
        #expect(SpriteFactory.frame(for: .angry, index: 8, agentCubes: false).pixels.contains(Palette.errorFill))
    }
}

@Suite struct RotationReviewTests {
    @Test func spinsStayInsideTheCanvas() {
        let skin = Skin.lavender
        let body: Set<RGBA> = [skin.outline, skin.fill, skin.highlight, skin.rim, skin.shade, skin.shade2]
        for state in [PetState.flip, .tumble] {
            for (i, frame) in SpriteFactory.frames(for: state, agentCubes: false).enumerated() {
                let topRow = (0..<32).contains { frame.pixel($0, 0).map(body.contains) == true }
                #expect(!topRow, "\(state) frame \(i) is clipped at the top")
            }
        }
    }

    @Test func accessoriesStayOnDuringSpins() {
        let look = Look(skin: .lavender, accessory: .cap)
        for i in 4...7 {
            #expect(SpriteFactory.frame(for: .flip, index: i, agentCubes: false, look: look).pixels.contains(Palette.capRed), "flip \(i)")
        }
    }

    @Test func faceStaysOnTheSameRowWhenTheBodyTurns() {
        func eyeRow(_ c: PixelCanvas) -> Int? {
            (0..<32).first { y in (0..<32).contains { c.pixel($0, y) == Skin.lavender.eye } }
        }
        var style = BodyStyle(look: .standard)
        style.eyes = .squeeze
        var upright = PixelCanvas()
        upright.body(style)
        style.rotation = 30
        var turned = PixelCanvas()
        turned.body(style)
        #expect(eyeRow(upright) != nil)
        #expect(eyeRow(turned) == eyeRow(upright))
    }

    @Test func rotationIsDeterministic() {
        #expect(SpriteFactory.frames(for: .flip, agentCubes: false) == SpriteFactory.frames(for: .flip, agentCubes: false))
    }

    @Test func drainWorksForMonoWithHeadphones() {
        let look = Look(skin: .mono, accessory: .headphones)
        let frame = SpriteFactory.frame(for: .idle, index: 0, agentCubes: false, look: look)
        let drained = frame.drained(rows: 3, skin: .mono)
        // Body top outline is row 12; rows 13-15 are drained.
        #expect(drained.pixel(12, 14) == Skin.mono.empty)
        #expect(drained.pixel(12, 13) == Skin.mono.empty)
    }
}

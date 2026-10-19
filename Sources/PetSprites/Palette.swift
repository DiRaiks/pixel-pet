/// Body colors of one look. Shadows lean cool and saturated, highlights warm and pale (hue shifting),
/// the outline is a deep tint of the body rather than near-black.
public struct Skin: Equatable, Hashable, Sendable {
    public let name: String
    public let outline, fill, highlight, rim, shade, shade2, empty, eye, eyeShine, eyeShine2, blush: RGBA

    public static let lavender = Skin(
        name: "lavender", outline: RGBA(0x2E2470), fill: RGBA(0x8A80E6), highlight: RGBA(0xC9C1FA), rim: RGBA(0xA9A0F2),
        shade: RGBA(0x5A55C4), shade2: RGBA(0x3F3FA0), empty: RGBA(0xEEEDFE), eye: RGBA(0x1B1442),
        eyeShine: RGBA(0xFFFFFF), eyeShine2: RGBA(0x5A4FB0), blush: RGBA(0xF5A3C7))
    public static let mint = Skin(
        name: "mint", outline: RGBA(0x0F4E3E), fill: RGBA(0x5DCAA5), highlight: RGBA(0xB8EEDB), rim: RGBA(0x8FDEC3),
        shade: RGBA(0x2E9C80), shade2: RGBA(0x1D7A66), empty: RGBA(0xE1F5EE), eye: RGBA(0x08332A),
        eyeShine: RGBA(0xFFFFFF), eyeShine2: RGBA(0x2E7A66), blush: RGBA(0xF5A3C7))
    public static let peach = Skin(
        name: "peach", outline: RGBA(0x6A2A14), fill: RGBA(0xF0997B), highlight: RGBA(0xFBD3C2), rim: RGBA(0xF7B9A2),
        shade: RGBA(0xD2694A), shade2: RGBA(0xB04E35), empty: RGBA(0xFAECE7), eye: RGBA(0x4A1B0C),
        eyeShine: RGBA(0xFFFFFF), eyeShine2: RGBA(0x8A3A22), blush: RGBA(0xE2557E))
    public static let mono = Skin(
        name: "mono", outline: RGBA(0x2C2C2A), fill: RGBA(0xB4B2A9), highlight: RGBA(0xE4E2DA), rim: RGBA(0xCFCDC5),
        shade: RGBA(0x888780), shade2: RGBA(0x6A6964), empty: RGBA(0xF1EFE8), eye: RGBA(0x2C2C2A),
        eyeShine: RGBA(0xFFFFFF), eyeShine2: RGBA(0x5F5E5A), blush: RGBA(0xED93B1))
    /// The pet turning red while something fails.
    static let error = Skin(
        name: "error", outline: RGBA(0x501313), fill: RGBA(0xE24B4A), highlight: RGBA(0xF09595), rim: RGBA(0xF09595),
        shade: RGBA(0xA32D2D), shade2: RGBA(0x791F1F), empty: RGBA(0xFCEBEB), eye: RGBA(0x501313),
        eyeShine: RGBA(0xFFFFFF), eyeShine2: RGBA(0x791F1F), blush: RGBA(0xF09595))

    public static let all: [Skin] = [.lavender, .mint, .peach, .mono]

    public static func named(_ name: String) -> Skin { all.first { $0.name == name } ?? .lavender }
}

public enum Accessory: String, CaseIterable, Sendable {
    case none, glasses, headphones, cap
}

/// Everything about how the pet looks, besides the animation itself.
public struct Look: Equatable, Hashable, Sendable {
    public var skin: Skin
    public var accessory: Accessory
    public init(skin: Skin = .lavender, accessory: Accessory = .none) {
        self.skin = skin
        self.accessory = accessory
    }
    public static let standard = Look()
}

/// Colors outside the body. The body constants mirror the default skin for older call sites.
public enum Palette {
    public static let outline = Skin.lavender.outline
    public static let fill = Skin.lavender.fill
    public static let highlight = Skin.lavender.highlight
    public static let shade = Skin.lavender.shade
    public static let empty = Skin.lavender.empty
    public static let eye = Skin.lavender.eye
    public static let glint = Skin.lavender.eyeShine
    public static let glow = RGBA(0xEEEDFE)
    public static let shadow = RGBA(0x000000, alpha: 46)
    public static let notch = RGBA(0x000000)
    public static let menuBar = RGBA(0xD3D1C7)

    public static let amber = RGBA(0xEF9F27)
    public static let amberLight = RGBA(0xFAC775)
    public static let amberDark = RGBA(0x412402)
    public static let teal = RGBA(0x1D9E75)
    public static let tealLight = RGBA(0x9FE1CB)
    public static let pink = RGBA(0xD4537E)
    public static let blue = RGBA(0x378ADD)
    public static let green = RGBA(0x97C459)
    public static let sweat = RGBA(0x85B7EB)
    public static let sweatDark = RGBA(0x378ADD)
    public static let bubble = RGBA(0xB5D4F4)
    public static let errorFill = RGBA(0xE24B4A)
    public static let errorHighlight = RGBA(0xF09595)
    public static let errorShade = RGBA(0xA32D2D)
    public static let errorDark = RGBA(0x501313)
    public static let white = RGBA(0xFFFFFF)
    public static let steam = RGBA(0xB4B2A9)
    public static let keyboard = RGBA(0x5F5E5A)
    public static let keyboardTop = RGBA(0x888780)
    public static let capRed = RGBA(0xE24B4A)
    /// The coffee mug on the desk during long work (its steam reuses `steam`).
    public static let mug = RGBA(0xF1EFE8)
    public static let mugShade = RGBA(0xB4B2A9)
    public static let coffee = RGBA(0x6B4A2E)
    /// The little YubiKey: black body, gold touch pad (lit while it waits), silver USB plug.
    public static let keyBody = RGBA(0x2C2C2A)
    public static let keyGold = RGBA(0xC9962B)
    public static let keyGoldLit = RGBA(0xFAD978)
    public static let keyPlug = RGBA(0xC9C7C0)
    /// Frames of glasses and headphones; deliberately not any skin's outline color.
    public static let accessoryDark = RGBA(0x34302E)
    public static let gear = RGBA(0x2C2C2A)
    public static let gearLight = RGBA(0x888780)
    public static let agentIdle = RGBA(0xB4B2A9)
    public static let agentDone = RGBA(0x639922)
    /// Menu-bar icons are templates: only alpha matters, macOS tints them for light and dark bars.
    public static let template = RGBA(0x000000)
}

/// Props that pile up on the desk while agents keep working: a mug after a while, a headband after long.
public struct WorkProps: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let mug = WorkProps(rawValue: 1)
    public static let headband = WorkProps(rawValue: 2)
}

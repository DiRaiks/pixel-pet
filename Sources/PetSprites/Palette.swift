import Foundation

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
    public static let sky = Skin(
        name: "sky", outline: RGBA(0x123A63), fill: RGBA(0x6FB3EA), highlight: RGBA(0xC4E4FB), rim: RGBA(0x98CCF3),
        shade: RGBA(0x3E86C9), shade2: RGBA(0x2A66A6), empty: RGBA(0xE6F2FC), eye: RGBA(0x0B2440),
        eyeShine: RGBA(0xFFFFFF), eyeShine2: RGBA(0x2E6FA8), blush: RGBA(0xF5A3C7))
    public static let sakura = Skin(
        name: "sakura", outline: RGBA(0x6B1E45), fill: RGBA(0xF2A6C6), highlight: RGBA(0xFCD9E8), rim: RGBA(0xF7C1D8),
        shade: RGBA(0xD9739F), shade2: RGBA(0xB8557F), empty: RGBA(0xFDEEF4), eye: RGBA(0x4A1230),
        eyeShine: RGBA(0xFFFFFF), eyeShine2: RGBA(0x9E3D68), blush: RGBA(0xE2557E))
    public static let vanilla = Skin(
        name: "vanilla", outline: RGBA(0x5C4320), fill: RGBA(0xF1DFB4), highlight: RGBA(0xFBF3DD), rim: RGBA(0xF6E9C9),
        shade: RGBA(0xD6BC82), shade2: RGBA(0xB89A5E), empty: RGBA(0xFBF7EC), eye: RGBA(0x3D2C12),
        eyeShine: RGBA(0xFFFFFF), eyeShine2: RGBA(0x8A6A35), blush: RGBA(0xF0A08A))
    /// Dark body for dark wallpapers: the outline and the face are light instead.
    public static let night = Skin(
        name: "night", outline: RGBA(0xB9C3FF), fill: RGBA(0x2B3263), highlight: RGBA(0x4F5A9E), rim: RGBA(0x3A437E),
        shade: RGBA(0x1E2450), shade2: RGBA(0x161A3D), empty: RGBA(0x6A72A8), eye: RGBA(0xE8ECFF),
        eyeShine: RGBA(0x9BA6F0), eyeShine2: RGBA(0xB9C3FF), blush: RGBA(0xC77DB5))
    /// LM's own aqua; with that figure the color setting doesn't apply.
    public static let lidman = Skin(
        name: "lidman", outline: RGBA(0x1C5F6B), fill: RGBA(0xA8ECEA), highlight: RGBA(0xE2FBFA), rim: RGBA(0xC6F4F2),
        shade: RGBA(0x74D3D3), shade2: RGBA(0x4FB8BE), empty: RGBA(0xEAFBFA), eye: RGBA(0x163A40),
        eyeShine: RGBA(0xFFFFFF), eyeShine2: RGBA(0x2E6F78), blush: RGBA(0xF5A3C7))
    /// The pet turning red while something fails.
    static let error = Skin(
        name: "error", outline: RGBA(0x501313), fill: RGBA(0xE24B4A), highlight: RGBA(0xF09595), rim: RGBA(0xF09595),
        shade: RGBA(0xA32D2D), shade2: RGBA(0x791F1F), empty: RGBA(0xFCEBEB), eye: RGBA(0x501313),
        eyeShine: RGBA(0xFFFFFF), eyeShine2: RGBA(0x791F1F), blush: RGBA(0xF09595))

    public static let all: [Skin] = [.lavender, .mint, .peach, .mono, .sky, .sakura, .vanilla, .night]

    public static func named(_ name: String) -> Skin { all.first { $0.name == name } ?? .lavender }
}

public enum Accessory: String, CaseIterable, Sendable {
    case none, glasses, headphones, cap
    case beanie, crown, bow, flower, propeller, sunglasses, scarf, mustache

    /// Worn on the head: the work headband stays off so the two don't pile up.
    public var isOnHead: Bool {
        switch self {
        case .headphones, .cap, .beanie, .crown, .bow, .flower, .propeller: true
        case .none, .glasses, .sunglasses, .scarf, .mustache: false
        }
    }
}

/// The character itself: the cube, or LM.
public enum Figure: String, CaseIterable, Sendable {
    case cube, lidman
}

/// Everything about how the pet looks, besides the animation itself.
public struct Look: Equatable, Hashable, Sendable {
    public var skin: Skin
    public var accessory: Accessory
    public var figure: Figure
    /// LM always wears his own colors and none of the accessories (his diamond takes the top).
    public init(skin: Skin = .lavender, accessory: Accessory = .none, figure: Figure = .cube) {
        self.figure = figure
        self.skin = figure == .lidman ? .lidman : skin
        self.accessory = figure == .lidman ? .none : accessory
    }
    public static let standard = Look()

    /// The setting value meaning "a different one every day".
    public static let daily = "daily"

    /// Marks drawn over the middle of the head ("!", the spent clock) step aside for LM's diamond.
    var headMarkShift: Int { figure == .lidman ? 7 : 0 }

    /// The look for the saved settings on a given day: fixed names as they are, `daily` picked from the
    /// date alone (the same all day, also after a restart; never the same as the day before; never bare).
    public static func resolve(skin: String, accessory: String, figure: String = Figure.cube.rawValue, on date: Date,
                               calendar: Calendar = .autoupdatingCurrent) -> Look {
        let day = dayNumber(date, calendar)
        let skins = Skin.all, wearable = Accessory.allCases.filter { $0 != .none }
        // Stepping by a number coprime to the count walks through all of them, never repeating back to back.
        let pickedSkin = skin == daily ? skins[(day * 3) % skins.count] : Skin.named(skin)
        let pickedAccessory = accessory == daily ? wearable[(day * 5 + 2) % wearable.count] : Accessory(rawValue: accessory) ?? .none
        return Look(skin: pickedSkin, accessory: pickedAccessory, figure: Figure(rawValue: figure) ?? .cube)
    }

    private static func dayNumber(_ date: Date, _ calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let midnight = utc.date(from: DateComponents(year: c.year, month: c.month, day: c.day)) ?? date
        return Int(midnight.timeIntervalSince1970 / 86400)
    }
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
    public static let beanie = RGBA(0x4F6FA8)
    public static let beanieRib = RGBA(0x7B95C6)
    public static let crownGold = RGBA(0xE8B931)
    public static let crownShade = RGBA(0xB8891A)
    public static let bowPink = RGBA(0xE45C93)
    public static let petal = RGBA(0xFFFFFF)
    public static let petalCenter = RGBA(0xF6D365)
    public static let propellerBlue = RGBA(0x3D8BD9)
    public static let lens = RGBA(0x1C1B26)
    public static let scarf = RGBA(0xE07A5F)
    public static let scarfStripe = RGBA(0xF2CC8F)
    public static let mustache = RGBA(0x5A3A22)
    /// LM's diamond: light left half, dark right half.
    public static let crystalLight = RGBA(0xBFF3F5)
    public static let crystalDark = RGBA(0x4CB8C6)
    /// A drop of water (LM's fidgets).
    public static let water = RGBA(0x3FA3E8)
    public static let waterLight = RGBA(0xD6F2FF)
    /// The coffee mug on the desk during long work (its steam reuses `steam`).
    public static let mug = RGBA(0xF1EFE8)
    public static let mugShade = RGBA(0xB4B2A9)
    public static let coffee = RGBA(0x6B4A2E)
    /// The little YubiKey: black body, gold touch pad (lit while it waits), silver USB plug.
    public static let keyBody = RGBA(0x2C2C2A)
    public static let keyGold = RGBA(0xC9962B)
    public static let keyGoldLit = RGBA(0xFAD978)
    public static let keyPlug = RGBA(0xC9C7C0)
    public static let tea = RGBA(0xB5732F)
    /// The hookah: glass vase, clay bowl, a coal, smoke.
    public static let hookahGlass = RGBA(0x5DA9C4)
    public static let hookahWater = RGBA(0x3A7F9A)
    public static let hookahClay = RGBA(0x9C5A3C)
    public static let coal = RGBA(0xE24B4A)
    public static let smoke = RGBA(0xD3D1C7, alpha: 200)
    public static let smokeDense = RGBA(0xE8E6DF, alpha: 245)
    public static let lamp = RGBA(0x5F5E5A)
    public static let lampLight = RGBA(0xFAD978, alpha: 55)
    public static let batteryRed = RGBA(0xE24B4A)
    public static let batteryGreen = RGBA(0x5DCAA5)
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
    /// Late at night: a desk lamp, and tea instead of coffee in the mug.
    public static let lamp = WorkProps(rawValue: 4)
    public static let tea = WorkProps(rawValue: 8)
}

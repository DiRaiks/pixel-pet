/// Colors from the prototype. The sprite is drawn on the desktop, so it carries its own outline and shadow.
public enum Palette {
    public static let outline = RGBA(0x26215C)
    public static let fill = RGBA(0x7F77DD)
    public static let highlight = RGBA(0xAFA9EC)
    public static let shade = RGBA(0x534AB7)
    public static let empty = RGBA(0xEEEDFE)
    public static let eye = RGBA(0x26215C)
    public static let glint = RGBA(0xFFFFFF)
    public static let glow = RGBA(0xEEEDFE)
    public static let shadow = RGBA(0x000000, alpha: 46)
    public static let notch = RGBA(0x000000)
    public static let menuBar = RGBA(0xD3D1C7)

    public static let amber = RGBA(0xEF9F27)
    public static let amberDark = RGBA(0x412402)
    public static let teal = RGBA(0x1D9E75)
    public static let tealLight = RGBA(0x9FE1CB)
    public static let sweat = RGBA(0x85B7EB)
    public static let sweatDark = RGBA(0x378ADD)
    public static let errorFill = RGBA(0xE24B4A)
    public static let errorHighlight = RGBA(0xF09595)
    public static let errorShade = RGBA(0xA32D2D)
    public static let errorDark = RGBA(0x501313)
    public static let white = RGBA(0xFFFFFF)
    /// Menu-bar icons are templates: only alpha matters, macOS tints them for light and dark bars.
    public static let template = RGBA(0x000000)
}

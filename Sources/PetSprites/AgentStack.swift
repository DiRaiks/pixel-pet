import PetCore

/// The column of 3x3 agent blocks to the right of the pet, drawn on its own 32x32 overlay.
public enum AgentStack {
    public static let x = 27
    public static let bottomY = 24
    public static let step = 4
    public static let maxVisible = 5

    public static func canvas(for cubes: [AgentCube], tick: Int) -> PixelCanvas {
        var c = PixelCanvas()
        let overflow = cubes.count > maxVisible
        let shown = overflow ? Array(cubes.prefix(maxVisible - 1)) : cubes
        for (k, cube) in shown.enumerated() {
            draw(cube, slot: k, tick: tick, on: &c)
        }
        if overflow {
            let y = bottomY - (maxVisible - 1) * step + 1
            for dx in stride(from: 0, through: 4, by: 2) { c.set(x + dx, y, Palette.shade) }
        }
        return c
    }

    private static func draw(_ cube: AgentCube, slot k: Int, tick: Int, on c: inout PixelCanvas) {
        var y = bottomY - k * step
        switch cube.status {
        case .idle:
            c.agentCube(x, y, Palette.agentIdle)
        case .done:
            c.agentCube(x, y, Palette.agentDone)
        case .working:
            c.agentCube(x, y, Palette.teal, spin: tick + k * 2)
        case .waiting:
            if (tick + k * 3) % 12 < 3 { y -= 1 }
            c.agentCube(x, y, Palette.amber)
            if tick % 4 < 2 { c.set(x + 1, y + 1, Palette.amberDark) }
        case .failed:
            c.agentCube(x, y, Palette.errorFill)
            if tick % 4 < 2 { c.set(x + 1, y + 1, Palette.errorDark) }
        }
        if cube.subagents > 0 { c.set(x + 3, y, Palette.tealLight) }
    }
}

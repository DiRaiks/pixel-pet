import AppKit
import PetCore
import PetSprites

/// Owns the pet window: frame clock, rendering, click/drag behavior and persisted placement.
@MainActor
final class PetController {
    static let spriteSize = 32.0

    private let store: ConfigStore
    private let sprites: SpriteLibrary
    private(set) var config: PetConfig
    private var player = PetPlayer(base: .idle)
    /// The state the pet returns to after dragging; agent activity (or the debug menu) sets it.
    private(set) var restingState = PetState.idle
    private var agents: [AgentCube] = []
    private var drain = 0
    /// Extra hooks for the app: a plain click (after the hop) and the start of a drag.
    var onTap: (() -> Void)?
    var onDragStart: (() -> Void)?
    var anchorView: NSView { view }

    private let panel: PetPanel
    private let view: PetView
    private var timer: Timer?
    private var timerState: PetState?
    private var lastTick = CACurrentMediaTime()
    /// Bumped whenever a flick animation starts or is cancelled, so stale completions don't persist.
    private var moveGeneration = 0
    private var observers: [NSObjectProtocol] = []
    var contextMenu: NSMenu?

    init(store: ConfigStore, sprites: SpriteLibrary) {
        self.store = store
        self.sprites = sprites
        config = store.load()
        let side = Self.spriteSize * Double(config.scale)
        panel = PetPanel(size: NSSize(width: side, height: side))
        view = PetView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.scale = CGFloat(config.scale)
        panel.contentView = view
        wireInput()
    }

    func start() {
        placeOnScreen()
        render()
        if !config.isHidden { panel.orderFrontRegardless() }
        updateClock()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.placeOnScreen() }
            },
            // Covered, hidden or on a sleeping display: stop waking up for frames nobody sees.
            center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateClock() }
            },
        ]
    }

    // MARK: Commands (menu)

    var isHidden: Bool { config.isHidden }

    func setHidden(_ hidden: Bool) {
        config.isHidden = hidden
        hidden ? panel.orderOut(nil) : panel.orderFrontRegardless()
        updateClock()
        persist()
    }

    /// Saved only when the numbers change; statusline snapshots arrive several times a second.
    func rememberLimits(_ limits: UsageLimits?) {
        if let limits, let saved = config.lastLimits, limits.sameWindows(as: saved) { return }
        config.lastLimits = limits
        persist()
    }

    func setLogEvents(_ enabled: Bool) {
        config.logEvents = enabled
        persist()
    }

    func setScale(_ scale: Int) {
        guard PetConfig.scaleRange.contains(scale), scale != config.scale else { return }
        let anchor = NSPoint(x: panel.frame.midX, y: panel.frame.minY)
        config.scale = scale
        let side = Self.spriteSize * Double(scale)
        view.scale = CGFloat(scale)
        panel.setFrame(NSRect(x: anchor.x - side / 2, y: anchor.y, width: side, height: side), display: true)
        config.origin = PetPoint(panel.frame.origin)
        placeOnScreen()
        persistOrigin()
    }

    // MARK: Agents

    /// Agent activity decides the resting state; while dragged the pet keeps dangling and picks it up on drop.
    func setMood(_ state: PetState) {
        guard state != restingState else { return }
        restingState = state
        guard player.state != .dragged else { return }
        player.setBase(state)
        render()
        updateClock()
    }

    func react(_ oneShot: PetState) {
        guard player.state != .dragged else { return }
        player.play(oneShot)
        render()
        updateClock()
    }

    func setDrain(_ rows: Int) {
        guard rows != drain else { return }
        drain = rows
        render()
    }

    func setAgents(_ cubes: [AgentCube]) {
        guard cubes != agents else { return }
        agents = cubes
        renderAgents()
        updateClock()
    }

    /// Looping states become the resting state; one-shots play once on top of it.
    func preview(_ state: PetState) {
        if state.loops { restingState = state }
        player.play(state)
        render()
        updateClock()
    }

    // MARK: Input

    private func wireInput() {
        view.onPress = { [weak self] in self?.cancelFlick() }
        view.onClick = { [weak self] in
            guard let self else { return }
            react(.hop)
            onTap?()
        }
        view.onDragBegan = { [weak self] in
            guard let self else { return }
            onDragStart?()
            player.play(.dragged)
            render()
            updateClock()
        }
        view.onDragEnded = { [weak self] velocity in self?.endDrag(velocity: velocity) }
        view.onContextMenu = { [weak self] event in
            guard let self, let menu = contextMenu else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        }
    }

    private func endDrag(velocity: PetPoint) {
        player.play(restingState)
        player.play(.drop)
        render()
        updateClock()

        let destination = Placement.flickDestination(from: PetPoint(panel.frame.origin), velocity: velocity,
                                                     size: PetSize(panel.frame.size), screens: screens())
        moveGeneration += 1
        let generation = moveGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            panel.animator().setFrameOrigin(destination.ns)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.moveGeneration else { return }
                self.persistOrigin()
            }
        })
    }

    /// Grabbing the pet mid-flight stops the flick where it is, so the cursor and the animation don't fight.
    private func cancelFlick() {
        moveGeneration += 1
        let origin = panel.frame.origin
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().setFrameOrigin(origin)
        }
    }

    // MARK: Frames

    private var isOnScreen: Bool {
        !config.isHidden && panel.occlusionState.contains(.visible)
    }

    /// Runs the frame timer only while the pet is visible, at the current state's frame rate.
    private func updateClock() {
        guard isOnScreen else {
            timer?.invalidate()
            timer = nil
            timerState = nil
            return
        }
        guard timerState != player.state else { return }
        timer?.invalidate()
        timerState = player.state
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1 / player.state.fps, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.2 / player.state.fps
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let changed = player.advance(by: now - lastTick)
        lastTick = now
        if changed {
            render()
            if !agents.isEmpty { renderAgents() }
        }
        updateClock()
    }

    private func render() {
        let frame = sprites.frame(player.state, player.frame, drain: drain)
        view.show(frame.image, canvas: frame.canvas)
    }

    /// The stack animates on a shared 10 Hz beat so it doesn't speed up or slow down with the pet's state.
    private func renderAgents() {
        let canvas = AgentStack.canvas(for: agents, tick: Int(CACurrentMediaTime() * 10))
        view.showAgents(canvas.opaquePixelCount > 0 ? canvas.makeImage() : nil, canvas: canvas)
    }

    // MARK: Placement

    private func screens() -> [PetScreen] {
        NSScreen.screens.map { PetScreen(frame: PetRect($0.frame), visible: PetRect($0.visibleFrame)) }
    }

    private func placeOnScreen() {
        let origin = Placement.resolve(saved: config.origin, size: PetSize(panel.frame.size), screens: screens())
        panel.setFrameOrigin(origin.ns)
    }

    private func persistOrigin() {
        config.origin = PetPoint(panel.frame.origin)
        persist()
    }

    private func persist() {
        do {
            try store.save(config)
        } catch {
            NSLog("PixelPet: failed to save config: \(error.localizedDescription)")
        }
    }
}

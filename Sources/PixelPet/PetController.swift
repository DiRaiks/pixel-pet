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
    /// What agent activity (or the debug menu) asks for, before home and do-not-disturb are applied.
    private var mood = PetState.idle
    /// The state the pet returns to after dragging: `mood` on the desk, its home version at home.
    private(set) var restingState = PetState.idle
    private var hoverPeek: DispatchWorkItem?
    /// The pet "talks" while the translation card is open.
    private var talking = false
    /// When to doze off, and a live reading of how long the user has been away (sampled each time the
    /// rest state is decided, so a keyboard-only return is never judged from an old reading).
    private var sleepAfter: TimeInterval { Double(config.sleepAfterMinutes) * 60 }
    var userIdleProvider: () -> TimeInterval = {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
    private var cursorGaze: Gaze?
    private var glance: Gaze?
    private var glanceGeneration = 0
    private var dimmed = false
    /// The pet moved, changed screens, went home or out, or was hidden: desktop reactions re-check.
    var onPlacementChange: (() -> Void)?
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
        if config.isHome { panel.level = .statusBar }
        restingState = resolvedRest()
        player.play(restingState)
        placeOnScreen()
        render()
        if !config.isHidden { panel.orderFrontRegardless() }
        updateClock()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.placeOnScreen()
                    self?.onPlacementChange?()
                }
            },
            // Covered, hidden or on a sleeping display: stop waking up for frames nobody sees.
            center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.updateClock()
                    if self.panel.occlusionState.contains(.visible) { self.settleHome() }
                }
            },
        ]
        // While the screen is locked or the displays sleep, macOS reports other screen geometry and the window
        // can be left off its home; no screen-parameter change follows on wake, so re-seat it explicitly.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.settleHomeSoon() }
            })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.settleHomeSoon() }
        })
    }

    // MARK: Commands (menu)

    var isHidden: Bool { config.isHidden }

    func setHidden(_ hidden: Bool) {
        config.isHidden = hidden
        hidden ? panel.orderOut(nil) : panel.orderFrontRegardless()
        updateClock()
        persist()
        onPlacementChange?()
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
        mood = state
        applyRest()
    }

    /// One-shots (hop, celebrate) become a quick peek at home, or nothing under do-not-disturb.
    func react(_ oneShot: PetState) {
        guard player.state != .dragged else { return }
        let shown = config.isHome ? PetBrain.homeReaction(to: oneShot, doNotDisturb: config.doNotDisturb) : oneShot
        guard let shown, !(config.isHome && (player.state == .peekHold || player.state == .dive)) else { return }
        player.play(shown)
        render()
        updateClock()
    }

    private func resolvedRest() -> PetState {
        if config.isHome { return PetBrain.homeState(for: mood, doNotDisturb: config.doNotDisturb) }
        // Talking (translation card open) yields to errors and waiting agents.
        if talking && mood != .error && mood != .alert { return .talk }
        let idle = mood == .idle && sleepAfter > 0 ? userIdleProvider() : 0
        return PetBrain.restState(mood: mood, userIdle: idle, sleepAfter: sleepAfter)
    }

    // MARK: Desktop reactions

    /// Re-decides sleep from the current idle time; greets with a hop when the user comes back.
    func checkUserIdle() {
        let wasAsleep = restingState == .sleep
        applyRest()
        if wasAsleep, restingState != .sleep { react(.hop) }
    }

    /// Eyes follow the cursor when it's near (nil: far away, the pet keeps its own glances).
    func setCursorGaze(_ gaze: Gaze?) {
        guard gaze != cursorGaze else { return }
        let before = currentGaze
        cursorGaze = gaze
        if currentGaze != before, isOnScreen, !config.isHome, player.state == .idle { render() }
    }

    /// A short look toward a point on screen, e.g. the window the user just switched to.
    /// Returns false when there's nothing to look at (straight ahead or at home).
    @discardableResult
    func glance(at point: PetPoint, for duration: TimeInterval = 1.5) -> Bool {
        guard !config.isHome, let gaze = Gaze.toward(point, from: center, radius: .infinity),
              gaze != Gaze(x: 0, y: 0) else { return false }
        glanceGeneration += 1
        let generation = glanceGeneration
        glance = gaze
        if isOnScreen, player.state == .idle { render() }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, generation == glanceGeneration else { return }
            glance = nil
            if isOnScreen, player.state == .idle { render() }
        }
        return true
    }

    /// Fades out of the way over fullscreen apps (video, presentations) instead of hiding.
    func setDimmed(_ on: Bool) {
        guard on != dimmed else { return }
        dimmed = on
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = on ? 0.3 : 1
        }
    }

    var center: PetPoint { PetPoint(x: panel.frame.midX, y: panel.frame.midY) }
    var screenFrame: NSRect? { panel.screen?.frame }

    func greet() { react(.hop) }

    /// Reactions off (or pet hidden/home): forget where the cursor was and undo dimming.
    func resetDesktopReactions() {
        cursorGaze = nil
        glance = nil
        setDimmed(false)
        if isOnScreen { render() }
    }

    private var currentGaze: Gaze? {
        glance ?? cursorGaze
    }

    func setTalking(_ on: Bool) {
        talking = on
        applyRest()
    }

    private func applyRest() {
        let rest = resolvedRest()
        guard rest != restingState else { return }
        restingState = rest
        guard player.state != .dragged else { return }
        player.setBase(rest)
        render()
        updateClock()
    }

    // MARK: Home

    var isHome: Bool { config.isHome }
    var doNotDisturb: Bool { config.doNotDisturb }

    /// Do-not-disturb sends the pet home; it only comes out for errors until switched off or pulled out.
    func setDoNotDisturb(_ on: Bool) {
        guard player.state != .dragged else { return }
        config.doNotDisturb = on
        persist()
        if on, !config.isHome, let home = nearestHome() {
            goHome(home, dive: true)
        } else {
            applyRest()
        }
    }

    func toggleHome() {
        guard player.state != .dragged else { return }
        if config.isHome {
            leaveHome(clearDoNotDisturb: true)
            // Back to where it last sat on the desk, or a little below the hole.
            let size = PetSize(panel.frame.size)
            let fallback = PetPoint(x: panel.frame.minX, y: panel.frame.minY - 160)
            let desk = Placement.resolve(saved: config.origin ?? fallback, size: size, screens: screens())
            player.play(.drop)
            render()
            updateClock()
            animateMove(to: desk)
        } else if let home = nearestHome() {
            goHome(home, dive: true)
        }
    }

    struct Home {
        let spot: HomeSpot
        let display: UInt32?
    }

    private func homeDisplay() -> UInt32? { config.homeDisplay ?? NSScreen.screens.first.flatMap(Self.displayID) }

    private func homeSpots() -> [Home] {
        NSScreen.screens.map { screen in
            Home(spot: HomeGeometry.home(on: PetScreen(frame: PetRect(screen.frame), visible: PetRect(screen.visibleFrame)),
                                         notch: Self.notchRect(screen)),
                 display: Self.displayID(screen))
        }
    }

    static func displayID(_ screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func notchRect(_ screen: NSScreen) -> PetRect? {
        HomeGeometry.notch(screen: PetRect(screen.frame), left: screen.auxiliaryTopLeftArea.map(PetRect.init),
                           right: screen.auxiliaryTopRightArea.map(PetRect.init), safeTop: screen.safeAreaInsets.top)
    }

    /// Home on the screen the pet is on now, falling back to the remembered one and then the menu-bar screen.
    private func nearestHome() -> Home? {
        let homes = homeSpots()
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let current = NSScreen.screens.first { $0.frame.contains(center) }.flatMap(Self.displayID)
        return homes.first { $0.display == current } ?? homes.first { $0.display == homeDisplay() } ?? homes.first
    }

    private func goHome(_ home: Home, dive: Bool) {
        config.isHome = true
        config.homeDisplay = home.display
        panel.level = .statusBar
        persist()
        restingState = resolvedRest()
        player.play(restingState)
        if dive { player.play(.dive) }
        render()
        renderAgents()
        updateClock()
        animateMove(to: HomeGeometry.windowOrigin(for: home.spot, size: PetSize(panel.frame.size)), persistDesk: false)
        onPlacementChange?()
    }

    /// Leaving clears do-not-disturb only when the pet really ends up on the desk; a drag that snaps back
    /// home keeps it (that decision is made on drop).
    private func leaveHome(clearDoNotDisturb: Bool) {
        guard config.isHome else { return }
        config.isHome = false
        if clearDoNotDisturb { config.doNotDisturb = false }
        panel.level = .floating
        persist()
        restingState = resolvedRest()
        player.setBase(restingState)
        renderAgents()
        onPlacementChange?()
    }

    private func hover(_ inside: Bool) {
        hoverPeek?.cancel()
        hoverPeek = nil
        guard inside, config.isHome, player.state == .burrowed else { return }
        // A short delay so passing the cursor over the menu bar doesn't trigger it.
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.player.state == .burrowed else { return }
                self.player.play(.peek)
                self.render()
                self.updateClock()
            }
        }
        hoverPeek = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
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
    /// Debug menu: mood states go through the same home rules as agent activity; home-only states just play.
    func preview(_ state: PetState) {
        let homeOnly: Set<PetState> = [.burrowed, .peekHold, .dive]
        if !homeOnly.contains(state) {
            if state.loops {
                mood = state
                applyRest()
            } else {
                react(state)
            }
            return
        }
        player.play(state)
        render()
        updateClock()
    }

    // MARK: Input

    private func wireInput() {
        view.onPress = { [weak self] in self?.cancelFlick() }
        view.onHover = { [weak self] inside in self?.hover(inside) }
        view.onClick = { [weak self] in
            guard let self else { return }
            react(.hop)
            onTap?()
        }
        view.onDragBegan = { [weak self] in
            guard let self else { return }
            onDragStart?()
            leaveHome(clearDoNotDisturb: false)
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
        let size = PetSize(panel.frame.size)
        let homes = homeSpots()
        let origin = PetPoint(panel.frame.origin)
        // A flick toward a home counts too: check where it's thrown, not only where it was let go.
        let thrown = PetPoint(x: origin.x + velocity.x * Placement.throwTime, y: origin.y + velocity.y * Placement.throwTime)
        let spot = HomeGeometry.snapTarget(windowOrigin: origin, size: size, homes: homes.map(\.spot))
            ?? HomeGeometry.snapTarget(windowOrigin: thrown, size: size, homes: homes.map(\.spot))
        if let spot, let home = homes.first(where: { $0.spot == spot }) {
            goHome(home, dive: true)
            return
        }
        if config.doNotDisturb {
            config.doNotDisturb = false
            persist()
            restingState = resolvedRest()
        }
        player.play(restingState)
        player.play(.drop)
        render()
        updateClock()

        let destination = Placement.flickDestination(from: PetPoint(panel.frame.origin), velocity: velocity,
                                                     size: size, screens: screens())
        animateMove(to: destination)
    }

    /// Eases the window to a point; on the desk the final position is remembered.
    private func animateMove(to destination: PetPoint, persistDesk: Bool = true) {
        moveGeneration += 1
        let generation = moveGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            panel.animator().setFrameOrigin(destination.ns)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.moveGeneration, persistDesk, !self.config.isHome else { return }
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
            if !agents.isEmpty, !config.isHome { renderAgents() }
        }
        updateClock()
    }

    private func render() {
        // At home the top of the body is inside the hole, so a drained band would only show as a stray stripe.
        let frame = sprites.frame(player.state, player.frame, drain: config.isHome ? 0 : drain,
                                  gaze: config.isHome ? nil : currentGaze)
        view.show(frame.image, canvas: frame.canvas)
    }

    /// The stack animates on a shared 10 Hz beat so it doesn't speed up or slow down with the pet's state.
    private func renderAgents() {
        // At home the stack would sit in the menu bar; the menu-bar counter covers it there.
        let canvas = AgentStack.canvas(for: config.isHome ? [] : agents, tick: Int(CACurrentMediaTime() * 10))
        view.showAgents(canvas.opaquePixelCount > 0 ? canvas.makeImage() : nil, canvas: canvas)
    }

    // MARK: Placement

    private func screens() -> [PetScreen] {
        NSScreen.screens.map { PetScreen(frame: PetRect($0.frame), visible: PetRect($0.visibleFrame)) }
    }

    /// Puts a pet that lives at home back exactly on its home spot (no-op on the desk or mid-move).
    private func settleHome() {
        guard config.isHome, player.state != .dragged else { return }
        placeOnScreen()
    }

    /// Screens report their final geometry a moment after wake or unlock.
    private func settleHomeSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            MainActor.assumeIsolated { self?.settleHome() }
        }
    }

    private func placeOnScreen() {
        if config.isHome {
            let homes = homeSpots()
            if let home = homes.first(where: { $0.display == homeDisplay() }) ?? homes.first {
                panel.setFrameOrigin(HomeGeometry.windowOrigin(for: home.spot, size: PetSize(panel.frame.size)).ns)
            }
            return
        }
        let origin = Placement.resolve(saved: config.origin, size: PetSize(panel.frame.size), screens: screens())
        panel.setFrameOrigin(origin.ns)
    }

    private func persistOrigin() {
        config.origin = PetPoint(panel.frame.origin)
        persist()
        onPlacementChange?()
    }

    private func persist() {
        do {
            try store.save(config)
        } catch {
            NSLog("PixelPet: failed to save config: \(error.localizedDescription)")
        }
    }
}

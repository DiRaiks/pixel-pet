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
    /// The home a drag in progress started from (nil when it started on the desk).
    private var dragHome: HomeSpot?
    /// A status, translation or ask card is open (the pet stays calm under it).
    var isCardOpen: () -> Bool = { false }
    /// Desk-side reactions to the user: recent clicks (too many → cross), lingering cursor (→ shy).
    private var recentClicks: [Date] = []
    private var shyTimer: DispatchWorkItem?
    private var lastShy = Date.distantPast
    /// Rare idle fidgets (yawn, a roll) at random intervals, so the idle loop doesn't feel canned.
    private var nextFidget = Date().addingTimeInterval(PetController.fidgetDelay())
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
    /// System Settings → Accessibility → Display → Reduce motion.
    private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    /// Under Reduce Motion a skipped one-shot leaves a held frame for a moment instead.
    private var held: MotionPolicy.Cue?
    private var heldGeneration = 0
    private var agents: [AgentCube] = []
    private var drain = 0
    /// Extra hooks for the app: a plain click (after the hop) and the start of a drag.
    var onTap: (() -> Void)?
    var onDragStart: (() -> Void)?
    var anchorView: NSView { view }

    private let panel: PetPanel
    private let view: PetView
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    /// Bumped whenever a flick animation starts or is cancelled, so stale completions don't persist.
    private var moveGeneration = 0
    private var observers: [NSObjectProtocol] = []
    var contextMenu: NSMenu?

    init(store: ConfigStore, sprites: SpriteLibrary) {
        self.store = store
        self.sprites = sprites
        config = store.load()
        sprites.setLook(Self.look(from: config))
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
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                self.render()
                self.renderAgents()
                self.updateClock()
            }
        })
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

    /// Settings changes: save, re-decide the resting state, let desktop reactions re-check.
    func updateConfig(_ change: (inout PetConfig) -> Void) {
        change(&config)
        persist()
        applyRest()
        onPlacementChange?()
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
    /// Returns whether something was shown.
    @discardableResult
    func react(_ oneShot: PetState) -> Bool {
        guard player.state != .dragged else { return false }
        let shown = config.isHome ? PetBrain.homeReaction(to: oneShot, doNotDisturb: config.doNotDisturb) : oneShot
        guard let shown, !(config.isHome && (player.state == .peekHold || player.state == .dive)) else { return false }
        if reduceMotion, !MotionPolicy.allowsOneShot(shown) {
            guard let cue = MotionPolicy.cue(for: shown) else { return false }
            hold(cue)
            return true
        }
        player.play(shown)
        render()
        updateClock()
        return true
    }

    private func hold(_ cue: MotionPolicy.Cue, for duration: TimeInterval = 1.5) {
        heldGeneration += 1
        let generation = heldGeneration
        held = cue
        render()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, generation == heldGeneration else { return }
            held = nil
            render()
        }
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

    // MARK: Personality

    static let clickWindow: TimeInterval = 3
    static let clicksToAnnoy = 5
    static let shyAfter: TimeInterval = 2
    static let shyCooldown: TimeInterval = 60

    /// 1.5–4 minutes between fidgets: rare enough to stay a surprise.
    static func fidgetDelay() -> TimeInterval { Double.random(in: 90...240) }

    private func maybeFidget() {
        guard Date() >= nextFidget else { return }
        nextFidget = Date().addingTimeInterval(Self.fidgetDelay())
        // Only a pet idling on the desk fidgets; never over another animation, at home or with Reduce Motion.
        guard !config.isHome, config.desktopReactions, player.state == .idle, restingState == .idle, !reduceMotion,
              held == nil, glance == nil, !isCardOpen() else { return }
        player.play(Int.random(in: 0..<3) == 0 ? .tumble : .yawn)
        render()
    }

    /// The cursor resting on the pet for a while makes it shy (at most once a minute).
    private func scheduleShy() {
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.player.state == .idle, self.config.desktopReactions, !self.isCardOpen(),
                      Date().timeIntervalSince(self.lastShy) > Self.shyCooldown else { return }
                if self.react(.shy) { self.lastShy = Date() }
            }
        }
        shyTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shyAfter, execute: work)
    }

    /// Skin and accessory changed in settings: redraw everything in the new look.
    func setLook(skin: String, accessory: String) {
        config.skin = skin
        config.accessory = accessory
        persist()
        sprites.setLook(Self.look(from: config))
        render()
    }

    static func look(from config: PetConfig) -> Look {
        Look(skin: Skin.named(config.skin), accessory: Accessory(rawValue: config.accessory) ?? .none)
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
            if !reduceMotion { player.play(.drop) }
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
        if dive, !reduceMotion { player.play(.dive) }
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
        shyTimer?.cancel()
        shyTimer = nil
        if inside, !config.isHome { scheduleShy() }
        guard inside, config.isHome, player.state == .burrowed else { return }
        // A short delay so passing the cursor over the menu bar doesn't trigger it.
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.player.state == .burrowed, !self.reduceMotion else { return }
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
            let now = Date()
            recentClicks = config.isHome ? [] : recentClicks.filter { now.timeIntervalSince($0) < Self.clickWindow } + [now]
            if recentClicks.count >= Self.clicksToAnnoy {
                recentClicks.removeAll()
                react(.angry)
            } else {
                react(.hop)
            }
            onTap?()
        }
        view.onDragBegan = { [weak self] in
            guard let self else { return }
            onDragStart?()
            dragHome = config.isHome ? nearestHome()?.spot : nil
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
        let leaving = dragHome
        dragHome = nil
        let spot = HomeGeometry.snapTarget(windowOrigin: origin, size: size, homes: homes.map(\.spot), leaving: leaving)
            ?? HomeGeometry.snapTarget(windowOrigin: thrown, size: size, homes: homes.map(\.spot), leaving: leaving)
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
        if !reduceMotion { player.play(.drop) }
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
        if reduceMotion {
            // No sliding or throwing: the pet is simply where it lands.
            cancelFlick()
            panel.setFrameOrigin(destination.ns)
            if persistDesk, !config.isHome { persistOrigin() }
            return
        }
        // Animate the whole frame: on macOS 26+ the window animator ignores setFrameOrigin, which left the
        // pet wherever it was let go (even above the top edge, out of sight, when dropped into its home).
        let target = NSRect(origin: destination.ns, size: panel.frame.size)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.moveGeneration else { return }
                // Land exactly, even if the animation was skipped.
                if self.panel.frame.origin != target.origin { self.panel.setFrameOrigin(target.origin) }
                guard persistDesk, !self.config.isHome else { return }
                self.persistOrigin()
            }
        })
    }

    /// Grabbing the pet mid-flight stops the flick where it is, so the cursor and the animation don't fight.
    private func cancelFlick() {
        moveGeneration += 1
        let frame = panel.frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().setFrame(frame, display: false)
        }
    }

    // MARK: Frames

    private var isOnScreen: Bool {
        !config.isHidden && panel.occlusionState.contains(.visible)
    }

    /// Runs the frame timer only while the pet is visible, at the current state's frame rate.
    /// One wake-up per frame, exactly when the current frame ends (every frame has its own duration).
    /// While agent cubes are on screen the clock also keeps their 10 Hz beat.
    private func updateClock(fromTick: Bool = false) {
        // A frozen state under Reduce Motion has nothing to animate: no frame timer at all.
        let frozen = reduceMotion && MotionPolicy.stillFrame(for: player.state) != nil
        let wasRunning = timer != nil
        timer?.invalidate()
        timer = nil
        guard isOnScreen, !frozen else { return }
        let now = CACurrentMediaTime()
        if !fromTick {
            if wasRunning {
                // Account for time already spent in this frame, so outside calls never stretch it.
                if player.advance(by: now - lastTick) { render() }
            } else {
                // Resuming after being hidden or occluded: no instant catch-up fidget either.
                nextFidget = Date().addingTimeInterval(Self.fidgetDelay())
            }
            lastTick = now
        }
        let animatedCubes = !agents.isEmpty && !config.isHome && !reduceMotion
        let delay = max(0.008, animatedCubes ? min(player.timeToNextFrame, 0.1) : player.timeToNextFrame)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = min(0.05, delay * 0.25)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let changed = player.advance(by: now - lastTick)
        lastTick = now
        if changed { render() }
        if !agents.isEmpty, !config.isHome, !reduceMotion { renderAgents() }
        maybeFidget()
        updateClock(fromTick: true)
    }

    private func render() {
        // At home the top of the body is inside the hole, so a drained band would only show as a stray stripe.
        let state = held?.state ?? player.state
        let index = held?.frame ?? (reduceMotion ? (MotionPolicy.stillFrame(for: state) ?? player.frame) : player.frame)
        let frame = sprites.frame(state, index, drain: config.isHome ? 0 : drain,
                                  gaze: config.isHome ? nil : currentGaze)
        view.show(frame.image, canvas: frame.canvas)
    }

    /// The stack animates on a shared 10 Hz beat so it doesn't speed up or slow down with the pet's state.
    private func renderAgents() {
        // At home the stack would sit in the menu bar; the menu-bar counter covers it there.
        // Reduce Motion: the cubes keep their colors but stop spinning and bouncing.
        let tick = reduceMotion ? 0 : Int(CACurrentMediaTime() * 10)
        let canvas = AgentStack.canvas(for: config.isHome ? [] : agents, tick: tick)
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

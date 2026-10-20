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
    /// Rubbing the cursor over the pet pets it.
    private var petting = PettingDetector()
    /// What the agent is doing (the bubble over the keyboard), and the oldest wait for the user (waving).
    private var toolKind: ToolKind?
    private var waitingSince: Date?
    private var lastWave: Date?
    private var waveTimer: DispatchWorkItem?
    /// Rare idle fidgets (yawn, a roll) at random intervals, so the idle loop doesn't feel canned.
    private var nextFidget = Date().addingTimeInterval(PetController.fidgetDelay())
    /// The same at the keyboard while agents work: a sip, a stretch, a think, a burst of typing.
    private var nextWorkMoment = Date().addingTimeInterval(WorkMoments.delay())
    private var lastWorkMoment: PetState?
    private var lastAgentGlance = Date.distantPast
    /// What piles up on the desk as work goes on.
    private var workStage = WorkStage.fresh
    /// A call coming up (from the calendar, when that's on).
    private var meetingPhase = MeetingPlan.Phase.none
    /// The Mac's power (nil until read, or without a battery reading).
    private var power: PowerReading?
    private var mac = MacState()
    /// Mac states the user clicked away, until they end.
    private var macDismissed = MacDismissals()
    private var fullCelebrated = false
    /// Redraws the desk when the night lamp goes on or off.
    private var nightCheck: DispatchWorkItem?
    /// A hardware key waiting for a touch: shown above everything else.
    private var touchWait = TouchWait()
    private var touching = false {
        didSet { if touching != oldValue { onTouching?(touching) } }
    }
    /// A hardware key started or stopped waiting for a touch.
    var onTouching: ((Bool) -> Void)?
    /// The weekly recap is in: reads the newspaper while calm, until clicked.
    private(set) var hasNews = false
    /// A click on the newspaper: open the recap.
    var onOpenNews: (() -> Void)?
    private var touchEnd: DispatchWorkItem?
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
    /// Codex agents, drawn in the left column.
    private var codexAgents: [AgentCube] = []
    private var drain = 0
    /// Extra hooks for the app: a plain click (after the hop) and the start of a drag.
    var onTap: (() -> Void)?
    /// A click while the pet gets ready for a call: dismiss that reminder (the card doesn't open).
    var onDismissMeeting: (() -> Void)?
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
        scheduleNightCheck()
        scheduleDayChange()
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
                // A keyboard moment is pure motion: cut it short.
                if self.reduceMotion, self.player.state.isAtDesk, self.player.state != .working {
                    self.player.play(self.restingState)
                }
                self.render()
                self.renderAgents()
                self.updateClock()
            }
        })
        // While the screen is locked or the displays sleep, macOS reports other screen geometry and the window
        // can be left off its home; no screen-parameter change follows on wake, so re-seat it explicitly.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleNightCheck()
                self?.scheduleDayChange()
                // Woke up on another day: today's look.
                if let self { self.sprites.setLook(self.currentLook()) }
                self?.render()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleNightCheck() }
        })
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

    func rememberCodexLimits(_ limits: UsageLimits?) {
        if let limits, let saved = config.lastCodexLimits, limits.sameWindows(as: saved) { return }
        config.lastCodexLimits = limits
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
        // The key waiting for a touch is what the user is waiting on right now, even under do-not-disturb.
        if touching { return config.isHome ? .touchKeyHome : .touchKey }
        if config.isHome {
            let home = PetBrain.homeState(for: mood, doNotDisturb: config.doNotDisturb)
            // The last minute before a call: out of the hole to say so (not under do-not-disturb).
            if home == .burrowed, meetingPhase == .now, !config.doNotDisturb { return .peekHold }
            return home
        }
        // Talking (translation card open) yields to errors and waiting agents.
        if talking && mood != .error && mood != .alert && mood != .question { return .talk }
        // A call coming up beats working and resting, but not an agent that needs you or an error.
        if meetingPhase != .none, mood != .error, mood != .alert, mood != .question {
            return meetingPhase == .now ? .meetingNow : .meetingSoon
        }
        let idle = mood == .idle && sleepAfter > 0 ? userIdleProvider() : 0
        let rest = PetBrain.restState(mood: mood, userIdle: idle, sleepAfter: sleepAfter)
        // The recap waits behind anything going on: only while idle and awake.
        if hasNews, rest == .idle, !config.doNotDisturb { return .newspaper }
        // Idle on a nearly flat battery: droopy instead. Otherwise the Mac may give it something to do.
        return rest == .idle && power?.isLow == true ? .tired : mac.rest(insteadOf: rest, skipping: macDismissed.states)
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
        // Typing starts: the first moment comes a while later, not right away.
        if rest == .working { nextWorkMoment = Date().addingTimeInterval(WorkMoments.delay()) }
        // A keyboard moment belongs to the typing; when that stops (talking, an alert, done) it stops too.
        // A key wanting a touch cuts in at once.
        if rest == .touchKey || rest == .touchKeyHome || (player.state.isAtDesk && player.state != .working) {
            player.play(rest)
        } else {
            player.setBase(rest)
        }
        render()
        updateClock()
    }

    // MARK: Hardware key

    /// One "waiting for a touch" line from the system log.
    func keySignal(at now: Date = Date()) {
        // A signal queued just before the setting was switched off.
        guard config.touchHint else { return }
        touchWait.signal(at: now)
        let waiting = touchWait.isWaiting(now: now)
        if waiting != touching {
            touching = waiting
            applyRest()
        }
        // Check again once the signals would have stopped.
        touchEnd?.cancel()
        guard touching, let end = touchWait.endsAt else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.checkTouchEnded() }
        }
        touchEnd = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, end.timeIntervalSinceNow + 0.05), execute: work)
    }

    private func checkTouchEnded() {
        guard touching else { return }
        if touchWait.isWaiting(now: Date()) {
            // Not over yet after all (timers and the wall clock can disagree): look again a bit later.
            let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.checkTouchEnded() } }
            touchEnd = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            return
        }
        touching = false
        applyRest()
        // Touched: a happy check mark (from home just a quick peek). A wait that ran into gpg's timeout
        // most likely wasn't touched, so nothing to celebrate.
        if touchWait.duration < TouchWait.likelyTimeout { react(.touchDone) }
    }

    /// The recap came in (unfolds the paper when it can be seen), or was read elsewhere (menu, setting off).
    func setNews(_ on: Bool) {
        guard on != hasNews else { return }
        hasNews = on
        applyRest()
        if on, restingState == .newspaper { react(.newspaperOpen) }
    }

    /// The setting was switched off mid-wait.
    func clearTouch() {
        touchEnd?.cancel()
        touchWait = TouchWait()
        guard touching else { return }
        touching = false
        applyRest()
    }

    // MARK: Personality

    static let clickWindow: TimeInterval = 3
    static let clicksToAnnoy = 5
    static let shyAfter: TimeInterval = 2
    static let shyCooldown: TimeInterval = 60

    /// Only while typing on the desk, never over another moment, and not too often.
    private var canHaveWorkMoment: Bool {
        !config.isHome && config.desktopReactions && player.state == .working && restingState == .working
            && !reduceMotion && held == nil && !isCardOpen()
    }

    private func glanceAtAgents(_ side: PetState) {
        let now = Date()
        guard canHaveWorkMoment, now.timeIntervalSince(lastAgentGlance) >= WorkMoments.glanceCooldown else { return }
        lastAgentGlance = now
        // Keep a moment from following right on the heels of the look.
        nextWorkMoment = max(nextWorkMoment, now.addingTimeInterval(WorkMoments.glanceCooldown))
        player.play(side)
        render()
        updateClock()
    }

    private func maybeWorkMoment() {
        guard Date() >= nextWorkMoment else { return }
        nextWorkMoment = Date().addingTimeInterval(WorkMoments.delay())
        guard canHaveWorkMoment else { return }
        let moment = WorkMoments.pick(after: lastWorkMoment, roll: Int.random(in: 0..<1000))
        lastWorkMoment = moment
        player.play(moment)
        render()
    }

    /// Mug after a while, headband after long: set by the agent monitor from the longest running turn.
    func setWorkStage(_ stage: WorkStage) {
        guard stage != workStage else { return }
        workStage = stage
        if player.state.isAtDesk { render() }
    }

    private var workProps: WorkProps {
        var props: WorkProps
        switch workStage {
        case .fresh: props = []
        case .mug: props = [.mug]
        case .headband: props = [.mug, .headband]
        }
        if NightDesk.isLate(at: Date()) { props.formUnion([.lamp, .tea]) }
        switch toolKind {
        case .run: props.insert(.toolRun)
        case .search: props.insert(.toolSearch)
        case .read: props.insert(.toolRead)
        case .edit: props.insert(.toolEdit)
        case nil: break
        }
        switch Holiday.on(Date()) {
        case .halloween: props.insert(.pumpkin)
        case .newYear: props.insert(.fir)
        case nil: break
        }
        return props
    }

    /// The tool the latest working Claude session runs, shown in a bubble while typing. It lingers 2.5 s
    /// after the tool ends, so the bubble doesn't blink between back-to-back tools.
    func setTool(_ kind: ToolKind?) {
        toolClear?.cancel()
        toolClear = nil
        guard kind != toolKind else { return }
        if kind == nil {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.toolKind = nil
                    if self.player.state.isAtDesk { self.render() }
                }
            }
            toolClear = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.toolLinger, execute: work)
            return
        }
        toolKind = kind
        if player.state.isAtDesk { render() }
    }

    static let toolLinger: TimeInterval = 2.5
    private var toolClear: DispatchWorkItem?

    /// The oldest wait for the user, or nil: after a minute the pet starts waving now and then.
    func setWaitingSince(_ since: Date?) {
        guard since != waitingSince else { return }
        waitingSince = since
        scheduleWave()
    }

    /// `retry` is set after a wave that couldn't play (the pet was busy): try again a few seconds later.
    private func scheduleWave(retry: Bool = false) {
        waveTimer?.cancel()
        waveTimer = nil
        guard let since = waitingSince else { return }
        let due = retry ? Date().addingTimeInterval(5) : WaitNudge.next(since: since, lastWave: lastWave)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard !self.config.isHome, !self.reduceMotion, [.alert, .question].contains(self.restingState),
                      self.player.state == self.restingState, self.held == nil, !self.isCardOpen() else {
                    // At home there is nothing to wave from: wait for the next interval instead of polling.
                    self.config.isHome ? self.scheduleWave() : self.scheduleWave(retry: true)
                    return
                }
                self.player.play(.wave)
                self.render()
                self.updateClock()
                self.lastWave = Date()
                self.scheduleWave()
            }
        }
        waveTimer = work
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + max(1, due.timeIntervalSinceNow), execute: work)
    }

    /// Rubbing the cursor back and forth over the pet on the desk: eyes shut, hearts.
    private func mouseMoved(x: Double) {
        // Only a pet free to react counts strokes, so a rub it couldn't answer doesn't use up the cooldown.
        guard !config.isHome, config.desktopReactions,
              [.idle, .working, .tired].contains(restingState) || Self.macRests.contains(restingState),
              player.state == restingState, !isCardOpen() else { return petting.reset() }
        guard petting.move(x: x, at: ProcessInfo.processInfo.systemUptime) else { return }
        shyTimer?.cancel()
        shyTimer = nil
        react(.purr)
    }

    /// Redraws at the next 22:00 or 05:00, when the lamp goes on or off.
    private func scheduleNightCheck() {
        nightCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.player.state.isAtDesk { self.render() }
                self.scheduleNightCheck()
            }
        }
        nightCheck = work
        // Wall-clock deadline: it keeps counting while the Mac sleeps (wake and time zone changes also
        // reschedule, see `start`).
        let wait = NightDesk.nextChange(after: Date()).timeIntervalSinceNow + 1
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + max(1, wait), execute: work)
    }

    // MARK: Power and events

    func setMeetingPhase(_ phase: MeetingPlan.Phase) {
        guard phase != meetingPhase else { return }
        meetingPhase = phase
        applyRest()
    }

    /// Battery level or power source changed.
    func setPower(_ reading: PowerReading) {
        let before = power
        power = reading
        applyRest()
        if PowerReading.pluggedIn(from: before, to: reading) { moment(.plugIn) }
        // Once per plug-in: a battery held near full can flicker between 99 and 100.
        if !reading.onAC { fullCelebrated = false }
        if config.macReactions, !fullCelebrated, PowerReading.becameFull(from: before, to: reading) {
            fullCelebrated = true
            moment(.batteryFull)
        }
    }

    // MARK: The Mac

    /// Headphones, music, the mic or camera, heat, power and the network, from `MacMonitor`.
    /// `animate` is false for the first reading and the reset when the setting goes off: no put-on then.
    func setMac(_ state: MacState, animate: Bool) {
        let before = mac
        mac = state
        macDismissed.update(with: state)
        applyRest()
        if before.headphones != state.headphones { followHeadphones(animate: animate) }
    }

    /// What the look shows: headphones settle for 1.5 s first, so a Bluetooth reconnect flapping on and off
    /// doesn't rebuild every sprite each time.
    private var headphonesWorn = false
    private var headphonesChange: DispatchWorkItem?

    private func followHeadphones(animate: Bool) {
        headphonesChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.mac.headphones != self.headphonesWorn else { return }
                let before = MacState(headphones: self.headphonesWorn)
                self.headphonesWorn = self.mac.headphones
                self.sprites.setLook(self.currentLook())
                self.render()
                if animate, let moment = MacState.headphonesMoment(from: before, to: self.mac) { self.moment(moment) }
            }
        }
        headphonesChange = work
        if animate {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        } else {
            work.perform()
        }
    }

    func screenshotTaken() { moment(.screenshot) }

    func themeChanged(dark: Bool) { moment(dark ? .darkMode : .lightMode) }

    /// The "React to the Mac" setting changed: the party hat may come or go.
    func macReactionsChanged() {
        sprites.setLook(currentLook())
        render()
    }

    /// After the somersault for a big task, sometimes a hookah break: once the flip has played, if the pet
    /// is idling on the desk by then and the setting allows it.
    func maybeHookahBreak() {
        guard config.hookah, Int.random(in: 0..<Breaks.afterBigTaskShare) == 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + PetState.flip.totalDuration + 0.8) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.config.hookah, !self.config.isHome, self.config.desktopReactions, !self.reduceMotion,
                      self.player.state == .idle, self.restingState == .idle, !self.isCardOpen() else { return }
                self.player.play(Breaks.hookah(cloudRoll: Int.random(in: 0..<1000)))
                self.render()
                self.updateClock()
            }
        }
    }

    /// A one-off about agents, limits or power: only on the desk, over a calm or working pet, not on top of
    /// another moment. At home these pass quietly.
    @discardableResult
    func moment(_ state: PetState) -> Bool {
        guard !config.isHome, player.state != .dragged,
              [.idle, .working, .tired, .question].contains(restingState)
                || Self.macRests.subtracting([.onAir]).contains(restingState),
              player.state == restingState else { return false }
        return react(state)
    }

    /// Resting states the Mac gives an idle pet; one-offs and petting play over them like over idle, except
    /// one-offs during a call (on air), when it keeps quiet.
    static let macRests: Set<PetState> = [.music, .onAir, .overheated, .lowPower, .offline]

    /// 1.5–4 minutes between fidgets: rare enough to stay a surprise.
    static func fidgetDelay() -> TimeInterval { Double.random(in: 90...240) }

    private func maybeFidget() {
        guard Date() >= nextFidget else { return }
        nextFidget = Date().addingTimeInterval(Self.fidgetDelay())
        // Only a pet idling on the desk fidgets; never over another animation, at home or with Reduce Motion.
        guard !config.isHome, config.desktopReactions, player.state == .idle, restingState == .idle, !reduceMotion,
              held == nil, glance == nil, !isCardOpen() else { return }
        player.play(Breaks.fidget(hookahAllowed: config.hookah, roll: Int.random(in: 0..<1000),
                                  cloudRoll: Int.random(in: 0..<1000), lidMan: config.figure == Figure.lidman.rawValue))
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

    /// Character, skin or accessory changed in settings: redraw everything in the new look.
    func setLook(skin: String, accessory: String, figure: String) {
        config.skin = skin
        config.accessory = accessory
        config.figure = figure
        persist()
        sprites.setLook(currentLook())
        render()
    }

    /// The look for the settings and the day, plus what the Mac puts on the pet: headphones while they're
    /// connected, a party hat on Friday evening.
    static func look(from config: PetConfig, on date: Date = Date(), headphones: Bool = false) -> Look {
        var look = Look.resolve(skin: config.skin, accessory: config.accessory, figure: config.figure, on: date)
        if headphones { look.extras.insert(.headphones) }
        if config.macReactions, PartyTime.isOn(at: date) { look.extras.insert(.partyHat) }
        return look
    }

    private func currentLook() -> Look { Self.look(from: config, headphones: headphonesWorn) }

    /// With "every day new", the look changes at midnight; the party hat goes on at 17:00 on Fridays.
    private var dayChange: DispatchWorkItem?

    private func scheduleDayChange() {
        dayChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sprites.setLook(self.currentLook())
                self.render()
                self.scheduleDayChange()
            }
        }
        dayChange = work
        let calendar = Calendar.autoupdatingCurrent
        let midnight = calendar.nextDate(after: Date(), matching: DateComponents(hour: 0, minute: 0, second: 0),
                                         matchingPolicy: .nextTime) ?? Date().addingTimeInterval(86400)
        let next = [midnight, PartyTime.nextStart(after: Date(), calendar: calendar)].compactMap { $0 }.min() ?? midnight
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + max(1, next.timeIntervalSinceNow + 1), execute: work)
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
        petting.reset()
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

    func setAgents(_ cubes: [AgentCube], codex: [AgentCube] = [], noticing: Bool = true) {
        guard cubes != agents || codex != codexAgents else { return }
        // Something changed among the blocks: look over at that side (Codex left, Claude right).
        let side: PetState? = !noticing ? nil
            : WorkMoments.noticeable(old: codexAgents, new: codex) ? .glanceLeft
            : WorkMoments.noticeable(old: agents, new: cubes) ? .glanceRight : nil
        agents = cubes
        codexAgents = codex
        if let side { glanceAtAgents(side) }
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
        view.onMouseMove = { [weak self] x in self?.mouseMoved(x: x) }
        view.onClick = { [weak self] in
            guard let self else { return }
            if restingState == .meetingSoon || restingState == .meetingNow, !config.isHome {
                // "Got it": the headset comes off, a little hop, and the card stays shut this time.
                onDismissMeeting?()
                react(.hop)
                return
            }
            if restingState == .newspaper, !config.isHome {
                hasNews = false
                applyRest()
                react(.hop)
                onOpenNews?()
                return
            }
            if Self.macRests.contains(restingState), !config.isHome {
                // "Got it": back to idling (or the next thing in line) until this one ends.
                macDismissed.dismiss(restingState)
                applyRest()
                react(.hop)
                return
            }
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
        view.onDragEnded = { [weak self] velocity, shaken in self?.endDrag(velocity: velocity, shaken: shaken) }
        view.onContextMenu = { [weak self] event in
            guard let self, let menu = contextMenu else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        }
    }

    private func endDrag(velocity: PetPoint, shaken: Bool = false) {
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
        let outcome = Placement.throwOutcome(from: PetPoint(panel.frame.origin), velocity: velocity,
                                             size: size, screens: screens())
        player.play(restingState)
        // A hard throw tumbles through the air, then lands against the side it hit, or on the floor;
        // a shaken pet lands dizzy.
        let landing: PetState = shaken ? .dizzy
            : outcome.wall == .right ? .splatRight : outcome.wall == .left ? .splatLeft : .drop
        let hard = Placement.isHardThrow(velocity)
        if !reduceMotion { player.play(hard ? .thrown : landing) }
        render()
        updateClock()
        animateMove(to: outcome.destination, landing: hard && !reduceMotion ? landing : nil)
    }

    /// Eases the window to a point; on the desk the final position is remembered.
    /// `landing`: a one-shot to play once the window arrives (the end of a throw).
    private func animateMove(to destination: PetPoint, persistDesk: Bool = true, landing: PetState? = nil) {
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
                if let landing, self.player.state != .dragged, !self.config.isHome {
                    self.player.play(landing)
                    self.render()
                    self.updateClock()
                }
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

    var isOnScreen: Bool {
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
                nextWorkMoment = Date().addingTimeInterval(WorkMoments.delay())
            }
            lastTick = now
        }
        let animatedCubes = !(agents.isEmpty && codexAgents.isEmpty) && !config.isHome && !reduceMotion
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
        if !(agents.isEmpty && codexAgents.isEmpty), !config.isHome, !reduceMotion { renderAgents() }
        maybeFidget()
        maybeWorkMoment()
        updateClock(fromTick: true)
    }

    private func render() {
        // At home the top of the body is inside the hole, so a drained band would only show as a stray stripe.
        let state = held?.state ?? player.state
        let index = held?.frame ?? (reduceMotion ? (MotionPolicy.stillFrame(for: state) ?? player.frame) : player.frame)
        let frame = sprites.frame(state, index, drain: config.isHome ? 0 : drain,
                                  gaze: config.isHome ? nil : currentGaze, props: workProps)
        view.show(frame.image, canvas: frame.canvas)
    }

    /// The stack animates on a shared 10 Hz beat so it doesn't speed up or slow down with the pet's state.
    private func renderAgents() {
        // At home the stack would sit in the menu bar; the menu-bar counter covers it there.
        // Reduce Motion: the cubes keep their colors but stop spinning and bouncing.
        let tick = reduceMotion ? 0 : Int(CACurrentMediaTime() * 10)
        let canvas = AgentStack.canvas(for: config.isHome ? [] : agents, left: config.isHome ? [] : codexAgents, tick: tick)
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

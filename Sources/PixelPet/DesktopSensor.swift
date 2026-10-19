import AppKit
import CoreGraphics
import PetCore

/// Watches the desktop: cursor (eyes follow it), user idle time (sleep), app switches (a glance at the
/// new window), fullscreen apps (dim) and system wake (a greeting). Needs no extra permissions:
/// mouse monitors, the idle counter and window bounds are available to any app; window titles are never read.
@MainActor
final class DesktopSensor {
    static let mouseInterval: TimeInterval = 0.1

    private let pet: PetController
    private var mouseMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var idleTimer: Timer?
    private var lastMouseUpdate: TimeInterval = 0
    private var glances = ReactionThrottle(interval: 10)

    init(pet: PetController) {
        self.pet = pet
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let pid = app?.processIdentifier
                let regular = app?.activationPolicy == .regular
                MainActor.assumeIsolated { self?.appActivated(pid, regular: regular) }
            },
            workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.spaceChanged() }
            },
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemWoke() }
            },
        ]
        // Idle time only matters at minute scale; a slow, tolerant timer keeps wake-ups rare.
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIdle() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
        reconfigure()
    }

    /// Mouse tracking runs only while it can matter: reactions on, pet visible and on the desk.
    func reconfigure() {
        let active = pet.config.desktopReactions && !pet.isHidden && !pet.isHome
        if active, mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { @Sendable [weak self] event in
                let time = event.timestamp
                MainActor.assumeIsolated { self?.mouseMoved(at: time) }
            }
        } else if !active, let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if active {
            checkFullscreen(NSWorkspace.shared.frontmostApplication?.processIdentifier)
        } else {
            pet.resetDesktopReactions()
        }
    }

    private func mouseMoved(at time: TimeInterval) {
        // Throttle first: these events arrive hundreds of times a second.
        guard time - lastMouseUpdate > Self.mouseInterval else { return }
        lastMouseUpdate = time
        // Coming back to the desk wakes the pet at once rather than at the next idle check.
        if pet.restingState == .sleep { pet.checkUserIdle() }
        pet.setCursorGaze(Gaze.toward(PetPoint(NSEvent.mouseLocation), from: pet.center))
    }

    private func checkIdle() {
        guard pet.config.sleepAfterMinutes > 0, !pet.isHidden else { return }
        pet.checkUserIdle()
    }

    private func systemWoke() {
        let wasAsleep = pet.restingState == .sleep
        pet.checkUserIdle()
        // Waking from sleep already hops; otherwise say hello after the Mac wakes.
        if !wasAsleep, pet.config.desktopReactions { pet.greet() }
    }

    private func spaceChanged() {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        checkFullscreen(pid)
        // Space transitions report the old windows for a moment; look again once it has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            MainActor.assumeIsolated { self?.checkFullscreen(NSWorkspace.shared.frontmostApplication?.processIdentifier) }
        }
    }

    private func appActivated(_ pid: pid_t?, regular: Bool) {
        guard let pid, pid != getpid() else { return }
        checkFullscreen(pid)
        // System UI (Spotlight, login window, agents) isn't something the user "switched to".
        guard regular, pet.config.desktopReactions, !pet.isHidden, !pet.isHome,
              let window = frontWindow(of: pid), glances.take(at: Date()) else { return }
        pet.glance(at: PetPoint(x: window.x + window.width / 2, y: window.y + window.height / 2))
    }

    private func checkFullscreen(_ pid: pid_t?) {
        guard pet.config.desktopReactions, !pet.isHidden, let screen = pet.screenFrame else {
            pet.setDimmed(false)
            return
        }
        // Our own cards in front don't change what's behind them.
        guard let pid, pid != getpid() else { return }
        pet.setDimmed(frontWindow(of: pid).map { Fullscreen.covers(window: $0, screen: PetRect(screen)) } ?? false)
    }

    /// The app's frontmost normal, opaque window, in AppKit coordinates.
    private func frontWindow(of pid: pid_t) -> PetRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        for info in list where (info[kCGWindowOwnerPID as String] as? pid_t) == pid
            && (info[kCGWindowLayer as String] as? Int) == 0
            && ((info[kCGWindowAlpha as String] as? Double) ?? 1) >= 0.9 {
            guard let bounds = info[kCGWindowBounds as String] as? [String: Double],
                  let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"],
                  w > 50, h > 50 else { continue }
            return Fullscreen.appKitRect(cg: PetRect(x: x, y: y, width: w, height: h), primaryHeight: primaryHeight)
        }
        return nil
    }
}

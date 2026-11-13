import AppKit
import Carbon
import CoreGraphics
import DiskArbitration
import PetCore

/// What the user does on the Mac, for an idle pet to notice: Spaces switching, typing, the kind of app in
/// front, apps opening and quitting, USB sticks, displays and the keyboard layout. Needs no permission and
/// reads no content: workspace notifications, the time since the last key press (never the keys), the front
/// app's category, volume flags, the screen count and the input source's language. The key timing is read only
/// while the pet is on the desk (not hidden or at home); what it shows waits for no agent to be working.
@MainActor
final class ActivitySensor {
    private let pet: PetController
    private var running = false
    private var observers: [NSObjectProtocol] = []
    private var distributed: [NSObjectProtocol] = []
    private var typingTimer: Timer?
    private var focusTimer: Timer?

    private var focus = AppFocus()
    private var typing = TypingDetector()
    private var spaces = SpaceSwitches()
    private var launches = ReactionThrottle(interval: ActivityTiming.launchEvery)
    private var quits = ReactionThrottle(interval: ActivityTiming.quitEvery)
    private var layouts = ReactionThrottle(interval: ActivityTiming.layoutEvery)
    private var volumes = ReactionThrottle(interval: ActivityTiming.volumeEvery)
    private var displayCheck: DispatchWorkItem?
    /// Tells a disk image from a real device.
    private let disks = DASessionCreate(kCFAllocatorDefault)
    /// Launches and new displays right after start or wake are the login burst and screens coming back.
    private var quietUntil = Date()
    private var screenCount = 0
    private var layoutCode: String?
    /// Removable volumes mounted now, so their ejection is known (an unmounted volume can't be asked).
    private var sticks: Set<String> = []

    init(pet: PetController) {
        self.pet = pet
    }

    func setRunning(_ on: Bool) {
        guard on != running else { return }
        running = on
        on ? start() : stop()
    }

    private func start() {
        quietUntil = Date().addingTimeInterval(ActivityTiming.settleAfterStart)
        screenCount = NSScreen.screens.count
        layoutCode = Self.currentLayout()
        sticks = Set((FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? [])
            .filter(isStick).map(\.path))
        let workspace = NSWorkspace.shared.notificationCenter
        func on(_ name: Notification.Name, _ center: NotificationCenter = workspace,
                _ handler: @escaping @MainActor (Notification) -> Void) -> NSObjectProtocol {
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                // Only the parts handlers need cross over: the note itself isn't Sendable.
                nonisolated(unsafe) let note = note
                MainActor.assumeIsolated { handler(note) }
            }
        }
        observers = [
            on(NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in self?.spaceChanged() },
            on(NSWorkspace.didActivateApplicationNotification) { [weak self] note in self?.appActivated(Self.app(note)) },
            on(NSWorkspace.didLaunchApplicationNotification) { [weak self] note in self?.appLaunched(Self.app(note)) },
            on(NSWorkspace.didTerminateApplicationNotification) { [weak self] note in self?.appQuit(Self.app(note)) },
            on(NSWorkspace.didWakeNotification) { [weak self] _ in self?.woke() },
            // Screens waking and the user coming back reconnect displays too: not new ones.
            on(NSWorkspace.screensDidWakeNotification) { [weak self] _ in self?.woke() },
            on(NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] _ in self?.woke() },
            on(NSWorkspace.didMountNotification) { [weak self] note in self?.mounted(Self.volume(note)) },
            on(NSWorkspace.didUnmountNotification) { [weak self] note in self?.unmounted(Self.volume(note)) },
            on(NSApplication.didChangeScreenParametersNotification, .default) { [weak self] _ in self?.screensChanged() },
        ]
        distributed = [
            on(Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), DistributedNotificationCenter.default()) {
                [weak self] _ in self?.layoutChanged()
            },
        ]
        appActivated(NSWorkspace.shared.frontmostApplication)
        // Once a second: the time since the last key press, nothing else.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkTyping() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        typingTimer = timer
    }

    private func stop() {
        for o in observers { NSWorkspace.shared.notificationCenter.removeObserver(o); NotificationCenter.default.removeObserver(o) }
        for o in distributed { DistributedNotificationCenter.default().removeObserver(o) }
        observers = []
        distributed = []
        typingTimer?.invalidate()
        typingTimer = nil
        focusTimer?.invalidate()
        focusTimer = nil
        displayCheck?.cancel()
        displayCheck = nil
        focus = AppFocus()
        typing.reset()
        pet.setActivity(ActivityState())
    }

    // MARK: State: the app in front, typing

    private func publish() {
        pet.setActivity(ActivityState(app: focus.current(at: Date()), typing: typing.isTyping))
    }

    private func appActivated(_ app: NSRunningApplication?) {
        // Spotlight, Raycast and menu-bar apps coming forward for a moment don't change what the user is in.
        guard let app, app.processIdentifier != getpid(), app.activationPolicy == .regular else { return }
        let kind = AppKind.of(bundleID: app.bundleIdentifier, category: app.bundleURL.flatMap(Self.category))
        let now = Date()
        focus.update(kind, at: now)
        publish()
        // The kind counts once it has settled: look again then.
        focusTimer?.invalidate()
        focusTimer = nil
        if let due = focus.nextChange(after: now) {
            let timer = Timer(fire: due.addingTimeInterval(0.5), interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.publish() }
            }
            RunLoop.main.add(timer, forMode: .common)
            focusTimer = timer
        }
    }

    private func checkTyping() {
        let before = typing.isTyping
        if pet.isHidden || pet.isHome {
            // Nothing to show it on: don't read the keys' timing at all.
            typing.reset()
        } else {
            let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
            typing.update(secondsSinceKey: seconds, at: Date())
        }
        if typing.isTyping != before { publish() }
    }

    // MARK: One-offs

    private func spaceChanged() {
        // Waking and displays coming back switch Spaces too.
        let now = Date()
        guard now >= quietUntil, let state = spaces.record(at: now) else { return }
        pet.activityMoment(state)
    }

    /// Plays a one-off if its throttle allows, and uses the throttle up only when it played.
    private func play(_ state: PetState, _ throttle: inout ReactionThrottle) {
        let now = Date()
        guard throttle.allows(at: now), pet.activityMoment(state) else { return }
        throttle.mark(at: now)
    }

    private func appLaunched(_ app: NSRunningApplication?) {
        guard let app, app.activationPolicy == .regular, app.processIdentifier != getpid(), Date() >= quietUntil
        else { return }
        play(.appLaunched, &launches)
    }

    private func appQuit(_ app: NSRunningApplication?) {
        guard let app, app.activationPolicy == .regular, ActivityTiming.quitCounts(launchedAt: app.launchDate, at: Date())
        else { return }
        play(.appQuit, &quits)
    }

    private func woke() {
        quietUntil = Date().addingTimeInterval(ActivityTiming.settleAfterStart)
        typing.reset()
        publish()
    }

    private func mounted(_ url: URL?) {
        guard let url, isStick(url) else { return }
        sticks.insert(url.path)
        play(.usbIn, &volumes)
    }

    private func unmounted(_ url: URL?) {
        guard let url, sticks.remove(url.path) != nil else { return }
        play(.usbOut, &volumes)
    }

    /// More screens than before, still there a moment later and outside the quiet minute: a new display.
    private func screensChanged() {
        let before = screenCount
        screenCount = NSScreen.screens.count
        displayCheck?.cancel()
        guard screenCount > before else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, NSScreen.screens.count > before, Date() >= self.quietUntil else { return }
                self.pet.activityMoment(.newDisplay)
            }
        }
        displayCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ActivityTiming.displaySettle, execute: work)
    }

    private func layoutChanged() {
        guard let code = Self.currentLayout(), code != layoutCode else { return }
        let old = layoutCode
        layoutCode = code
        guard let old, layouts.allows(at: Date()), pet.layoutChanged(from: old, to: code) else { return }
        layouts.mark(at: Date())
    }

    // MARK: Reading

    private static func app(_ note: Notification) -> NSRunningApplication? {
        note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    private static func volume(_ note: Notification) -> URL? {
        note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
    }

    /// A stick, a card or an external drive: not an internal disk, a network share or a disk image.
    private func isStick(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey,
                                                       .volumeIsInternalKey, .volumeIsLocalKey])
        return RemovableVolume.counts(removable: values?.volumeIsRemovable, ejectable: values?.volumeIsEjectable,
                                      isInternal: values?.volumeIsInternal, isLocal: values?.volumeIsLocal,
                                      deviceProtocol: deviceProtocol(url))
    }

    /// DiskArbitration's device protocol ("USB", "SD", "Virtual Interface" for a disk image).
    private func deviceProtocol(_ url: URL) -> String? {
        guard let disks, let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, disks, url as CFURL),
              let description = DADiskCopyDescription(disk) as? [String: Any] else { return nil }
        return description[kDADiskDescriptionDeviceProtocolKey as String] as? String
    }

    /// The app's `LSApplicationCategoryType`, from its Info.plist.
    private static func category(_ url: URL) -> String? {
        Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
    }

    /// The selected keyboard layout's language as two letters ("EN", "RU").
    private static func currentLayout() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return nil }
        let languages = Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as? [String] ?? []
        return InputSourceCode.code(languages: languages)
    }
}

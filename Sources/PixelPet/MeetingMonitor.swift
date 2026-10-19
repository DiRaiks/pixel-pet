import AppKit
import EventKit
import PetCore

/// Upcoming calls from the Mac's calendars (EventKit), only while "remind me about calls" is on. Reads the
/// next day of events again whenever the calendar database changes and every 15 minutes, and wakes up at
/// each phase boundary (5 minutes before, 1 minute before, 1 minute after a call starts).
/// Skips all-day, cancelled and declined events, and anything without a call link. Titles stay in memory.
@MainActor
final class MeetingMonitor {
    /// `limited`: write-only access, or calendars restricted by whoever manages the Mac.
    enum Access { case notAsked, granted, denied, limited }

    static var access: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notAsked
        case .writeOnly, .restricted: .limited
        default: .denied
        }
    }

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var wake: DispatchWorkItem?
    private var meetings: [Meeting] = []
    private var running = false
    private var lastAccess = MeetingMonitor.access
    private var pendingReload: DispatchWorkItem?
    var onPhase: ((MeetingPlan.Phase) -> Void)?
    var onUpcoming: ((Meeting?) -> Void)?
    /// After the user answered the permission prompt.
    var onAccessChange: (() -> Void)?

    /// Calendars the Mac can see (Google ones only if the account is added in System Settings), birthdays aside.
    var calendarCount: Int {
        Self.access == .granted ? store.calendars(for: .event).filter { $0.type != .birthday }.count : 0
    }

    /// `askForAccess`: from the settings switch only; at launch the pet never pops a prompt by itself.
    func start(askForAccess: Bool) {
        guard !running else { return }
        running = true
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            // Syncing calendars send these in bursts: read once they settle.
            MainActor.assumeIsolated { self?.reloadSoon() }
        }
        if askForAccess { requestAccess() }
        reload()
    }

    /// Shows the system prompt (only possible while access was never decided; after a rebuild of an
    /// ad-hoc signed app macOS forgets the answer, so this is also how to get it back).
    func requestAccess() {
        guard running, Self.access == .notAsked else { return }
        // A menu-bar app's prompt can open behind other windows; come forward first.
        NSApp.activate()
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.onAccessChange?()
                    self?.reload()
                }
            }
        }
    }

    func stop() {
        running = false
        pendingReload?.cancel()
        pendingReload = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        wake?.cancel()
        wake = nil
        meetings = []
        onPhase?(.none)
        onUpcoming?(nil)
    }

    private func reloadSoon() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.reload() } }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// Also called when the settings open, so a permission granted or revoked meanwhile shows at once.
    func reload() {
        guard running else { return }
        let access = Self.access
        if access != lastAccess {
            lastAccess = access
            onAccessChange?()
        }
        meetings = access == .granted ? fetch() : []
        update()
    }

    private func fetch() -> [Meeting] {
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: now.addingTimeInterval(86400),
                                                 calendars: nil)
        return store.events(matching: predicate).compactMap { event in
            guard !event.isAllDay, event.status != .canceled,
                  event.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined else { return nil }
            return Meeting(title: event.title ?? "", start: event.startDate, end: event.endDate,
                           hasCall: MeetingLink.isCall([event.url?.absoluteString, event.location, event.notes]))
        }
    }

    private func update() {
        let now = Date()
        onPhase?(MeetingPlan.phase(for: meetings, now: now))
        onUpcoming?(MeetingPlan.upcoming(meetings, now: now))
        wake?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.reload() } }
        wake = work
        // The next boundary, or a fresh look in 15 minutes; on the wall clock, so sleep doesn't delay it.
        let next = [MeetingPlan.nextChange(for: meetings, now: now), now.addingTimeInterval(15 * 60)].compactMap { $0 }.min()!
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + max(1, next.timeIntervalSinceNow + 0.5), execute: work)
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

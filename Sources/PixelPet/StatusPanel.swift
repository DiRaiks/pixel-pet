import AppKit
import PetCore
import SwiftUI

/// Card next to the pet (status, translation). A borderless panel rather than NSPopover:
/// glass popovers take their tint from the wallpaper, which fights a solid, readable card.
@MainActor
final class CardPanel<Content: View> {
    private let panel: NSPanel
    /// Called when the card opens, e.g. to refresh what it shows.
    var onShow: (() -> Void)?
    private var monitors: [Any] = []
    private weak var anchor: NSView?
    /// Bumped on every show/close so a fade-out finishing late can't hide a card that was just reopened.
    private var generation = 0
    private var isClosing = false
    private var clock: Timer?
    private var resignObserver: NSObjectProtocol?
    /// Every `tickInterval` while open, for text that depends on the time.
    var onTick: (() -> Void)?
    var tickInterval: TimeInterval = 30
    var onClose: (() -> Void)?

    /// `keyboard: true` lets the card take typing (like Spotlight) without activating the app.
    /// Cards that hold a decision (a permission request) stay open through clicks elsewhere.
    private let staysOpen: Bool

    init(content: Content, keyboard: Bool = false, staysOpen: Bool = false) {
        self.staysOpen = staysOpen
        let panel = CardWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.acceptsKey = keyboard
        self.panel = panel
        if keyboard, Self.closesOnOutsideClick {
            // A typing card closes when the user moves to another app (⌘Tab, Mission Control, a click).
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
        }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: content)
        panel.onCancel = { [weak self] in self?.close() }
    }

    var isShown: Bool { panel.isVisible && !isClosing }

    func toggle(from view: NSView) {
        isShown ? close() : show(from: view)
    }

    /// `animated: false` for cards opened from a hotkey: those must appear at once.
    func show(from view: NSView, animated: Bool = true) {
        guard let petWindow = view.window else { return }
        generation += 1
        isClosing = false
        anchor = view
        onShow?()
        // Content set just before showing isn't laid out yet: measure it laid out, or the card is placed
        // for a stub and then grows over the pet.
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 340, height: 200))
        let origin = position(for: panel.frame.size, near: petWindow.frame, on: petWindow.screen ?? NSScreen.main)
        // Enter: fade in while settling 6 pt toward the pet, ease-out, under 200 ms.
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let lift: CGFloat = origin.y >= petWindow.frame.maxY ? 6 : -6
            panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y + lift))
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
                panel.animator().alphaValue = 1
                // The window animator ignores setFrameOrigin (macOS 26+); the whole frame does animate.
                panel.animator().setFrame(NSRect(origin: origin, size: panel.frame.size), display: true)
            }
        } else {
            panel.setFrameOrigin(origin)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        if panel.canBecomeKey { panel.makeKey() }
        watchOutsideClicks()
        // "Resets in" and "seen N min ago" keep moving while the card is open (only cards that need it).
        clock?.invalidate()
        guard onTick != nil else { return }
        let clock = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick?() }
        }
        clock.tolerance = tickInterval / 6
        RunLoop.main.add(clock, forMode: .common)
        self.clock = clock
    }

    func close() {
        guard isShown else { return }
        isClosing = true
        generation += 1
        let closing = generation
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        clock?.invalidate()
        clock = nil
        onClose?()
        // Exit faster than enter (and not at all with Reduce Motion).
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == closing else { return }
                self.isClosing = false
                self.panel.orderOut(nil)
            }
        })
    }

    /// Re-fits the card after its content changed, keeping the edge next to the pet in place, and then
    /// keeping the whole card on screen (a long result grows it past the edge otherwise).
    func refit() {
        guard isShown, let petWindow = anchor?.window, let size = panel.contentView?.fittingSize,
              size != panel.frame.size else { return }
        let pet = petWindow.frame
        var frame = panel.frame
        let above = frame.minY >= pet.maxY
        if !above { frame.origin.y = frame.maxY - size.height }
        frame.size = size
        if let area = (petWindow.screen ?? NSScreen.main)?.visibleFrame {
            frame.size.height = min(frame.height, area.height)
            if frame.maxY > area.maxY { frame.origin.y = area.maxY - frame.height }
            if frame.minY < area.minY { frame.origin.y = area.minY }
        }
        panel.setFrame(frame, display: true)
    }

    /// Above the pet when there's room, otherwise below; centered on it and kept on screen.
    private func position(for size: NSSize, near pet: NSRect, on screen: NSScreen?) -> NSPoint {
        let area = screen?.visibleFrame ?? pet.insetBy(dx: -1000, dy: -1000)
        let gap: CGFloat = 4
        var y = pet.maxY + gap
        if y + size.height > area.maxY { y = pet.minY - gap - size.height }
        let x = min(max(pet.midX - size.width / 2, area.minX + 8), area.maxX - size.width - 8)
        return NSPoint(x: x, y: max(y, area.minY))
    }

    /// Debug aid (`--keep-cards`): scripted checks shouldn't be cut short by clicks elsewhere.
    static var closesOnOutsideClick: Bool { !CommandLine.arguments.contains("--keep-cards") }

    /// Clicks in other apps close the card. (No Esc: a global monitor can't consume it, so the frontmost
    /// app would get it too, and it would need Accessibility just for that.)
    private func watchOutsideClicks() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        guard Self.closesOnOutsideClick, !staysOpen else { return }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        // Clicks inside our own windows don't close it: the pet toggles cards itself, and system sheets
        // hosted by the card (Translation's language download) must stay usable.
        monitors = [global].compactMap { $0 }
    }
}

struct StatusPanelView: View {
    let model: StatusModel

    private func meetingLine(_ meeting: Meeting) -> String {
        let minutes = Int((meeting.start.timeIntervalSince(model.now) / 60).rounded(.up))
        let when = minutes <= 0 ? L("Call starting", "Звонок начинается") : L("Call in \(minutes) min", "Звонок через \(minutes) мин")
        return meeting.title.isEmpty ? when : "\(when): \(meeting.title)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let meeting = model.nextMeeting {
                Label {
                    Text(meetingLine(meeting)).font(.callout).lineLimit(1)
                } icon: {
                    Image(systemName: "alarm")
                }
                Divider()
            }
            LimitsSection(model: model)
            Divider()
            SessionsSection(model: model)
        }
        .padding(16)
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}

private struct LimitsSection: View {
    let model: StatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Limits", "Лимиты")).font(.headline)
                Spacer()
                // With Codex on, each group says how fresh it is instead.
                if !model.codexEnabled, let observed = model.limits?.observedAt {
                    Text(Format.ago(observed, now: model.now)).font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    model.onRefreshLimits?()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isProbing)
                .help(L("Refresh limits", "Обновить лимиты"))
            }
            if model.codexEnabled {
                LimitGroup(title: "Claude", limits: model.limits, probing: model.isProbing, now: model.now)
                LimitGroup(title: "Codex", limits: model.codexLimits, probing: false, now: model.now)
            } else {
                LimitGroup(title: nil, limits: model.limits, probing: model.isProbing, now: model.now)
            }
        }
    }
}

private struct LimitGroup: View {
    let title: String?
    let limits: UsageLimits?
    let probing: Bool
    let now: Date

    var body: some View {
        let current = limits?.current(at: now)
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                HStack {
                    Text(title).font(.subheadline.weight(.medium))
                    Spacer()
                    if let observed = limits?.observedAt {
                        Text(Format.ago(observed, now: now)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let current, !current.isEmpty {
                LimitRow(title: L("5h", "5 ч"), window: current.fiveHour, low: UsageLimits.fiveHourLow, now: now)
                LimitRow(title: L("7d", "7 дн"), window: current.sevenDay, low: UsageLimits.sevenDayLow, now: now)
            } else {
                Text(probing ? L("Checking limits…", "Узнаю лимиты…") : L("Limits not known yet", "Лимиты пока неизвестны"))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct LimitRow: View {
    let title: String
    let window: LimitWindow?
    let low: Double
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.callout).frame(width: 34, alignment: .leading)
            if let window {
                ProgressView(value: min(window.usedPercent, 100), total: 100)
                    // The pet's own purple; the system accent turns gray while the app is inactive, which it always is.
                    .tint(window.usedPercent >= low ? Color(red: 0.89, green: 0.29, blue: 0.29) : Color(red: 0.5, green: 0.47, blue: 0.87))
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.callout.monospacedDigit()).frame(width: 38, alignment: .trailing)
                Text(Format.duration(window.resetsAt.timeIntervalSince(now)))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 84, alignment: .trailing)
                    .help(L("Resets in \(Format.duration(window.resetsAt.timeIntervalSince(now)))",
                             "Сброс через \(Format.duration(window.resetsAt.timeIntervalSince(now)))"))
            } else {
                Text(L("no data", "нет данных")).font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

private struct SessionsSection: View {
    let model: StatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Sessions", "Сессии")).font(.headline)
            if model.sessions.isEmpty && model.codexSessions.isEmpty {
                Text(emptyText).font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(model.sessions, id: \.id) { SessionRow(session: $0, source: nil, now: model.now) }
                ForEach(model.codexSessions, id: \.id) { SessionRow(session: $0, source: "Codex", now: model.now) }
            }
        }
    }
}

private extension SessionsSection {
    var emptyText: String {
        let claude = model.hooksConnected ? "Claude Code" : nil
        let codex = model.codexEnabled ? "Codex" : nil
        switch (claude, codex) {
        case (nil, nil): return L("Connect the cube to Claude Code from the menu bar", "Подключите кубика к Claude Code в меню-баре")
        case (nil, _): return L("No Codex sessions right now. Claude Code can be connected from the menu bar",
                                "Сейчас нет сессий Codex. Claude Code можно подключить в меню-баре")
        default:
            let names = [claude, codex].compactMap { $0 }
            return L("No \(names.joined(separator: " or ")) sessions right now",
                     "Сейчас нет сессий " + names.joined(separator: " и "))
        }
    }
}

private struct SessionRow: View {
    let session: AgentSession
    /// Shown before the status for agents other than Claude Code.
    let source: String?
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.project ?? String(session.id.prefix(8))).font(.callout).lineLimit(1)
                    Spacer(minLength: 8)
                    if let meta { Text(meta).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1) }
                }
                HStack(alignment: .firstTextBaseline) {
                    activity.font(.caption).lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(active ? .primary : .secondary)
                    Spacer(minLength: 8)
                    if let since = timerStart {
                        Text(Format.clock(now.timeIntervalSince(since)))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                if let turn { Text(turn).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }

    private var active: Bool { session.status == .working || session.status == .waiting }

    private var color: Color {
        switch session.status {
        case .working: Color(red: 0.11, green: 0.62, blue: 0.46)
        case .waiting: Color(red: 0.94, green: 0.62, blue: 0.15)
        case .failed: Color(red: 0.89, green: 0.29, blue: 0.29)
        case .idle: Color.secondary.opacity(0.5)
        }
    }

    /// What it's doing now: the step, or what it waits for.
    private var activity: Text {
        let prefix = source.map { Text("\($0) · ") } ?? Text("")
        switch session.status {
        case .working:
            guard source == nil else { return prefix + Text(L("working", "работает")) }
            return session.step.map(Format.step) ?? Text(L("Thinking", "Думает"))
        case .waiting where session.waitingFor == .permission:
            let what = session.step.flatMap(\.object) ?? session.currentTool.map(Format.tool)
            let waiting = Text(L("Waiting for permission", "Ждёт разрешения"))
            return prefix + (what.map { waiting + Text(": ") + Format.code($0) } ?? waiting)
        case .waiting: return prefix + Text(L("Waiting for an answer", "Ждёт ответа"))
        case .failed: return prefix + Text(L("Error", "Ошибка"))
        case .idle:
            guard let finished = session.finishedAt else { return prefix + Text(L("Idle", "Простаивает")) }
            let ago = Format.ago(finished, now: now)
            let done = L("Done \(ago)", "Закончил \(ago)")
            guard let took = session.lastTurn, took >= 60 else { return prefix + Text(done) }
            return prefix + Text(done + L(", took \(Format.duration(took))", ", работал \(Format.duration(took))"))
        }
    }

    /// The step's (or the wait's) own clock.
    private var timerStart: Date? {
        switch session.status {
        case .working: source == nil ? session.stepSince : session.workingSince
        case .waiting: session.waitingSince
        default: nil
        }
    }

    /// The whole turn: how long and how many steps.
    private var turn: String? {
        guard active, source == nil, let start = session.turnStartedAt else { return nil }
        let long = Format.duration(now.timeIntervalSince(start))
        let time = session.status == .working ? L("working \(long)", "работает \(long)") : L("worked \(long)", "работал \(long)")
        return session.steps > 0 ? time + " · " + Format.steps(session.steps) : time
    }

    private var meta: String? {
        let parts = [AgentSession.shortModel(session.model),
                     session.contextPercent.map { "ctx \(Int($0.rounded()))%" },
                     session.subagents.isEmpty ? nil : L("+\(session.subagents.count) sub.", "+\(session.subagents.count) саб.")]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

@MainActor
enum Format {
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        return seconds < 60 ? L("just now", "только что") : L("\(duration(seconds)) ago", "\(duration(seconds)) назад")
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        if minutes < 1 { return L("<1 min", "<1 мин") }
        if minutes < 60 { return L("\(minutes) min", "\(minutes) мин") }
        let hours = minutes / 60
        if hours < 24 {
            return minutes % 60 == 0 ? L("\(hours) h", "\(hours) ч") : L("\(hours) h \(minutes % 60) min", "\(hours) ч \(minutes % 60) мин")
        }
        return L("\(hours / 24) d \(hours % 24) h", "\(hours / 24) д \(hours % 24) ч")
    }

    /// "mcp__terminal__run_in_terminal" -> "run_in_terminal".
    /// m:ss, or h:mm:ss past an hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return s < 3600 ? String(format: "%d:%02d", s / 60, s % 60) : String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }

    static func steps(_ n: Int) -> String {
        L(n == 1 ? "1 step" : "\(n) steps", "\(n) \(ru(n, "шаг", "шага", "шагов"))")
    }

    /// The Russian word for `n`: 1 (and 21, 31…), 2–4 (and 22–24…), or the rest (with 11–14).
    static func ru(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        if n % 10 == 1 && n % 100 != 11 { return one }
        return (2...4).contains(n % 10) && !(12...14).contains(n % 100) ? few : many
    }

    static func code(_ text: String) -> Text {
        Text(text).font(.caption.monospaced())
    }

    /// "Runs `npm test`", "Edits `App.swift`", "terminal: run_in_terminal".
    static func step(_ step: AgentStep) -> Text {
        let verb: String = switch step.action {
        case .run: L("Runs", "Выполняет")
        case .read: L("Reads", "Читает")
        case .edit: L("Edits", "Правит")
        case .write: L("Writes", "Пишет")
        case .search: L("Searches", "Ищет")
        case .findFiles: L("Finds files", "Ищет файлы")
        case .fetch: L("Opens", "Открывает")
        case .webSearch: L("Searches the web", "Ищет в сети")
        case .subagent: L("Subagent", "Сабагент")
        case .tool(let name): PermissionView.toolName(name)
        }
        guard let object = step.object else { return Text(verb) }
        return Text(verb + (step.action == .subagent ? ": " : " ")) + code(object)
    }

    static func tool(_ name: String) -> String {
        name.hasPrefix("mcp__") ? String(name.split(separator: "__").last ?? Substring(name)) : name
    }
}

/// Borderless windows can't become key unless told; only cards with a text field ask for it.
final class CardWindow: NSPanel {
    var acceptsKey = false
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }

    /// Esc, wherever focus is inside the card (even with the text field disabled while streaming).
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// The status card: limits and sessions.
typealias StatusPanel = CardPanel<StatusPanelView>

extension CardPanel where Content == StatusPanelView {
    convenience init(model: StatusModel) {
        self.init(content: StatusPanelView(model: model))
        onShow = { model.now = Date() }
        onTick = { model.now = Date() }
        // The step timers count seconds.
        tickInterval = 1
    }
}

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
    /// Every 30 s while open, for text that depends on the time.
    var onTick: (() -> Void)?
    var onClose: (() -> Void)?

    /// `keyboard: true` lets the card take typing (like Spotlight) without activating the app.
    init(content: Content, keyboard: Bool = false) {
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
        let clock = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick?() }
        }
        clock.tolerance = 5
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

    /// Re-fits the card after its content changed, keeping the edge next to the pet in place.
    func refit() {
        guard isShown, let pet = anchor?.window?.frame, let size = panel.contentView?.fittingSize,
              size != panel.frame.size else { return }
        var frame = panel.frame
        let above = frame.minY >= pet.maxY
        if !above { frame.origin.y = frame.maxY - size.height }
        frame.size = size
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
        guard Self.closesOnOutsideClick else { return }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                Text("Лимиты").font(.headline)
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
                .help("Обновить лимиты")
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
                LimitRow(title: "5 ч", window: current.fiveHour, low: UsageLimits.fiveHourLow, now: now)
                LimitRow(title: "7 дн", window: current.sevenDay, low: UsageLimits.sevenDayLow, now: now)
            } else {
                Text(probing ? "Узнаю лимиты…" : "Лимиты пока неизвестны")
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
                    .help("Сброс через \(Format.duration(window.resetsAt.timeIntervalSince(now)))")
            } else {
                Text("нет данных").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

private struct SessionsSection: View {
    let model: StatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Сессии").font(.headline)
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
        case (nil, nil): return "Подключите кубика к Claude Code в меню-баре"
        case (nil, _): return "Сейчас нет сессий Codex. Claude Code можно подключить в меню-баре"
        default: return "Сейчас нет сессий " + [claude, codex].compactMap { $0 }.joined(separator: " и ")
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
                Text(session.project ?? String(session.id.prefix(8))).font(.callout).lineLimit(1)
                Text(source.map { "\($0) · \(detail)" } ?? detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let meta { Text(meta).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
        }
    }

    private var color: Color {
        switch session.status {
        case .working: Color(red: 0.11, green: 0.62, blue: 0.46)
        case .waiting: Color(red: 0.94, green: 0.62, blue: 0.15)
        case .failed: Color(red: 0.89, green: 0.29, blue: 0.29)
        case .idle: Color.secondary.opacity(0.5)
        }
    }

    private var detail: String {
        switch session.status {
        case .working:
            let since = session.workingSince.map { " · " + Format.duration(now.timeIntervalSince($0)) } ?? ""
            return (session.currentTool.map { "работает · \(Format.tool($0))" } ?? "работает") + since
        case .waiting: return "ждёт ввода"
        case .failed: return "ошибка"
        case .idle: return "простаивает"
        }
    }

    private var meta: String? {
        let parts = [AgentSession.shortModel(session.model),
                     session.contextPercent.map { "ctx \(Int($0.rounded()))%" },
                     session.subagents.isEmpty ? nil : "+\(session.subagents.count) саб."]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

enum Format {
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        return seconds < 60 ? "только что" : "\(duration(seconds)) назад"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        if minutes < 1 { return "<1 мин" }
        if minutes < 60 { return "\(minutes) мин" }
        let hours = minutes / 60
        if hours < 24 { return minutes % 60 == 0 ? "\(hours) ч" : "\(hours) ч \(minutes % 60) мин" }
        return "\(hours / 24) д \(hours % 24) ч"
    }

    /// "mcp__terminal__run_in_terminal" -> "run_in_terminal".
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
    }
}

import AppKit
import PetCore
import SwiftUI

/// Card next to the pet with limits and live sessions. A borderless panel rather than NSPopover:
/// glass popovers take their tint from the wallpaper, which fights a solid, readable card.
@MainActor
final class StatusPanel {
    private let panel: NSPanel
    private let model: StatusModel
    private var monitors: [Any] = []
    private weak var anchor: NSView?
    /// Bumped on every show/close so a fade-out finishing late can't hide a card that was just reopened.
    private var generation = 0
    private var isClosing = false
    private var clock: Timer?

    init(model: StatusModel) {
        self.model = model
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: StatusPanelView(model: model))
    }

    var isShown: Bool { panel.isVisible && !isClosing }

    func toggle(from view: NSView) {
        isShown ? close() : show(from: view)
    }

    func show(from view: NSView) {
        guard let petWindow = view.window else { return }
        generation += 1
        isClosing = false
        anchor = view
        model.now = Date()
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 340, height: 200))
        let origin = position(for: panel.frame.size, near: petWindow.frame, on: petWindow.screen ?? NSScreen.main)
        // Enter: fade in while settling 6 pt toward the pet, ease-out, under 200 ms.
        let lift: CGFloat = origin.y >= petWindow.frame.maxY ? 6 : -6
        panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y + lift))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(origin)
        }
        watchOutsideClicks()
        // "Resets in" and "seen N min ago" keep moving while the card is open.
        clock?.invalidate()
        let clock = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.now = Date() }
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
        // Exit faster than enter.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
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

    /// Clicks anywhere else close the card; clicks on the pet are left to its own toggle.
    private func watchOutsideClicks() {
        monitors.forEach(NSEvent.removeMonitor)
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.window !== self.panel && event.window !== self.anchor?.window { self.close() }
            }
            return event
        }
        monitors = [global, local].compactMap { $0 }
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
        let limits = model.limits?.current(at: model.now)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Лимиты").font(.headline)
                Spacer()
                if let observed = model.limits?.observedAt {
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
            if let limits, !limits.isEmpty {
                LimitRow(title: "5 ч", window: limits.fiveHour, low: UsageLimits.fiveHourLow, now: model.now)
                LimitRow(title: "7 дн", window: limits.sevenDay, low: UsageLimits.sevenDayLow, now: model.now)
            } else {
                Text(model.isProbing ? "Узнаю лимиты…" : "Лимиты пока неизвестны")
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
            if model.sessions.isEmpty {
                Text(model.hooksConnected ? "Сейчас нет сессий Claude Code"
                                          : "Подключите кубика к Claude Code в меню-баре")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(model.sessions, id: \.id) { SessionRow(session: $0, now: model.now) }
            }
        }
    }
}

private struct SessionRow: View {
    let session: AgentSession
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.project ?? String(session.id.prefix(8))).font(.callout).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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

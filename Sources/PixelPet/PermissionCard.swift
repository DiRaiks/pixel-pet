import AppKit
import Observation
import PetCore
import PetIntegrations
import SwiftUI

/// What the permission card shows: the oldest waiting request and how many there are.
@MainActor
@Observable
final class PermissionModel {
    var prompt: PermissionPrompt?
    var index = 0
    var count = 0
    /// "Don't ask again": allow with Claude Code's suggested rule.
    var always = false
    /// The buttons go live half a second after a request appears, so a click meant for the previous one (or
    /// a double click) can't answer one nobody has read.
    var armed = false
    @ObservationIgnored var onChange: (() -> Void)?
}

typealias PermissionPanel = CardPanel<PermissionView>

struct PermissionView: View {
    let model: PermissionModel
    var onAnswer: (UUID, PermissionAnswer) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let prompt = model.prompt {
                header(prompt)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if !prompt.subject.isEmpty {
                            Text(prompt.subject).font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // The rest of an unusual tool's input, small: nothing it asks for stays hidden.
                        ForEach(prompt.fields, id: \.key) { field in
                            (Text("\(field.key): ").foregroundStyle(.secondary) + Text(field.value))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                }
                // About eight lines; longer commands scroll.
                .scrollIndicators(.visible)
                .frame(maxHeight: 132)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                if let detail = prompt.detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if prompt.suggestions != nil {
                    Toggle(isOn: Binding(get: { model.always }, set: { model.always = $0 })) {
                        Text(prompt.ruleSummary.map {
                            L("Don't ask again for \($0)", "Больше не спрашивать для \($0)")
                        } ?? L("Don't ask again (Claude Code's suggested rules)", "Больше не спрашивать (правила от Claude Code)"))
                            .font(.callout).lineLimit(1).truncationMode(.middle)
                    }
                    .toggleStyle(.checkbox)
                }
                HStack(spacing: 8) {
                    Button(Self.handBack(prompt.host)) { onAnswer(prompt.id, .passToHost) }
                        .buttonStyle(.link).font(.callout).lineLimit(1).fixedSize()
                    Spacer(minLength: 8)
                    Button(L("Deny", "Запретить"), role: .destructive) { onAnswer(prompt.id, .deny) }
                        .fixedSize().disabled(!model.armed)
                    Button(L("Allow", "Разрешить")) { onAnswer(prompt.id, model.always ? .allowAlways : .allow) }
                        .buttonStyle(.borderedProminent).fixedSize().disabled(!model.armed)
                }
            }
        }
        .padding(16)
        .frame(width: 384)
        // The card never takes focus, and AppKit would draw its buttons as in a background window (grey Allow).
        .environment(\.controlActiveState, .key)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    private func header(_ prompt: PermissionPrompt) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(prompt.kind, agent: prompt.agentName)).font(.headline)
                Text(subtitle(prompt)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { onAnswer(prompt.id, .passToHost) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).help(Self.handBack(prompt.host))
                .accessibilityLabel(Self.handBack(prompt.host))
        }
    }

    private func subtitle(_ prompt: PermissionPrompt) -> String {
        var parts = [prompt.project, Self.toolName(prompt.tool)].compactMap { $0 }
        if model.count > 1 { parts.append(L("\(model.index + 1) of \(model.count)", "\(model.index + 1) из \(model.count)")) }
        return parts.joined(separator: " · ")
    }

    static func title(_ kind: PermissionPrompt.Kind, agent: String) -> String {
        switch kind {
        case .command: L("\(agent) wants to run a command", "\(agent) хочет выполнить команду")
        case .edit: L("\(agent) wants to change a file", "\(agent) хочет изменить файл")
        case .web: L("\(agent) wants to go online", "\(agent) хочет в интернет")
        case .mcp, .other: L("\(agent) wants to use a tool", "\(agent) хочет использовать инструмент")
        }
    }

    /// "mcp__github__create_issue" reads as "github: create_issue".
    static func toolName(_ tool: String) -> String {
        guard tool.hasPrefix("mcp__") else { return tool }
        let parts = tool.dropFirst(5).components(separatedBy: "__")
        return parts.count >= 2 ? "\(parts[0]): \(parts.dropFirst().joined(separator: "__"))" : tool
    }

    static func handBack(_ host: AgentHost?) -> String {
        guard let names = host?.names else { return L("Answer there", "Ответить там") }
        return L("Answer in \(names.en)", "Ответить в \(names.ru)")
    }
}

/// Holds the waiting permission requests and the card for them. A request waits only while the setting is on
/// and the pet is on screen (not hidden, not in do-not-disturb, not covered); otherwise, and when the card is
/// dismissed, nobody answers in time, the hook goes away or the session ends, Claude Code asks the usual way.
@MainActor
final class PermissionDesk {
    /// More than this waiting at once (a burst of subagents, or a misbehaving client) are let go at once.
    static let maxWaiting = 16
    /// How long a new request's buttons stay off.
    static let armDelay: TimeInterval = 0.5

    private let pet: PetController
    private let model = PermissionModel()
    private let panel: PermissionPanel
    private var queue = PermissionQueue()
    private var replies: [UUID: HookReply] = [:]
    private var expiry: [UUID: DispatchWorkItem] = [:]
    /// The card was opened by `show`: while true, closing it lets every waiting request go.
    private var answering = false
    /// Letting several go at once: show the card once at the end, not after each.
    private var releasing = false

    /// The card opened: the other cards make way.
    var onShow: (() -> Void)?
    /// A held request's hook went away: answered where the session runs. Takes the session id.
    var onSettledElsewhere: ((String) -> Void)?
    var isShown: Bool { panel.isShown }

    init(pet: PetController) {
        self.pet = pet
        var answer: (UUID, PermissionAnswer) -> Void = { _, _ in }
        panel = PermissionPanel(content: PermissionView(model: model, onAnswer: { answer($0, $1) }), staysOpen: true)
        answer = { [weak self] in self?.answer($0, $1) }
        panel.onShow = { [weak self] in self?.onShow?() }
        panel.onClose = { [weak self] in
            guard let self, answering else { return }
            answering = false
            letAllGo()
        }
    }

    /// A permission request from the hook, with its open connection.
    func receive(_ data: Data, reply: HookReply) {
        guard canWait, queue.prompts.count < Self.maxWaiting, let prompt = PermissionPrompt.parse(data) else {
            reply.send(nil)
            return
        }
        queue.add(prompt)
        replies[prompt.id] = reply
        let id = prompt.id
        let session = prompt.sessionID
        reply.onGone { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.settledElsewhere(id, session) } }
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.finish(id, with: .passToHost, activate: false) }
        }
        expiry[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + PermissionWait.window, execute: work)
        show()
    }

    /// The session's request was answered where it runs (seen in its transcript): the card has nothing to ask.
    func answeredElsewhere(_ sessionID: String) {
        sessionEnded(sessionID)
    }

    /// A session that ended has nothing to answer any more.
    func sessionEnded(_ sessionID: String) {
        let gone = queue.prompts.filter { $0.sessionID == sessionID }
        releasing = true
        for prompt in gone { finish(prompt.id, with: .passToHost, activate: false) }
        releasing = false
        show()
    }

    /// The setting went off: let everything go.
    func settingsChanged() {
        if !canWait { letAllGo() }
    }

    private var canWait: Bool {
        pet.config.approveFromPet && !pet.doNotDisturb && pet.isOnScreen
    }

    /// Only the request on the card, and only once its buttons are live.
    private func answer(_ id: UUID, _ answer: PermissionAnswer) {
        guard id == queue.current?.id, answer == .passToHost || model.armed else { return }
        finish(id, with: answer, activate: answer == .passToHost)
    }

    private func settledElsewhere(_ id: UUID, _ session: String) {
        guard replies[id] != nil else { return }
        finish(id, with: .passToHost, activate: false)
        onSettledElsewhere?(session)
    }

    private func finish(_ id: UUID, with answer: PermissionAnswer, activate: Bool) {
        let prompt = queue.remove(id)
        expiry.removeValue(forKey: id)?.cancel()
        if let reply = replies.removeValue(forKey: id) {
            reply.send(prompt.flatMap { answer.hookOutput(for: $0) })
        }
        if activate, let bundle = prompt?.host?.bundleID {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.activate()
        }
        if !releasing { show() }
    }

    private func letAllGo() {
        releasing = true
        for prompt in queue.prompts { finish(prompt.id, with: .passToHost, activate: false) }
        releasing = false
        show()
    }

    /// Shows the oldest request, or closes the card when none is left.
    private func show() {
        guard let current = queue.current else {
            model.prompt = nil
            if panel.isShown {
                answering = false
                panel.close()
            }
            return
        }
        if model.prompt?.id != current.id {
            model.always = false
            model.armed = false
            let id = current.id
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.armDelay) { [weak self] in
                guard let self, model.prompt?.id == id else { return }
                model.armed = true
            }
        }
        model.prompt = current
        model.index = 0
        model.count = queue.prompts.count
        if panel.isShown {
            DispatchQueue.main.async { [weak self] in self?.panel.refit() }
            return
        }
        panel.show(from: pet.anchorView, animated: true)
        DispatchQueue.main.async { [weak self] in self?.panel.refit() }
        answering = panel.isShown
        // Nothing on screen to answer with: don't keep Claude Code waiting.
        if !panel.isShown { letAllGo() }
    }
}


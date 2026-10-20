import AppKit
import Observation
import PetCore
import PetIntegrations
import SwiftUI

@MainActor
@Observable
final class AskModel {
    var conversation = AskConversation()
    var draft = ""
    var modelName = "haiku"
    /// Measured height of the question/answer history (kept here: `@State` is a macro that the
    /// Command Line Tools toolchain can't expand).
    var historyHeight: CGFloat = 0
    /// Files dropped on the pet, sent with the next question.
    var files: [Attachment] = []
    /// Dropped files it couldn't take, and why, for one line under the chips.
    var skipped: [String] = []
    /// Content height changed; the card window re-fits.
    @ObservationIgnored var onLayout: (() -> Void)?
}

typealias AskPanel = CardPanel<AskView>

struct AskView: View {
    let model: AskModel
    var onSend: () -> Void = {}
    var onStop: () -> Void = {}
    var onNew: () -> Void = {}
    var onClose: () -> Void = {}
    /// A suggested question for the files: sent at once.
    var onSuggest: (String) -> Void = { _ in }

    @FocusState private var inputFocused: Bool

    private var placeholder: String {
        if let first = model.files.first {
            return model.files.count == 1 ? L("Ask about \(first.name)…", "Что спросить про \(first.name)?")
                : L("Ask about these files…", "Что спросить про эти файлы?")
        }
        return model.conversation.turns.isEmpty ? L("Ask anything…", "Спросите что-нибудь…") : L("Follow up…", "Уточните…")
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(L("Ask Claude", "Спросить Claude")).font(.headline)
                Text(model.modelName).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !model.conversation.turns.isEmpty {
                    Button(L("New", "Новый"), action: onNew).buttonStyle(.borderless)
                        .help(L("Start a new conversation", "Начать новый диалог"))
                }
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help(L("Close (Esc)", "Закрыть (Esc)"))
            }
            if !model.conversation.turns.isEmpty { history }
            if !model.files.isEmpty || !model.skipped.isEmpty { files }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: $model.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .onSubmit(onSend)
                    .disabled(model.conversation.isStreaming)
                if model.conversation.isStreaming {
                    Button(action: onStop) { Image(systemName: "stop.circle.fill").font(.title3) }
                        .buttonStyle(.borderless).help(L("Stop", "Остановить"))
                } else {
                    Button(action: onSend) { Image(systemName: "arrow.up.circle.fill").font(.title3) }
                        .buttonStyle(.borderless)
                        .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help(L("Send (Return)", "Отправить (Enter)"))
                }
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            if let answer = model.conversation.lastAnswer, !model.conversation.isStreaming {
                HStack {
                    Spacer()
                    Button(L("Copy answer", "Копировать ответ")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(answer, forType: .string)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .onExitCommand(perform: onClose)
        .onAppear { inputFocused = true }
        .onChange(of: model.conversation.isStreaming) { _, streaming in
            if !streaming { inputFocused = true }
            model.onLayout?()
        }
        // A multi-line question grows the field; the window follows.
        .onChange(of: model.draft) { _, _ in model.onLayout?() }
        .onChange(of: model.files.count) { _, _ in
            inputFocused = true
            model.onLayout?()
        }
    }

    /// The files waiting to go with the next question, what it couldn't take, and questions to start with.
    private var files: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(model.files.enumerated()), id: \.offset) { index, file in
                HStack(spacing: 10) {
                    Image(systemName: FileText.symbol(file.kind)).font(.title3).foregroundStyle(.secondary).frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                        Text(FileText.details(file)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.files.remove(at: index) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).help(L("Don't send this file", "Не отправлять этот файл"))
                }
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            if !model.skipped.isEmpty {
                Text(L("Not taken: ", "Не взял: ") + model.skipped.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !model.files.isEmpty, model.draft.isEmpty, !model.conversation.isStreaming {
                HStack(spacing: 6) {
                    ForEach(FileText.suggestions(model.files.map(\.kind)), id: \.self) { question in
                        Button(question) { onSuggest(question) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
    }

    /// Questions and answers; scrolls once taller than 420 pt and follows the streaming answer.
    private var history: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(model.conversation.turns.enumerated()), id: \.offset) { _, turn in
                        TurnView(turn: turn)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: HistoryHeight.self, value: geometry.size.height)
                })
            }
            .frame(height: min(model.historyHeight, 420))
            .onPreferenceChange(HistoryHeight.self) { height in
                model.historyHeight = height
                model.onLayout?()
            }
            .onChange(of: model.conversation.turns.last?.answer) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}

private struct TurnView: View {
    let turn: AskConversation.Turn

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !turn.files.isEmpty {
                Label(turn.files.joined(separator: ", "), systemImage: "paperclip")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Text(turn.question).font(.callout.weight(.medium)).foregroundStyle(.secondary).textSelection(.enabled)
            if turn.answer.isEmpty, turn.state == .streaming {
                ProgressView().controlSize(.small)
            } else if !turn.answer.isEmpty {
                ForEach(Array(AnswerText.segments(turn.answer).enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .prose(let text):
                        Text(Self.markdown(text)).font(.body).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .code(let code):
                        Text(code).font(.callout.monospaced()).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            switch turn.state {
            case .failed(let message):
                Text(message).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            case .stopped:
                Text(L("Stopped", "Остановлено")).font(.caption).foregroundStyle(.secondary)
            case .streaming, .done:
                EmptyView()
            }
        }
    }

    /// Inline Markdown (bold, code, links) keeping line breaks; anything it can't parse stays plain.
    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

private struct HistoryHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Hotkey → card with a text field → `claude -p` streamed into it; follow-ups resume the same session.
@MainActor
final class Asker {
    let model = AskModel()
    let panel: AskPanel
    private let pet: PetController
    private var task: Task<Void, Never>?
    /// Identifies the current run, so a finishing older run doesn't clear the newer one's handle.
    private var runID = 0
    private var refitScheduled = false
    var onLimits: ((UsageLimits) -> Void)?

    init(pet: PetController) {
        self.pet = pet
        var send: () -> Void = {}
        var stop: () -> Void = {}
        var new: () -> Void = {}
        var close: () -> Void = {}
        var suggest: (String) -> Void = { _ in }
        panel = AskPanel(content: AskView(model: model, onSend: { send() }, onStop: { stop() },
                                          onNew: { new() }, onClose: { close() }, onSuggest: { suggest($0) }),
                         keyboard: true)
        suggest = { [weak self] question in
            self?.model.draft = question
            self?.send()
        }
        send = { [weak self] in self?.send() }
        stop = { [weak self] in self?.stop() }
        new = { [weak self] in self?.newConversation() }
        close = { [weak self] in self?.panel.close() }
        model.onLayout = { [weak self] in self?.scheduleRefit() }
        // Closing stops an answer still streaming, but lets a finished run write its session for follow-ups.
        panel.onClose = { [weak self] in
            guard let self else { return }
            if pet.config.logEvents { EventLog.append("ask card closed") }
            if model.conversation.isStreaming { stop() }
            model.files = []
            model.skipped = []
            pet.setTalking(false)
        }
    }

    /// Files dropped on the pet: read them off the main thread, swallow (or shake the head), then open the
    /// card with them attached to the next question.
    func attach(_ urls: [URL]) {
        let taken = Array(urls.prefix(Attachment.maxFiles))
        let extra = urls.dropFirst(Attachment.maxFiles).map(\.lastPathComponent)
        Task { @MainActor [weak self] in
            let results = await Task.detached { taken.map { ($0.lastPathComponent, AttachmentLoader.load($0)) } }.value
            guard let self else { return }
            var files: [Attachment] = []
            var skipped: [String] = []
            for (name, result) in results {
                switch result {
                case .success(let file): files.append(file)
                case .failure(let why): skipped.append("\(name) (\(FileText.refusal(why)))")
                }
            }
            skipped += extra.map { L("\($0) (over \(Attachment.maxFiles) files)", "\($0) (больше \(Attachment.maxFiles) файлов)") }
            pet.caughtFiles(!files.isEmpty)
            guard !files.isEmpty else { return }
            model.files = Array((model.files + files).suffix(Attachment.maxFiles))
            model.skipped = skipped
            // The card opens as the chewing ends.
            try? await Task.sleep(for: .seconds(0.8))
            if !panel.isShown { toggle() }
        }
    }

    /// ⌃⌥K opens the card; pressing it again closes it, unless an answer is still coming in.
    func toggle() {
        if panel.isShown {
            if !model.conversation.isStreaming { panel.close() }
        } else {
            model.modelName = pet.config.askModel
            panel.show(from: pet.anchorView, animated: false)
            if panel.isShown { pet.setTalking(true) }
        }
    }

    /// Debug aid (`--ask`, `--ask-followup`): type and send a question.
    func ask(_ question: String) {
        if !panel.isShown { toggle() }
        model.draft = question
        send()
    }

    func newConversation() {
        if model.conversation.isStreaming { stop() }
        model.conversation.reset()
        model.draft = ""
        model.files = []
        model.skipped = []
        model.historyHeight = 0
        // Once the last run has exited, nothing of the old conversation stays on disk.
        let last = task
        Task { @MainActor in
            await last?.value
            AskSessions.removeAll()
        }
        panel.refit()
    }

    private func stop() {
        if let ticket = model.conversation.ticket { model.conversation.cancel(ticket: ticket) }
        task?.cancel()
    }

    /// Streaming updates arrive per token; re-fit the window at most every 50 ms.
    private func scheduleRefit() {
        guard !refitScheduled else { return }
        refitScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                self?.refitScheduled = false
                self?.panel.refit()
            }
        }
    }

    private func send() {
        let files = model.files
        guard model.conversation.ask(model.draft, files: files.map(\.name)), let ticket = model.conversation.ticket else { return }
        let question = model.conversation.turns[ticket.turn].question
        model.draft = ""
        model.files = []
        model.skipped = []
        // Files go in the message itself: text in tagged blocks, pictures as image blocks (stream-json input).
        let streamInput = files.contains(where: \.needsStreamInput)
        let input = streamInput ? Attachment.streamMessage(question: question, files: files)
            : Data((files.isEmpty ? question : Attachment.prompt(question: question, files: files)).utf8)
        guard let claude = ClaudeLocator.find() else {
            model.conversation.fail(L("Couldn't find the Claude Code CLI.", "Не нашёл Claude Code CLI."), ticket: ticket)
            return
        }
        let askModel = pet.config.askModel
        let log = pet.config.logEvents
        // The previous CLI process keeps writing its session for a moment after the answer is shown;
        // a follow-up resuming that session must wait for it to exit, or its turn is lost.
        let previous = task
        runID += 1
        let run = runID
        task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            guard !Task.isCancelled, ticket.epoch == model.conversation.epoch else {
                model.conversation.cancel(ticket: ticket)
                return
            }
            // Read the session only now: everything from the previous run has been applied.
            let resume = model.conversation.sessionID
            if log { EventLog.append("ask start resume=\(resume?.prefix(8) ?? "-")") }
            // One stream, one consumer: events reach the conversation in the order the CLI sent them.
            let (events, sink) = AsyncStream.makeStream(of: ClaudeChat.Event.self)
            async let outcome = Self.chat(claude: claude, arguments: ClaudeAsk.arguments(model: askModel, resume: resume,
                                                                                          streamInput: streamInput),
                                          input: input, sink: sink)
            for await event in events { apply(event, ticket, log: log) }
            let result = await outcome
            if run == runID { task = nil }
            if log { EventLog.append("ask finished \(Self.describe(result))") }
            finish(result, ticket, resumed: resume != nil)
        }
    }

    private nonisolated static func chat(claude: URL, arguments: [String], input: Data,
                                         sink: AsyncStream<ClaudeChat.Event>.Continuation) async
        -> Result<String, ClaudeTranslation.Failure> {
        let result = await ClaudeChat.run(claude: claude, arguments: arguments, stdin: input) { sink.yield($0) }
        sink.finish()
        return result
    }

    private func apply(_ event: ClaudeChat.Event, _ ticket: AskConversation.Ticket, log: Bool) {
        switch event {
        case .session(let id):
            if log { EventLog.append("ask session \(id.prefix(8))") }
            model.conversation.receive(session: id, ticket: ticket)
        case .text(let text):
            model.conversation.receive(text: text, ticket: ticket)
        case .done(let text):
            model.conversation.receive(text: text, ticket: ticket)
            model.conversation.complete(ticket: ticket)
        case .limits(let limits):
            onLimits?(limits)
        }
    }

    private func finish(_ result: Result<String, ClaudeTranslation.Failure>, _ ticket: AskConversation.Ticket,
                        resumed: Bool) {
        switch result {
        case .success(let text):
            model.conversation.receive(text: text, ticket: ticket)
            model.conversation.complete(ticket: ticket)
        case .failure(.cancelled):
            model.conversation.cancel(ticket: ticket)
        case .failure(.claude(let message)):
            if resumed, message.localizedCaseInsensitiveContains("no conversation found") {
                model.conversation.forgetSession()
                model.conversation.fail(L("The previous conversation's context was lost. Ask again to start over.",
                                               "Контекст прошлого диалога потерян. Спросите ещё раз, начнём заново."), ticket: ticket)
            } else {
                model.conversation.fail("Claude: \(message)", ticket: ticket)
            }
        case .failure(.noOutput):
            model.conversation.fail(L("Claude didn't answer.", "Claude ничего не ответил."), ticket: ticket)
        }
    }

    private static func describe(_ result: Result<String, ClaudeTranslation.Failure>) -> String {
        switch result {
        case .success: "ok"
        case .failure(.cancelled): "cancelled"
        case .failure(.claude): "claude-error"
        case .failure(.noOutput): "no-output"
        }
    }
}

/// Quick-ask sessions live under the pet's own workdir in ~/.claude/projects. They exist only so
/// follow-ups can resume; the pet removes them when a conversation is dropped, on quit and on launch.
enum AskSessions {
    static func removeAll() {
        let projects = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: projects.path)) ?? []
        for name in names where name.hasSuffix("-pixelpet-claude") {
            try? FileManager.default.removeItem(at: projects.appendingPathComponent(name))
        }
    }
}

/// Words and symbols for attached files.
@MainActor
enum FileText {
    static func symbol(_ kind: Attachment.Kind) -> String {
        switch kind {
        case .text: "doc.text"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .pdf: "doc.richtext"
        case .image: "photo"
        }
    }

    static func details(_ file: Attachment) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file)
        let kind: String = switch file.kind {
        case .text: L("Text", "Текст")
        case .code: L("Code", "Код")
        case .pdf: file.pages.map { L("PDF · \($0) pages", "PDF · \($0) стр.") } ?? "PDF"
        case .image: L("Image", "Картинка")
        }
        let cut = file.truncated ? L(" · only the beginning is sent", " · уйдёт только начало") : ""
        return "\(kind) · \(size)\(cut)"
    }

    static func refusal(_ why: AttachmentLoader.Refusal) -> String {
        switch why {
        case .folder: L("a folder", "папка")
        case .unsupported: L("not text, PDF or an image", "не текст, PDF или картинка")
        case .tooLarge: L("too large", "слишком большой")
        case .unreadable: L("can't read it", "не читается")
        case .empty: L("empty", "пустой")
        }
    }

    /// Questions to start with, by what was dropped.
    static func suggestions(_ kinds: [Attachment.Kind]) -> [String] {
        if Set(kinds).count > 1 || kinds.count > 1 {
            return [L("What are these files?", "Что это за файлы?"), L("Compare them", "Сравни их")]
        }
        switch kinds.first {
        case .code: return [L("What does it do?", "Что делает этот код?"), L("Find bugs", "Найди баги")]
        case .image: return [L("What's in the picture?", "Что на картинке?"), L("Copy out the text", "Перепиши текст с картинки")]
        case .pdf, .text: return [L("What's it about?", "О чём это?"), L("Key points", "Главное в 5 пунктах")]
        case nil: return []
        }
    }
}

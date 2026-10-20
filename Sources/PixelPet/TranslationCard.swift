import AppKit
import NaturalLanguage
import Observation
import PetCore
import PetIntegrations
import SwiftUI
import Translation

/// State of the translation card. The actual translating happens in the view's `translationTask`,
/// which also offers to download missing languages.
@MainActor
@Observable
final class TranslationModel {
    enum Phase: Equatable {
        case reading
        case translating
        case done(String)
        case needsPermission
        case nothingSelected
        case secureField
        case clipboardBusy
        case failed(String)
    }

    var phase = Phase.reading {
        didSet { if phase != oldValue { onPhaseChange?() } }
    }
    /// The card re-fits its window to the new content.
    @ObservationIgnored var onPhaseChange: (() -> Void)?
    var plan: TranslationPlan?
    var configuration: TranslationSession.Configuration?

    /// The optional second opinion from Claude, streamed in under Apple's result.
    enum ClaudeState: Equatable {
        case running(String)
        case done(String)
        case failed(String)
    }

    var claude: ClaudeState? {
        didSet { if claude != oldValue { onPhaseChange?() } }
    }
    /// Bumped on every new request and on close; a translation finishing for an older request is dropped.
    private(set) var request = 0
    /// How tall the translated text may get before it scrolls, from the screen the card is on.
    var maxResultHeight: CGFloat = 420

    /// Forget the current request; a translation still running for it is dropped when it finishes. The
    /// configuration stays: see `start`.
    func reset() {
        request += 1
        plan = nil
        claude = nil
        phase = .reading
    }

    /// The translation runs when the configuration changes. A fresh configuration for the same languages
    /// compares equal to the last one, so SwiftUI wouldn't run it again and the card would sit on
    /// "Translating…" forever; `invalidate()` is how a configuration asks to run again.
    func start(_ plan: TranslationPlan) {
        self.plan = plan
        phase = .translating
        let source = plan.source.map { Locale.Language(identifier: $0) }
        let target = Locale.Language(identifier: plan.target)
        if configuration?.source == source, configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }

    /// Copies Claude's translation when there is one, otherwise Apple's.
    func copyResult() {
        let text: String
        if case .done(let claudeText) = claude {
            text = claudeText
        } else if case .done(let appleText) = phase {
            text = appleText
        } else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Short snippets are easy to misread, so the user's two languages get a head start.
    static func detectLanguage(_ text: String, native: String, foreign: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageHints = [NLLanguage(rawValue: native): 0.4, NLLanguage(rawValue: foreign): 0.4]
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }
}

typealias TranslationPanel = CardPanel<TranslationView>

struct TranslationView: View {
    let model: TranslationModel
    var onClose: () -> Void = {}
    var onAskClaude: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Translation", "Перевод")).font(.headline)
                if let plan = model.plan {
                    Text("\(plan.source ?? L("auto", "авто")) → \(plan.target)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help(L("Close", "Закрыть"))
            }
            content
        }
        .padding(16)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .translationTask(model.configuration) { session in
            guard let plan = model.plan else { return }
            let request = model.request
            // The framework hands the session to this closure and expects it to be used right here;
            // it isn't Sendable, so opt out of the region check for this one call.
            nonisolated(unsafe) let session = session
            do {
                let response = try await session.translate(plan.text)
                guard request == model.request else { return }
                model.phase = .done(response.targetText)
            } catch is CancellationError {
                return
            } catch {
                guard request == model.request else { return }
                model.phase = .failed(Self.describe(error))
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .reading:
            Text(L("Reading the selection…", "Читаю выделение…")).font(.callout).foregroundStyle(.secondary)
        case .translating:
            original
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("Translating…", "Перевожу…")).font(.callout).foregroundStyle(.secondary)
            }
        case .done(let text):
            original
            // Long results scroll, capped by the screen, so the card never runs off it.
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(text).font(.body).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    claudeSection
                }
            }
            .frame(maxHeight: model.maxResultHeight)
            HStack {
                Spacer()
                if model.claude == nil { Button(L("Via Claude", "Через Claude"), action: onAskClaude)
                        .help(L("More accurate in context, ~3 s", "Точнее по контексту, ~3 с")) }
                Button(L("Copy", "Копировать")) { model.copyResult() }
            }
        case .needsPermission:
            Text(L("To read selected text, the cube needs Accessibility access.",
                    "Чтобы читать выделенный текст, кубику нужен доступ в «Универсальном доступе»."))
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("Open Settings", "Открыть настройки")) { SelectionReader.requestPermission() }
            }
        case .nothingSelected:
            Text(L("Select some text and press ⌃⌥T.", "Выделите текст и нажмите ⌃⌥T.")).font(.callout).foregroundStyle(.secondary)
        case .secureField:
            Text(L("This is a password field; the cube doesn't read it.", "Это поле пароля, его кубик не читает.")).font(.callout).foregroundStyle(.secondary)
        case .clipboardBusy:
            Text(L("The clipboard holds data that can't be restored exactly (files, for example), so the selection isn't read here. Copy the text yourself and press ⌃⌥T again.",
                    "В буфере обмена данные, которые нельзя вернуть в точности (например, файлы), поэтому выделение здесь не читаю. Скопируйте текст сами и нажмите ⌃⌥T ещё раз."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            original
            Text(message).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            claudeSection
            if model.claude == nil {
                HStack {
                    Spacer()
                    Button(L("Via Claude", "Через Claude"), action: onAskClaude)
                }
            }
        }
    }

    @ViewBuilder private var claudeSection: some View {
        if let claude = model.claude {
            Divider()
            HStack(spacing: 6) {
                Text("Claude").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if case .running = claude { ProgressView().controlSize(.mini) }
            }
            switch claude {
            case .running(let text), .done(let text):
                Text(text.isEmpty ? "…" : text).font(.body).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .failed(let message):
                Text(message).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var original: some View {
        if let plan = model.plan {
            Text(plan.text).font(.callout).foregroundStyle(.secondary).lineLimit(3)
        }
    }

    static func describe(_ error: Error) -> String {
        if let error = error as? TranslationError {
            switch error {
            case .unsupportedLanguagePairing, .unsupportedSourceLanguage, .unsupportedTargetLanguage:
                return L("Apple Translation doesn't support this language pair.", "Эту пару языков Apple Translation не поддерживает.")
            case .unableToIdentifyLanguage:
                return L("Couldn't detect the language of the text.", "Не удалось определить язык текста.")
            default:
                break
            }
        }
        return L("Couldn't translate: \(error.localizedDescription)", "Не получилось перевести: \(error.localizedDescription)")
    }
}

/// Hotkey → read selection → plan → show the card at once (no entrance animation for keyboard actions).
@MainActor
final class Translator {
    let model = TranslationModel()
    let panel: TranslationPanel
    private let pet: PetController
    private var reading: Task<Void, Never>?
    private var claudeTask: Task<Void, Never>?
    /// Limits reported by the translation run, handed to the agent monitor.
    var onLimits: ((UsageLimits) -> Void)?

    init(pet: PetController) {
        self.pet = pet
        var closeAction: () -> Void = {}
        var claudeAction: () -> Void = {}
        panel = TranslationPanel(content: TranslationView(model: model, onClose: { closeAction() },
                                                          onAskClaude: { claudeAction() }))
        closeAction = { [weak self] in self?.panel.close() }
        claudeAction = { [weak self] in self?.translateWithClaude() }
        model.onPhaseChange = { [weak self] in
            // Let SwiftUI lay out the new content first.
            DispatchQueue.main.async { self?.panel.refit() }
        }
        panel.onClose = { [weak self] in
            guard let self else { return }
            reading?.cancel()
            reading = nil
            claudeTask?.cancel()
            claudeTask = nil
            model.reset()
            pet.setTalking(false)
        }
    }

    func translateSelection() {
        // A second press while the selection is still being read is ignored (see SelectionReader).
        guard reading == nil else { return }
        model.reset()
        let request = model.request
        open()
        reading = Task { @MainActor [weak self] in
            let result = await SelectionReader.read()
            guard let self else { return }
            reading = nil
            guard !Task.isCancelled, request == model.request, panel.isShown else { return }
            switch result {
            case .failure(.busy):
                return
            case .failure(.noPermission):
                model.phase = .needsPermission
            case .failure(.nothingSelected):
                model.phase = .nothingSelected
            case .failure(.secureField):
                model.phase = .secureField
            case .failure(.clipboardBusy):
                model.phase = .clipboardBusy
            case .success(let text):
                start(text)
            }
            panel.refit()
        }
    }

    /// Debug aid (`--translate-text "…"`): skip reading the selection.
    func translate(_ text: String) {
        model.reset()
        open()
        start(text)
        panel.refit()
    }

    /// Second opinion: the same text through `claude -p`, streamed into the card.
    func translateWithClaude() {
        guard let plan = model.plan, claudeTask == nil else { return }
        guard let claude = ClaudeLocator.find() else {
            model.claude = .failed(L("Couldn't find the Claude Code CLI.", "Не нашёл Claude Code CLI."))
            return
        }
        let request = model.request
        model.claude = .running("")
        let model = self.model
        let onText: @Sendable (String) -> Void = { text in
            Task { @MainActor in
                guard request == model.request, case .running = model.claude else { return }
                model.claude = .running(text)
            }
        }
        let onLimits: @Sendable (UsageLimits) -> Void = { [weak self] limits in
            Task { @MainActor in self?.onLimits?(limits) }
        }
        // The spinner stops at message_stop, not when the CLI exits a second later.
        let onDone: @Sendable (String) -> Void = { text in
            Task { @MainActor in
                guard request == model.request, case .running = model.claude else { return }
                model.claude = .done(text)
            }
        }
        claudeTask = Task { @MainActor [weak self] in
            let result = await ClaudeTranslation.run(claude: claude, text: plan.text, target: plan.target,
                                                     onText: onText, onDone: onDone, onLimits: onLimits)
            guard let self else { return }
            claudeTask = nil
            guard request == model.request else { return }
            switch result {
            case .success(let text): if case .running = model.claude { model.claude = .done(text) }
            case .failure(.cancelled): break
            case .failure(.claude(let message)): model.claude = .failed("Claude: \(message)")
            case .failure(.noOutput): model.claude = .failed(L("Claude didn't answer.", "Claude ничего не ответил."))
            }
        }
    }

    private func open() {
        // Room for the header, the original and the buttons; the rest of the screen for the translation.
        let screen = pet.anchorView.window?.screen ?? NSScreen.main
        model.maxResultHeight = max(160, min(480, (screen?.visibleFrame.height ?? 800) - 260))
        panel.show(from: pet.anchorView, animated: false)
        if panel.isShown { pet.setTalking(true) }
    }

    private func start(_ text: String) {
        let config = pet.config
        let detected = TranslationModel.detectLanguage(text, native: config.nativeLanguage, foreign: config.foreignLanguage)
        if let plan = TranslationPlan.make(text: text, detected: detected, native: config.nativeLanguage,
                                           foreign: config.foreignLanguage) {
            model.start(plan)
        } else {
            model.phase = .nothingSelected
        }
    }
}

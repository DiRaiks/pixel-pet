import AppKit
import Observation
import PetCore
import SwiftUI

/// What the listen card shows: getting ready, the words as they're recognized, then the text to use.
@MainActor
@Observable
final class ListenModel {
    enum Phase: Equatable {
        /// Not listening, the card closed.
        case idle
        case starting
        case downloading
        case listening
        case finishing
        case done
        case nothingHeard
        case needsPermission
        case noMic
        case unsupported
        case failed(String)
    }

    var phase = Phase.idle {
        didSet { if phase != oldValue { onLayout?() } }
    }
    var text = "" {
        didSet { if text != oldValue { onLayout?() } }
    }
    /// Started with ⌃⌥L (stops on its own or on a second press) rather than held down.
    var handsFree = false
    var language = "ru"
    /// The card re-fits its window to the new content.
    @ObservationIgnored var onLayout: (() -> Void)?

    var isActive: Bool { [.starting, .downloading, .listening, .finishing].contains(phase) }
}

struct ListenView: View {
    @Bindable var model: ListenModel
    var onClose: () -> Void = {}
    var onAsk: () -> Void = {}
    var onTranslate: () -> Void = {}
    var onCopy: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: model.isActive ? "mic.fill" : "text.bubble")
                    .foregroundStyle(model.isActive ? Color.red : Color.secondary)
                Text(title).font(.headline)
                Text(model.language.uppercased()).font(.caption).foregroundStyle(.secondary)
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
    }

    private var title: String {
        model.isActive ? L("Listening…", "Слушаю…") : L("Heard", "Услышано")
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .starting:
            note(L("Getting ready…", "Готовлюсь…"))
        case .downloading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                note(L("Downloading the speech model (once per language)…", "Скачиваю модель речи (один раз на язык)…"))
            }
        case .listening, .finishing:
            if model.text.isEmpty {
                note(L("Speak, I'm listening.", "Говорите, я слушаю."))
            } else {
                Text(model.text).font(.body).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            note(model.phase == .finishing ? L("Finishing…", "Дослушиваю…")
                 : model.handsFree ? L("⌃⌥L or a pause to finish", "⌃⌥L или пауза, чтобы закончить")
                 : L("Let go to finish", "Отпустите, чтобы закончить"))
                .font(.caption)
        case .done:
            TextField("", text: $model.text, axis: .vertical)
                .textFieldStyle(.plain).font(.body).lineLimit(1...10)
            HStack {
                Spacer()
                Button(L("Copy", "Копировать"), action: onCopy)
                Button(L("Translate", "Перевести"), action: onTranslate)
                Button(L("Ask Claude", "Спросить Claude"), action: onAsk).keyboardShortcut(.defaultAction)
            }
        case .nothingHeard:
            note(L("Didn't catch anything.", "Ничего не расслышал."))
        case .needsPermission:
            note(L("The cube needs access to the microphone.", "Кубику нужен доступ к микрофону."))
            HStack {
                Spacer()
                Button(L("Open Settings", "Открыть настройки")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        case .noMic:
            note(L("No microphone found.", "Не нашёл микрофон."))
        case .unsupported:
            note(L("This Mac doesn't recognize speech in this language. Pick another in Settings → Listening.",
                   "Этот Mac не распознаёт речь на этом языке. Выберите другой в Настройках → Слушать."))
        case .failed(let message):
            Text(message).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

typealias ListenPanel = CardPanel<ListenView>

/// Press and hold the pet (or ⌃⌥L): the mic is turned into text on the Mac, shown live in a card, then
/// handed to Claude, the translator or the clipboard. The text lives only in the card.
@MainActor
final class Listener {
    let model = ListenModel()
    let panel: ListenPanel
    private let pet: PetController
    /// One per take: a take closed while its mic is still starting can't touch the next take's.
    private var speech: SpeechListener?
    private var clock: ListenClock?
    private var ticker: Timer?
    /// Bumped on every take and on close; work finishing for an older take is dropped.
    private var take = 0
    /// Let go (or pressed ⌃⌥L again) while the mic was still starting.
    private var stopWhenStarted = false
    var onAsk: ((String) -> Void)?
    var onTranslate: ((String) -> Void)?
    /// While the question card is open, the words go into its field instead of this card, and are sent
    /// as a follow-up at the end; opening this card would take the keyboard and close that one.
    var questionOpen: (() -> Bool)?
    var questionDraft: (() -> String)?
    var onDraft: ((String) -> Void)?
    private var dictating = false
    /// What was already typed in the question field; the words go after it.
    private var typed = ""
    /// The recognizer gets this long to settle the last words before the text so far is used.
    private static let finishTimeout: Duration = .seconds(5)

    init(pet: PetController) {
        self.pet = pet
        var close: () -> Void = {}
        var ask: () -> Void = {}
        var translate: () -> Void = {}
        var copy: () -> Void = {}
        panel = ListenPanel(content: ListenView(model: model, onClose: { close() }, onAsk: { ask() },
                                                onTranslate: { translate() }, onCopy: { copy() }),
                            keyboard: true)
        close = { [weak self] in self?.panel.close() }
        ask = { [weak self] in self?.handOff { self?.onAsk?($0) } }
        translate = { [weak self] in self?.handOff { self?.onTranslate?($0) } }
        copy = { [weak self] in
            guard let self, !text.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            panel.close()
            pet.react(.hop)
        }
        model.onLayout = { [weak self] in
            DispatchQueue.main.async { self?.panel.refit() }
        }
        panel.onClose = { [weak self] in self?.stop() }
    }

    private var text: String { model.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// ⌃⌥L: start hands-free, or finish the take in progress.
    func toggle() {
        if model.isActive { end() } else { begin(handsFree: true) }
    }

    /// Returns whether the press is a hold for listening: a new take, or one in progress that letting go
    /// will end. At home it isn't, and the press stays a click.
    @discardableResult
    func begin(handsFree: Bool) -> Bool {
        if model.isActive { return true }
        guard pet.config.listening, !pet.config.isHome else { return false }
        take += 1
        let current = take
        let speech = SpeechListener()
        self.speech = speech
        stopWhenStarted = false
        model.text = ""
        model.handsFree = handsFree
        model.language = pet.config.spokenLanguage
        model.phase = .starting
        dictating = questionOpen?() ?? false
        typed = dictating ? questionDraft?().trimmingCharacters(in: .whitespacesAndNewlines) ?? "" : ""
        if !dictating { panel.show(from: pet.anchorView, animated: false) }
        pet.setListening(.quiet)
        speech.onText = { [weak self] text in
            guard let self, take == current else { return }
            model.text = text
            if dictating { onDraft?(afterTyped(text)) }
        }
        speech.onDownloading = { [weak self] on in
            guard let self, take == current else { return }
            if on { model.phase = .downloading } else if model.phase == .downloading { model.phase = .starting }
        }
        speech.onLevel = { [weak self] level in self?.heard(level, take: current) }
        let locale = Locale(identifier: model.language)
        Task { @MainActor [weak self] in
            do throws(SpeechListener.Failure) {
                try await speech.start(locale: locale)
            } catch {
                self?.failed(error, take: current)
                return
            }
            guard let self, take == current else {
                // Closed while starting: the mic must not stay on.
                await speech.cancel()
                return
            }
            started(take: current)
        }
        return true
    }

    /// Let go, ⌃⌥L again, or a long enough pause: wait for the last words, then show the text.
    func end() {
        switch model.phase {
        case .starting, .downloading:
            stopWhenStarted = true
        case .listening:
            finish(take: take)
        default:
            break
        }
    }

    /// Another card opened, the pet was dragged, or this card closed: drop the take and turn the mic off.
    func stop() {
        if panel.isShown { panel.close() }
        let wasActive = model.isActive
        take += 1
        stopTicker()
        clock = nil
        dictating = false
        model.phase = .idle
        model.text = ""
        let speech = self.speech
        self.speech = nil
        if wasActive {
            Task { await speech?.cancel() }
            pet.setListening(nil, nod: false)
        }
    }

    private func started(take current: Int) {
        model.phase = .listening
        clock = ListenClock(started: Date(), handsFree: model.handsFree)
        if stopWhenStarted { return finish(take: current) }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Dictating into the question card: closing that card ends the take too.
                if self.dictating, !(self.questionOpen?() ?? false) { return self.stop() }
                guard let clock = self.clock, clock.shouldStop(at: Date()) else { return }
                self.finish(take: current)
            }
        }
    }

    private func heard(_ level: Float, take current: Int) {
        guard take == current, model.phase == .listening, var clock else { return }
        let quiet = clock.update(level: level, at: Date())
        self.clock = clock
        pet.setListening(quiet ? .quiet : .sound)
    }

    private func finish(take current: Int) {
        guard take == current, model.phase == .listening, let speech else { return }
        stopTicker()
        model.phase = .finishing
        Task { @MainActor [weak self] in
            let heard = await speech.finish()
            self?.complete(take: current, heard: heard)
        }
        // A recognizer that never settles doesn't keep the pet listening: the text so far is used.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.finishTimeout)
            guard let self, take == current, model.phase == .finishing else { return }
            await speech.cancel()
            complete(take: current, heard: "")
        }
    }

    private func complete(take current: Int, heard: String) {
        guard take == current, model.phase == .finishing else { return }
        speech = nil
        if !heard.isEmpty { model.text = heard }
        let text = self.text
        if dictating {
            dictating = false
            model.phase = .idle
            model.text = ""
            pet.setListening(nil, nod: !text.isEmpty)
            if text.isEmpty { pet.react(.shakeHead) } else { onAsk?(afterTyped(text)) }
            return
        }
        if text.isEmpty {
            model.phase = .nothingHeard
            pet.setListening(nil, nod: false)
            pet.react(.shakeHead)
        } else {
            model.phase = .done
            pet.setListening(nil)
        }
    }

    private func afterTyped(_ words: String) -> String {
        typed.isEmpty ? words : typed + " " + words
    }

    private func failed(_ error: SpeechListener.Failure, take current: Int) {
        guard take == current else { return }
        speech = nil
        // The reason needs this card, even over the question card.
        if dictating {
            dictating = false
            panel.show(from: pet.anchorView, animated: false)
        }
        switch error {
        case .noPermission: model.phase = .needsPermission
        case .noMic: model.phase = .noMic
        case .unsupportedLanguage: model.phase = .unsupported
        case .failed(let message): model.phase = .failed(L("Couldn't listen: \(message)", "Не получилось слушать: \(message)"))
        }
        pet.setListening(nil, nod: false)
        pet.react(.shakeHead)
    }

    /// The text goes on to the next card; this one closes.
    private func handOff(_ next: (String) -> Void) {
        let text = self.text
        guard !text.isEmpty else { return }
        panel.close()
        next(text)
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

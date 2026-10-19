import AppKit
import Observation
import PetCore
import SwiftUI

/// Settings mirror the config; every change goes straight back to the pet and is saved.
@MainActor
@Observable
final class SettingsModel {
    @ObservationIgnored private let pet: PetController
    @ObservationIgnored let hooks: HookInstaller

    var scale = 4 { didSet { if !loading, scale != oldValue { pet.setScale(scale) } } }
    var doNotDisturb = false {
        didSet {
            guard !loading, doNotDisturb != oldValue else { return }
            pet.setDoNotDisturb(doNotDisturb)
            // The pet may refuse (e.g. while being dragged); show what actually happened.
            if pet.doNotDisturb != doNotDisturb { refresh() }
        }
    }
    var desktopReactions = true { didSet { update { $0.desktopReactions = desktopReactions } } }
    var sleepAfterMinutes = 10 { didSet { update { $0.sleepAfterMinutes = sleepAfterMinutes } } }
    var nativeLanguage = "ru" { didSet { update { $0.nativeLanguage = nativeLanguage } } }
    var foreignLanguage = "en" { didSet { update { $0.foreignLanguage = foreignLanguage } } }
    var askModel = "haiku" { didSet { update { $0.askModel = askModel } } }
    var skin = "lavender" { didSet { if !loading, skin != oldValue { pet.setLook(skin: skin, accessory: accessory) } } }
    var accessory = "none" { didSet { if !loading, accessory != oldValue { pet.setLook(skin: skin, accessory: accessory) } } }
    var logEvents = false { didSet { if !loading, logEvents != oldValue { pet.setLogEvents(logEvents) } } }
    var watchCodex = true {
        didSet {
            guard !loading, watchCodex != oldValue else { return }
            update { $0.watchCodex = watchCodex }
            onWatchCodex?(watchCodex)
        }
    }
    @ObservationIgnored var onWatchCodex: ((Bool) -> Void)?
    var launchAtLogin = false
    var hooksConnected = false
    var statusLine = HookSettings.StatusLineState.absent
    var accessibility = false
    var message: String?
    @ObservationIgnored private var loading = false

    init(pet: PetController, hooks: HookInstaller) {
        self.pet = pet
        self.hooks = hooks
        refresh()
    }

    /// Re-reads the config and system state (window shown, app focused, permission granted elsewhere).
    func refresh() {
        loading = true
        defer { loading = false }
        let c = pet.config
        scale = c.scale
        doNotDisturb = c.doNotDisturb
        desktopReactions = c.desktopReactions
        sleepAfterMinutes = c.sleepAfterMinutes
        nativeLanguage = c.nativeLanguage
        foreignLanguage = c.foreignLanguage
        askModel = c.askModel
        skin = c.skin
        accessory = c.accessory
        logEvents = c.logEvents
        watchCodex = c.watchCodex
        launchAtLogin = LaunchAtLogin.isEnabled
        hooksConnected = hooks.isInstalled
        statusLine = hooks.statusLineState
        accessibility = SelectionReader.isTrusted
        message = nil
    }

    /// The cheap check worth polling while a window is open: permissions change in System Settings.
    func refreshAccessibility() {
        let trusted = SelectionReader.isTrusted
        if trusted != accessibility { accessibility = trusted }
    }

    func setLaunchAtLogin(_ on: Bool) {
        message = LaunchAtLogin.set(on)
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func toggleHooks() {
        if hooksConnected {
            HookActions.disconnect(hooks)
        } else {
            HookActions.connect(hooks)
        }
        refresh()
    }

    func addStatusLine() {
        HookActions.addStatusLine(hooks)
        refresh()
    }

    func requestAccessibility() {
        SelectionReader.requestPermission()
    }

    private func update(_ change: (inout PetConfig) -> Void) {
        guard !loading else { return }
        pet.updateConfig(change)
    }
}

enum Choices {
    static let languages: [(code: String, name: String)] = [
        ("ru", "Русский"), ("en", "English"), ("uk", "Українська"), ("de", "Deutsch"), ("fr", "Français"),
        ("es", "Español"), ("it", "Italiano"), ("pt", "Português"), ("pl", "Polski"), ("tr", "Türkçe"),
        ("zh", "中文"), ("ja", "日本語"), ("ko", "한국어"),
    ]
    static let models = ["haiku", "sonnet", "opus"]
    static let skins: [(name: String, title: String)] = [
        ("lavender", "Лавандовый"), ("mint", "Мятный"), ("peach", "Персиковый"), ("mono", "Графитовый"),
    ]
    static let accessories: [(name: String, title: String)] = [
        ("none", "Без аксессуара"), ("glasses", "Очки"), ("headphones", "Наушники"), ("cap", "Кепка"),
    ]
    static let sleep: [(minutes: Int, title: String)] = [
        (0, "никогда"), (5, "через 5 мин"), (10, "через 10 мин"), (15, "через 15 мин"), (30, "через 30 мин"), (60, "через час"),
    ]
}

struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section("Кубик") {
                Picker("Размер", selection: $model.scale) {
                    ForEach(Array(PetConfig.scaleRange), id: \.self) { Text("×\($0)").tag($0) }
                }
                Picker("Цвет", selection: $model.skin) {
                    ForEach(Choices.skins, id: \.name) { Text($0.title).tag($0.name) }
                }
                Picker("Аксессуар", selection: $model.accessory) {
                    ForEach(Choices.accessories, id: \.name) { Text($0.title).tag($0.name) }
                }
                Toggle("Не беспокоить (⌃⌥P)", isOn: $model.doNotDisturb)
                Toggle("Реагировать на рабочий стол", isOn: $model.desktopReactions)
                    .help("Глаза за курсором, взгляд на новое окно, полупрозрачность над полноэкранными приложениями")
                Picker("Засыпать без активности", selection: $model.sleepAfterMinutes) {
                    ForEach(Choices.sleep, id: \.minutes) { Text($0.title).tag($0.minutes) }
                }
                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            }
            Section("Claude Code") {
                LabeledContent("Хуки") {
                    HStack {
                        StatusDot(ok: model.hooksConnected)
                        Text(model.hooksConnected ? "подключены" : "не подключены").foregroundStyle(.secondary)
                        Button(model.hooksConnected ? "Отключить" : "Подключить…") { model.toggleHooks() }
                    }
                }
                LabeledContent("Statusline в терминале") {
                    HStack {
                        switch model.statusLine {
                        case .ours:
                            StatusDot(ok: true)
                            Text("кубика").foregroundStyle(.secondary)
                        case .foreign:
                            StatusDot(ok: true)
                            Text("ваша, не трогаю").foregroundStyle(.secondary)
                        case .absent:
                            StatusDot(ok: false)
                            Text("нет").foregroundStyle(.secondary)
                            if model.hooksConnected { Button("Добавить") { model.addStatusLine() } }
                        }
                    }
                }
                Picker("Модель для вопросов (⌃⌥K)", selection: $model.askModel) {
                    ForEach(Choices.models, id: \.self) { Text($0).tag($0) }
                }
                Toggle("Журнал событий (~/.pixelpet/events.log)", isOn: $model.logEvents)
                    .help("Только id сессий, проекты и имена событий, без текстов")
            }
            Section("Codex") {
                Toggle("Следить за агентами Codex", isOn: $model.watchCodex)
                    .help("Читает ~/.codex/sessions: кубики Codex слева, лимиты Codex в панели. Ничего не устанавливает")
            }
            Section("Перевод (⌃⌥T)") {
                Picker("Мой язык", selection: $model.nativeLanguage) {
                    ForEach(Choices.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                Picker("Переводить мой язык на", selection: $model.foreignLanguage) {
                    ForEach(Choices.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                LabeledContent("Доступ к выделенному тексту") {
                    HStack {
                        StatusDot(ok: model.accessibility)
                        Text(model.accessibility ? "есть" : "нет").foregroundStyle(.secondary)
                        if !model.accessibility { Button("Разрешить…") { model.requestAccessibility() } }
                    }
                }
            }
            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct StatusDot: View {
    let ok: Bool
    var body: some View {
        Circle().fill(ok ? Color(red: 0.11, green: 0.62, blue: 0.46) : Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
    }
}

/// A regular titled window that brings the accessory app forward while it's open.
@MainActor
final class AppWindow<Content: View>: NSObject, NSWindowDelegate {
    let window: NSWindow
    var onKey: (() -> Void)?
    var onPoll: (() -> Void)?
    var onClose: (() -> Void)?
    private var timer: Timer?
    private var lastRefresh = Date.distantPast

    init(title: String, content: Content) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
                          styleMask: [.titled, .closable], backing: .buffered, defer: true)
        super.init()
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.delegate = self
    }

    func show() {
        refresh()
        window.setContentSize(window.contentView?.fittingSize ?? window.frame.size)
        if !window.isVisible { window.center() }
        // Activation is only a request for a background app; float the window above others until the
        // user focuses it, so a welcome shown at launch isn't buried under the frontmost app.
        window.level = .floating
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        timer?.invalidate()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onPoll?() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func close() { window.close() }

    func windowDidBecomeKey(_ notification: Notification) {
        window.level = .normal
        refresh()
    }

    /// Full refresh (reads settings.json, login items) at most once a second.
    private func refresh() {
        guard Date().timeIntervalSince(lastRefresh) > 1 else { return }
        lastRefresh = Date()
        onKey?()
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        onClose?()
    }
}

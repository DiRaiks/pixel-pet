import AppKit
import Observation
import PetCore
import PetSprites
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
    var uiLanguage = UILanguage.en {
        didSet {
            guard !loading, uiLanguage != oldValue else { return }
            Loc.shared.language = uiLanguage
            update { $0.uiLanguage = uiLanguage.rawValue }
            onLanguage?()
        }
    }
    /// The language changed: windows and menus built in AppKit retitle themselves.
    @ObservationIgnored var onLanguage: (() -> Void)?
    var nativeLanguage = "ru" { didSet { update { $0.nativeLanguage = nativeLanguage } } }
    var foreignLanguage = "en" { didSet { update { $0.foreignLanguage = foreignLanguage } } }
    var askModel = "haiku" { didSet { update { $0.askModel = askModel } } }
    var figure = "cube" { didSet { if !loading, figure != oldValue { applyLook() } } }
    var skin = "lavender" { didSet { if !loading, skin != oldValue { applyLook() } } }
    var accessory = "none" { didSet { if !loading, accessory != oldValue { applyLook() } } }
    private func applyLook() { pet.setLook(skin: skin, accessory: accessory, figure: figure) }
    var logEvents = false { didSet { if !loading, logEvents != oldValue { pet.setLogEvents(logEvents) } } }
    var watchCodex = true {
        didSet {
            guard !loading, watchCodex != oldValue else { return }
            update { $0.watchCodex = watchCodex }
            onWatchCodex?(watchCodex)
        }
    }
    @ObservationIgnored var onWatchCodex: ((Bool) -> Void)?
    var hookah = true { didSet { update { $0.hookah = hookah } } }
    var meetingAlerts = false {
        didSet {
            guard !loading, meetingAlerts != oldValue else { return }
            update { $0.meetingAlerts = meetingAlerts }
            onMeetingAlerts?(meetingAlerts)
        }
    }
    @ObservationIgnored var onMeetingAlerts: ((Bool) -> Void)?
    /// Calendar access and how many calendars are visible, for the settings row.
    var calendarAccess = MeetingMonitor.Access.notAsked
    var calendarCount = 0
    @ObservationIgnored var calendarCountProvider: (() -> Int)?
    /// Settings opened or refocused: let the calendar monitor look at the permission again.
    @ObservationIgnored var onRefresh: (() -> Void)?
    @ObservationIgnored var onRequestCalendar: (() -> Void)?
    var touchHint = true {
        didSet {
            guard !loading, touchHint != oldValue else { return }
            update { $0.touchHint = touchHint }
            onTouchHint?(touchHint)
        }
    }
    @ObservationIgnored var onTouchHint: ((Bool) -> Void)?
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
        uiLanguage = UILanguage(rawValue: c.uiLanguage) ?? .en
        nativeLanguage = c.nativeLanguage
        foreignLanguage = c.foreignLanguage
        askModel = c.askModel
        figure = c.figure
        skin = c.skin
        accessory = c.accessory
        logEvents = c.logEvents
        watchCodex = c.watchCodex
        touchHint = c.touchHint
        hookah = c.hookah
        meetingAlerts = c.meetingAlerts
        onRefresh?()
        calendarAccess = MeetingMonitor.access
        calendarCount = calendarCountProvider?() ?? 0
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
    @MainActor static var figures: [(name: String, title: String)] {
        [(Figure.cube.rawValue, L("Cube", "Кубик")), (Figure.lidman.rawValue, "LM")]
    }
    @MainActor static var skins: [(name: String, title: String)] {
        [
            ("lavender", L("Lavender", "Лавандовый")), ("mint", L("Mint", "Мятный")), ("peach", L("Peach", "Персиковый")),
            ("mono", L("Graphite", "Графитовый")), ("sky", L("Sky", "Небесный")), ("sakura", L("Sakura", "Сакура")),
            ("vanilla", L("Vanilla", "Ваниль")), ("night", L("Night", "Ночной")),
            (Look.daily, L("New every day", "Каждый день новый")),
        ]
    }
    @MainActor static var accessories: [(name: String, title: String)] {
        [
            ("none", L("None", "Без аксессуара")), ("glasses", L("Glasses", "Очки")),
            ("sunglasses", L("Sunglasses", "Солнечные очки")), ("headphones", L("Headphones", "Наушники")),
            ("cap", L("Cap", "Кепка")), ("beanie", L("Beanie", "Шапка-бини")), ("crown", L("Crown", "Корона")),
            ("bow", L("Bow", "Бантик")), ("flower", L("Flower", "Цветок")),
            ("propeller", L("Propeller hat", "Шапка с пропеллером")), ("scarf", L("Scarf", "Шарф")),
            ("mustache", L("Mustache", "Усы")),
            (Look.daily, L("New every day", "Каждый день новый")),
        ]
    }
    @MainActor static var sleep: [(minutes: Int, title: String)] {
        [
            (0, L("never", "никогда")), (5, L("5 min", "через 5 мин")), (10, L("10 min", "через 10 мин")),
            (15, L("15 min", "через 15 мин")), (30, L("30 min", "через 30 мин")), (60, L("1 hour", "через час")),
        ]
    }
}

struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section(L("Pet", "Кубик")) {
                Picker("Language / Язык", selection: $model.uiLanguage) {
                    ForEach(UILanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker(L("Size", "Размер"), selection: $model.scale) {
                    ForEach(Array(PetConfig.scaleRange), id: \.self) { Text("×\($0)").tag($0) }
                }
                Picker(L("Character", "Персонаж"), selection: $model.figure) {
                    ForEach(Choices.figures, id: \.name) { Text($0.title).tag($0.name) }
                }
                // LM keeps his own colors and wears nothing on his diamond.
                Group {
                    Picker(L("Color", "Цвет"), selection: $model.skin) {
                        ForEach(Choices.skins, id: \.name) { Text($0.title).tag($0.name) }
                    }
                    Picker(L("Accessory", "Аксессуар"), selection: $model.accessory) {
                        ForEach(Choices.accessories, id: \.name) { Text($0.title).tag($0.name) }
                    }
                }
                .disabled(model.figure == Figure.lidman.rawValue)
                Toggle(L("Do not disturb (⌃⌥P)", "Не беспокоить (⌃⌥P)"), isOn: $model.doNotDisturb)
                Toggle(L("Desktop reactions", "Реагировать на рабочий стол"), isOn: $model.desktopReactions)
                    .help(L("Eyes follow the cursor, glances at the window you switch to, fades over fullscreen apps",
                             "Глаза за курсором, взгляд на новое окно, полупрозрачность над полноэкранными приложениями"))
                Toggle(L("Hookah breaks", "Кальян на перерывах"), isOn: $model.hookah)
                    .help(L("Now and then, when idle or after a big task, the cube smokes a hookah",
                             "Иногда в покое и после больших задач кубик курит кальян"))
                Picker(L("Fall asleep after", "Засыпать без активности"), selection: $model.sleepAfterMinutes) {
                    ForEach(Choices.sleep, id: \.minutes) { Text($0.title).tag($0.minutes) }
                }
                Toggle(L("Launch at login", "Запускать при входе в систему"), isOn: Binding(
                    get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            }
            Section("Claude Code") {
                LabeledContent(L("Hooks", "Хуки")) {
                    HStack {
                        StatusDot(ok: model.hooksConnected)
                        Text(model.hooksConnected ? L("connected", "подключены") : L("not connected", "не подключены")).foregroundStyle(.secondary)
                        Button(model.hooksConnected ? L("Disconnect", "Отключить") : L("Connect…", "Подключить…")) { model.toggleHooks() }
                    }
                }
                LabeledContent(L("Terminal statusline", "Statusline в терминале")) {
                    HStack {
                        switch model.statusLine {
                        case .ours:
                            StatusDot(ok: true)
                            Text(L("the cube's", "кубика")).foregroundStyle(.secondary)
                        case .foreign:
                            StatusDot(ok: true)
                            Text(L("yours, left as is", "ваша, не трогаю")).foregroundStyle(.secondary)
                        case .absent:
                            StatusDot(ok: false)
                            Text(L("none", "нет")).foregroundStyle(.secondary)
                            if model.hooksConnected { Button(L("Add", "Добавить")) { model.addStatusLine() } }
                        }
                    }
                }
                Picker(L("Model for questions (⌃⌥K)", "Модель для вопросов (⌃⌥K)"), selection: $model.askModel) {
                    ForEach(Choices.models, id: \.self) { Text($0).tag($0) }
                }
                Toggle(L("Event log (~/.pixelpet/events.log)", "Журнал событий (~/.pixelpet/events.log)"), isOn: $model.logEvents)
                    .help(L("Only session ids, projects and event names, no text", "Только id сессий, проекты и имена событий, без текстов"))
            }
            Section(L("Calls", "Звонки")) {
                Toggle(L("Remind about calls", "Напоминать о звонках"), isOn: $model.meetingAlerts)
                    .help(L("5 minutes before a meeting with a call link the cube puts on a headset, and an alarm rings in the last minute",
                             "За 5 минут до встречи со ссылкой на звонок кубик надевает гарнитуру, в последнюю минуту звенит будильник"))
                if model.meetingAlerts {
                    LabeledContent(L("Calendars", "Календари")) {
                        HStack {
                            switch model.calendarAccess {
                            case .granted:
                                StatusDot(ok: model.calendarCount > 0)
                                Text(model.calendarCount > 0
                                     ? L("visible: \(model.calendarCount)", "видно: \(model.calendarCount)")
                                     : L("none: add an account in Internet Accounts", "ни одного: добавьте аккаунт в «Учётных записях интернета»"))
                                    .foregroundStyle(.secondary)
                            case .denied:
                                StatusDot(ok: false)
                                Text(L("no access", "нет доступа")).foregroundStyle(.secondary)
                                Button(L("Open Settings…", "Открыть настройки…")) { MeetingMonitor.openPrivacySettings() }
                            case .limited:
                                StatusDot(ok: false)
                                Text(L("limited access: full access needed", "доступ ограничен: нужен полный")).foregroundStyle(.secondary)
                                Button(L("Open Settings…", "Открыть настройки…")) { MeetingMonitor.openPrivacySettings() }
                            case .notAsked:
                                Text(L("no access", "нет доступа")).foregroundStyle(.secondary)
                                Button(L("Allow…", "Разрешить…")) { model.onRequestCalendar?() }
                            }
                        }
                    }
                }
            }
            Section("YubiKey") {
                Toggle(L("Show when the key waits for a touch", "Подсказывать касание ключа"), isOn: $model.touchHint)
                    .help(L("When the key waits for a touch to sign with GPG, the cube takes it out and shows it. Reads only that system log message",
                             "Когда ключ ждёт касания для GPG-подписи, кубик достаёт его и показывает. Читает только это сообщение системного журнала"))
            }
            Section("Codex") {
                Toggle(L("Follow Codex agents", "Следить за агентами Codex"), isOn: $model.watchCodex)
                    .help(L("Reads ~/.codex/sessions: Codex cubes on the left, Codex limits in the panel. Installs nothing",
                             "Читает ~/.codex/sessions: кубики Codex слева, лимиты Codex в панели. Ничего не устанавливает"))
            }
            Section(L("Translation (⌃⌥T)", "Перевод (⌃⌥T)")) {
                Picker(L("My language", "Мой язык"), selection: $model.nativeLanguage) {
                    ForEach(Choices.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                Picker(L("Translate my language into", "Переводить мой язык на"), selection: $model.foreignLanguage) {
                    ForEach(Choices.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                LabeledContent(L("Access to selected text", "Доступ к выделенному тексту")) {
                    HStack {
                        StatusDot(ok: model.accessibility)
                        Text(model.accessibility ? L("granted", "есть") : L("none", "нет")).foregroundStyle(.secondary)
                        if !model.accessibility { Button(L("Allow…", "Разрешить…")) { model.requestAccessibility() } }
                    }
                }
            }
            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        // Not pinned to its full height: the window caps it to the screen and the form scrolls.
        .frame(width: 480)
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

    /// Measures how tall the content wants to be, laid out at its full height.
    private let measure: NSHostingView<AnyView>

    init(title: String, content: Content) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        measure = NSHostingView(rootView: AnyView(content.fixedSize(horizontal: false, vertical: true)))
        super.init()
        window.title = title
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: content)
        // The window decides the height; the content scrolls inside it when it's taller.
        host.sizingOptions = []
        window.contentView = host
        window.delegate = self
    }

    func show() {
        refresh()
        // As tall as the content wants, but never beyond the screen (minus a margin); width stays fixed.
        let wanted = measure.fittingSize
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let height = min(wanted.height, (screen * 0.9).rounded())
        window.setContentSize(NSSize(width: wanted.width, height: height))
        window.contentMinSize = NSSize(width: wanted.width, height: min(height, 320))
        window.contentMaxSize = NSSize(width: wanted.width, height: wanted.height)
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

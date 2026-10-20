import AppKit
import Carbon
import PetCore
import PetIntegrations
import PetSprites

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pet: PetController?
    private var agents: AgentMonitor?
    private var menu: StatusMenu?
    private var panel: StatusPanel?
    private var hotKeys: [HotKey] = []
    private var translator: Translator?
    private var asker: Asker?
    private var desktop: DesktopSensor?
    private var settings: AppWindow<SettingsView>?
    private var welcome: AppWindow<OnboardingView>?
    private var touch: TouchWatcher?
    private var power: PowerMonitor?
    private var meetings: MeetingMonitor?
    private var mac: MacMonitor?
    private var settingsModel: SettingsModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let exportArgs = CommandLine.arguments
        if let i = exportArgs.firstIndex(of: "--export-sprites"), i + 1 < exportArgs.count {
            let skin = i + 2 < exportArgs.count ? Skin.named(exportArgs[i + 2]) : .lavender
            let accessory = i + 3 < exportArgs.count ? Accessory(rawValue: exportArgs[i + 3]) ?? .none : .none
            let figure: Figure = i + 2 < exportArgs.count && exportArgs[i + 2] == Figure.lidman.rawValue ? .lidman : .cube
            SpriteExport.run(to: URL(fileURLWithPath: exportArgs[i + 1]), look: Look(skin: skin, accessory: accessory, figure: figure))
            NSApp.terminate(nil)
            return
        }
        if let i = exportArgs.firstIndex(of: "--export-work"), i + 1 < exportArgs.count {
            ReadmeExport.work(to: URL(fileURLWithPath: exportArgs[i + 1]))
            NSApp.terminate(nil)
            return
        }
        if let i = exportArgs.firstIndex(of: "--export-readme"), i + 1 < exportArgs.count {
            ReadmeExport.run(to: URL(fileURLWithPath: exportArgs[i + 1]))
            NSApp.terminate(nil)
            return
        }
        // One pet at a time: a second copy would fight over the socket and the screen.
        let me = NSRunningApplication.current
        if NSRunningApplication.runningApplications(withBundleIdentifier: me.bundleIdentifier ?? "")
            .contains(where: { $0 != me && !$0.isTerminated }) {
            NSApp.terminate(nil)
            return
        }
        NSApp.mainMenu = Self.editMenu()
        // Leftover quick-ask sessions from a previous run.
        AskSessions.removeAll()
        let hooks = HookInstaller()
        do {
            try hooks.upgradeIfOlderInstall()
        } catch {
            NSLog("PixelPet: failed to add new hook events: \(error.localizedDescription)")
        }
        do {
            try hooks.refreshScriptIfInstalled()
        } catch {
            NSLog("PixelPet: failed to refresh hook script: \(error.localizedDescription)")
        }
        let store = ConfigStore()
        Loc.shared.language = UILanguage(rawValue: store.load().uiLanguage) ?? .en
        // Sprites are drawn once, straight in the saved look.
        let pet = PetController(store: store, sprites: SpriteLibrary(look: PetController.look(from: store.load())))
        let agents = AgentMonitor(pet: pet, hooks: hooks)
        let panel = StatusPanel(model: agents.status)
        let menu = StatusMenu(pet: pet, hooks: hooks)
        agents.onChange = { [weak menu] active, limits, codexLimits in
            menu?.update(active: active, limits: limits, codexLimits: codexLimits)
            DispatchQueue.main.async { panel.refit() }
        }
        let showPanel = { [weak agents, weak pet] in
            guard let agents, let pet, !pet.isHidden else { return }
            if !panel.isShown { agents.panelWillShow() }
            panel.toggle(from: pet.anchorView)
        }
        pet.onTap = showPanel

        menu.onShowPanel = showPanel
        self.panel = panel
        let translator = Translator(pet: pet)
        translator.onLimits = { [weak agents] in agents?.absorb($0) }
        self.translator = translator
        let asker = Asker(pet: pet)
        asker.onLimits = { [weak agents] in agents?.absorb($0) }
        self.asker = asker
        // Only one card at a time.
        translator.panel.onShow = { [weak panel, weak asker] in
            panel?.close()
            asker?.panel.close()
        }
        asker.panel.onShow = { [weak panel, weak translator] in
            panel?.close()
            translator?.panel.close()
        }
        let statusShow = panel.onShow
        panel.onShow = { [weak translator, weak asker] in
            translator?.panel.close()
            asker?.panel.close()
            statusShow?()
        }
        menu.onAsk = { [weak asker] in asker?.toggle() }
        menu.onTranslate = { [weak translator] in translator?.translateSelection() }
        pet.isCardOpen = { [weak panel, weak translator, weak asker] in
            (panel?.isShown ?? false) || (translator?.panel.isShown ?? false) || (asker?.panel.isShown ?? false)
        }
        pet.onDragStart = { [weak translator, weak asker] in
            panel.close()
            translator?.panel.close()
            asker?.panel.close()
        }
        // ⌃⌥P: do not disturb (home, quiet). ⌃⌥T: translate the selection. ⌃⌥K: ask Claude.
        // Shown next to the menu items too.
        hotKeys = [
            HotKey(keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey, id: 1) { [weak menu] in menu?.toggleDND() },
            HotKey(keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey, id: 2) { [weak translator] in
                translator?.translateSelection()
            },
            HotKey(keyCode: kVK_ANSI_K, modifiers: controlKey | optionKey, id: 3) { [weak asker] in asker?.toggle() },
        ]
        // Debug aid: `open PixelPet.app --args --show-panel` opens the panel once limits had time to load.
        if let i = CommandLine.arguments.firstIndex(of: "--translate-text"), i + 1 < CommandLine.arguments.count {
            let text = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { translator.translate(text) }
            if CommandLine.arguments.contains("--with-claude") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { translator.translateWithClaude() }
            }
        }
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--ask"), i + 1 < args.count {
            let question = args[i + 1]
            let followUp = args.firstIndex(of: "--ask-followup").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { asker.ask(question) }
            if let followUp {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    while asker.model.conversation.isStreaming { try? await Task.sleep(for: .milliseconds(200)) }
                    asker.ask(followUp)
                }
            }
        }
        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { showPanel() }
        }
        pet.contextMenu = menu.menu
        self.pet = pet
        self.agents = agents
        self.menu = menu
        pet.start()
        agents.start()
        let settingsModel = SettingsModel(pet: pet, hooks: hooks)
        self.settingsModel = settingsModel
        settingsModel.onWatchCodex = { [weak agents] on in agents?.setWatchingCodex(on) }
        let settings = AppWindow(title: L("Pixel Pet Settings", "Pixel Pet — настройки"), content: SettingsView(model: settingsModel))
        settings.onKey = { settingsModel.refresh() }
        settings.onPoll = { settingsModel.refreshAccessibility() }
        var openSettings: () -> Void = {}
        var finishWelcome: () -> Void = {}
        let welcome = AppWindow(title: "Pixel Pet", content: OnboardingView(
            model: settingsModel, onSettings: { openSettings() }, onDone: { finishWelcome() }))
        welcome.onKey = { settingsModel.refresh() }
        welcome.onPoll = { settingsModel.refreshAccessibility() }
        // Seen once is enough, however the window was closed.
        welcome.onClose = { [weak pet] in
            guard let pet, !pet.config.onboarded else { return }
            pet.updateConfig { $0.onboarded = true }
        }
        openSettings = { [weak settings] in settings?.show() }
        finishWelcome = { [weak welcome] in welcome?.close() }
        menu.onSettings = { [weak settings] in settings?.show() }
        menu.onWelcome = { [weak welcome] in welcome?.show() }
        self.settings = settings
        self.welcome = welcome
        // The welcome window's title is just the app name, the same in every language.
        settingsModel.onLanguage = { [weak settings] in
            settings?.window.title = L("Pixel Pet Settings", "Pixel Pet — настройки")
        }
        if CommandLine.arguments.contains("--show-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak settings] in settings?.show() }
        }
        if !pet.config.onboarded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak welcome] in welcome?.show() }
        }
        let power = PowerMonitor { [weak pet] reading in pet?.setPower(reading) }
        power.start()
        self.power = power
        // The Mac around the pet: headphones, music, mic and camera, heat, power, network, screenshots, theme.
        let mac = MacMonitor()
        mac.onChange = { [weak pet] state, animate in pet?.setMac(state, animate: animate) }
        mac.onScreenshot = { [weak pet] in pet?.screenshotTaken() }
        mac.onTheme = { [weak pet] dark in pet?.themeChanged(dark: dark) }
        mac.setRunning(pet.config.macReactions)
        self.mac = mac
        settingsModel.onMacReactions = { [weak mac, weak pet] on in
            mac?.setRunning(on)
            pet?.macReactionsChanged()
        }
        settingsModel.calendarCountProvider = { [weak self] in self?.meetings?.calendarCount ?? 0 }
        settingsModel.onMeetingAlerts = { [weak self, weak settingsModel] on in
            self?.setMeetingAlerts(on, askForAccess: true)
            settingsModel?.refresh()
        }
        settingsModel.onRefresh = { [weak self] in self?.meetings?.reload() }
        settingsModel.onRequestCalendar = { [weak self] in self?.meetings?.requestAccess() }
        setMeetingAlerts(pet.config.meetingAlerts, askForAccess: false)
        setTouchHint(pet.config.touchHint)
        settingsModel.onTouchHint = { [weak self] on in self?.setTouchHint(on) }
        let desktop = DesktopSensor(pet: pet)
        pet.onPlacementChange = { [weak desktop] in desktop?.reconfigure() }
        desktop.start()
        self.desktop = desktop
    }

    /// Calendar reminders on or off; turning them on asks for calendar access the first time.
    private func setMeetingAlerts(_ on: Bool, askForAccess: Bool) {
        guard on != (meetings != nil), let pet else { return }
        if on {
            let monitor = MeetingMonitor()
            monitor.onPhase = { [weak pet] phase in pet?.setMeetingPhase(phase) }
            monitor.onUpcoming = { [weak self] meeting in self?.agents?.status.nextMeeting = meeting }
            monitor.onAccessChange = { [weak self] in self?.settingsModel?.refresh() }
            pet.onDismissMeeting = { [weak monitor] in monitor?.dismissCurrent() }
            meetings = monitor
            monitor.start(askForAccess: askForAccess)
        } else {
            meetings?.stop()
            meetings = nil
            pet.onDismissMeeting = nil
        }
    }

    /// Follow the system log for a YubiKey waiting for a touch, or stop.
    private func setTouchHint(_ on: Bool) {
        guard on != (touch != nil), let pet else { return }
        if on {
            let watcher = TouchWatcher { [weak pet] at in
                DispatchQueue.main.async { MainActor.assumeIsolated { pet?.keySignal(at: at) } }
            }
            watcher.start()
            touch = watcher
        } else {
            touch?.stop()
            touch = nil
            pet.clearTouch()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        touch?.stop()
        agents?.stop()
        AskSessions.removeAll()
    }

    /// An accessory app shows no menu bar of its own, but text fields still need the standard Edit key
    /// equivalents (⌘X/⌘C/⌘V/⌘A/⌘Z), which AppKit routes through the main menu.
    private static func editMenu() -> NSMenu {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        return main
    }
}

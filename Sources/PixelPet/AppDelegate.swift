import AppKit
import Carbon
import PetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pet: PetController?
    private var agents: AgentMonitor?
    private var menu: StatusMenu?
    private var panel: StatusPanel?
    private var hotKeys: [HotKey] = []
    private var translator: Translator?
    private var asker: Asker?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            try hooks.refreshScriptIfInstalled()
        } catch {
            NSLog("PixelPet: failed to refresh hook script: \(error.localizedDescription)")
        }
        let pet = PetController(store: ConfigStore(), sprites: SpriteLibrary())
        let agents = AgentMonitor(pet: pet, hooks: hooks)
        let panel = StatusPanel(model: agents.status)
        let menu = StatusMenu(pet: pet, hooks: hooks)
        agents.onChange = { [weak menu] active, limits in
            menu?.update(active: active, limits: limits)
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
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        return main
    }
}

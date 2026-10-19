import AppKit
import PetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pet: PetController?
    private var agents: AgentMonitor?
    private var menu: StatusMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One pet at a time: a second copy would fight over the socket and the screen.
        let me = NSRunningApplication.current
        if NSRunningApplication.runningApplications(withBundleIdentifier: me.bundleIdentifier ?? "")
            .contains(where: { $0 != me && !$0.isTerminated }) {
            NSApp.terminate(nil)
            return
        }
        let hooks = HookInstaller()
        do {
            try hooks.refreshScriptIfInstalled()
        } catch {
            NSLog("PixelPet: failed to refresh hook script: \(error.localizedDescription)")
        }
        let pet = PetController(store: ConfigStore(), sprites: SpriteLibrary())
        let agents = AgentMonitor(pet: pet)
        let menu = StatusMenu(pet: pet, hooks: hooks)
        agents.onChange = { [weak menu] active in menu?.setActiveCount(active) }
        pet.contextMenu = menu.menu
        self.pet = pet
        self.agents = agents
        self.menu = menu
        pet.start()
        agents.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        agents?.stop()
    }
}

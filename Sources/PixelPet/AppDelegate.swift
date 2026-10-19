import AppKit
import PetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pet: PetController?
    private var menu: StatusMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let sprites = SpriteLibrary()
        let pet = PetController(store: ConfigStore(), sprites: sprites)
        let menu = StatusMenu(pet: pet, sprites: sprites)
        pet.contextMenu = menu.menu
        self.pet = pet
        self.menu = menu
        pet.start()
    }
}

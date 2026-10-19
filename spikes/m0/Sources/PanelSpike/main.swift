// M0 spike: transparent non-activating panel + SpriteKit at display rate, notch geometry, alpha hit-test.
import AppKit
import SpriteKit

final class PetScene: SKScene {
    var frames = 0
    var start = CACurrentMediaTime()
    let body = SKSpriteNode(color: NSColor(red: 0.5, green: 0.47, blue: 0.87, alpha: 1), size: CGSize(width: 16, height: 14))

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        scaleMode = .resizeFill
        body.texture?.filteringMode = .nearest
        body.setScale(4)
        body.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(body)
        let hop = SKAction.sequence([.moveBy(x: 0, y: 24, duration: 0.25), .moveBy(x: 0, y: -24, duration: 0.25)])
        body.run(.repeatForever(hop))
    }

    override func update(_ currentTime: TimeInterval) {
        frames += 1
        let elapsed = CACurrentMediaTime() - start
        if elapsed >= 2 {
            print(String(format: "fps=%.1f", Double(frames) / elapsed))
            frames = 0
            start = CACurrentMediaTime()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        reportScreens()
        let rect = NSRect(x: 400, y: 400, width: 160, height: 160)
        panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = SKView(frame: rect)
        view.allowsTransparency = true
        view.preferredFramesPerSecond = Int(ProcessInfo.processInfo.environment["FPS"] ?? "120") ?? 120
        view.isPaused = ProcessInfo.processInfo.environment["PAUSED"] == "1"
        panel.contentView = view
        view.presentScene(PetScene(size: rect.size))
        panel.orderFrontRegardless()
        print("panel shown, level=\(panel.level.rawValue), key=\(panel.isKeyWindow)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { NSApp.terminate(nil) }
    }

    func reportScreens() {
        for s in NSScreen.screens {
            let notch = s.safeAreaInsets.top > 0
            print("screen \(s.localizedName) frame=\(s.frame) maxFPS=\(s.maximumFramesPerSecond) safeTop=\(s.safeAreaInsets.top) notch=\(notch)")
            if let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
                let notchRect = NSRect(x: l.maxX, y: l.minY, width: r.minX - l.maxX, height: l.height)
                print("  notchRect=\(notchRect) menuBarHeight=\(s.frame.maxY - s.visibleFrame.maxY)")
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

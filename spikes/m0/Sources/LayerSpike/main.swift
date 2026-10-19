// M0 spike: CALayer sprite (frame swap on a 12 fps timer) + Core Animation movement rendered out of process.
import AppKit
import QuartzCore

func makeFrame(_ i: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.5, green: 0.47, blue: 0.87, alpha: 1))
    ctx.fill(CGRect(x: 8, y: 6, width: 16, height: 14 + (i % 2)))
    ctx.setFillColor(CGColor(red: 0.15, green: 0.13, blue: 0.36, alpha: 1))
    ctx.fill(CGRect(x: 12, y: 12, width: 2, height: i % 4 == 3 ? 1 : 3))
    ctx.fill(CGRect(x: 18, y: 12, width: 2, height: i % 4 == 3 ? 1 : 3))
    return ctx.makeImage()!
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var timer: Timer?
    var frame = 0
    let frames = (0..<8).map(makeFrame)
    let sprite = CALayer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = ProcessInfo.processInfo.environment
        let rect = NSRect(x: 600, y: 400, width: 160, height: 200)
        panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = NSView(frame: rect)
        view.wantsLayer = true
        panel.contentView = view
        sprite.frame = CGRect(x: 16, y: 16, width: 128, height: 128)
        sprite.magnificationFilter = .nearest
        sprite.contents = frames[0]
        view.layer!.addSublayer(sprite)
        panel.orderFrontRegardless()

        if env["MODE"] != "still" {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.frame = (self.frame + 1) % self.frames.count
                CATransaction.begin(); CATransaction.setDisableActions(true)
                self.sprite.contents = self.frames[self.frame]
                CATransaction.commit()
            }
        }
        if env["MODE"] == "hop" {
            let hop = CABasicAnimation(keyPath: "position.y")
            hop.byValue = 40; hop.duration = 0.25; hop.autoreverses = true; hop.repeatCount = .infinity
            hop.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            sprite.add(hop, forKey: "hop")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

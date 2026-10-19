import AppKit
import PetCore
import PetSprites

/// Borderless, non-activating panel: never steals focus and follows the user across Spaces.
final class PetPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws the current sprite frame and turns mouse input into click / drag callbacks.
/// Fully transparent pixels are click-through: hitTest returns nil and the window server ignores alpha 0.
@MainActor
final class PetView: NSView {
    let sprite = CALayer()
    var canvas: PixelCanvas?
    var scale: CGFloat = 4

    var onPress: (() -> Void)?
    var onClick: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((PetPoint) -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?

    private var tracker: DragTracker?
    private var grabOffset = NSPoint.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .nearest
        sprite.frame = bounds
        layer?.addSublayer(sprite)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.frame = bounds
        CATransaction.commit()
    }

    func show(_ image: CGImage, canvas: PixelCanvas) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.contents = image
        CATransaction.commit()
        self.canvas = canvas
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local), isOpaquePixel(at: local) else { return nil }
        return self
    }

    private func isOpaquePixel(at p: NSPoint) -> Bool {
        guard let canvas else { return true }
        let hit = SpriteHit.pixel(x: p.x, y: p.y, scale: scale, height: canvas.height)
        return canvas.pixel(hit.x, hit.y) != nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onContextMenu?(event)
            return
        }
        guard let window else { return }
        onPress?()
        let mouse = NSEvent.mouseLocation
        grabOffset = NSPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)
        tracker = DragTracker(start: PetPoint(mouse), time: event.timestamp)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var tracker, let window else { return }
        let mouse = NSEvent.mouseLocation
        let wasDragging = tracker.isDragging
        tracker.move(to: PetPoint(mouse), time: event.timestamp)
        self.tracker = tracker
        guard tracker.isDragging else { return }
        if !wasDragging { onDragBegan?() }
        window.setFrameOrigin(NSPoint(x: mouse.x - grabOffset.x, y: mouse.y - grabOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard let tracker else { return }
        self.tracker = nil
        switch tracker.end(time: event.timestamp) {
        case .click: onClick?()
        case .drag(let velocity): onDragEnded?(velocity)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(event)
    }
}


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
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// At home the pet hangs over the menu bar; AppKit would otherwise push the window below it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Draws the current sprite frame and turns mouse input into click / drag callbacks.
/// Fully transparent pixels are click-through: hitTest returns nil and the window server ignores alpha 0.
@MainActor
final class PetView: NSView {
    let sprite = CALayer()
    let agentsLayer = CALayer()
    var canvas: PixelCanvas?
    var agentsCanvas: PixelCanvas?
    var scale: CGFloat = 4

    var onPress: (() -> Void)?
    var onClick: (() -> Void)?
    var onDragBegan: (() -> Void)?
    /// Release velocity, and whether the pet was shaken on the way.
    var onDragEnded: ((PetPoint, Bool) -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?
    var onHover: ((Bool) -> Void)?
    /// The cursor moved over the pet: its x in screen points (for petting).
    var onMouseMove: ((Double) -> Void)?
    /// Files dragged over the pet (true) or away again (false).
    var onFilesOver: ((Bool) -> Void)?
    /// Files dropped on the pet.
    var onFilesDropped: (([URL]) -> Void)?

    private var tracker: DragTracker?
    private var grabOffset = NSPoint.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .nearest
        sprite.frame = bounds
        agentsLayer.magnificationFilter = .nearest
        agentsLayer.frame = bounds
        layer?.addSublayer(sprite)
        layer?.addSublayer(agentsLayer)
        registerForDraggedTypes([.fileURL])
    }

    // MARK: Files dropped on the pet

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(sender).isEmpty else { return [] }
        onFilesOver?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(sender).isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { onFilesOver?(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        onFilesOver?(false)
        guard !urls.isEmpty else { return false }
        onFilesDropped?(urls)
        return true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.frame = bounds
        agentsLayer.frame = bounds
        CATransaction.commit()
    }

    func showAgents(_ image: CGImage?, canvas: PixelCanvas) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        agentsLayer.contents = image
        CATransaction.commit()
        agentsCanvas = image == nil ? nil : canvas
    }

    func show(_ image: CGImage, canvas: PixelCanvas) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.contents = image
        CATransaction.commit()
        self.canvas = canvas
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseMoved(with event: NSEvent) { onMouseMove?(NSEvent.mouseLocation.x) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local), isOpaquePixel(at: local) else { return nil }
        return self
    }

    private func isOpaquePixel(at p: NSPoint) -> Bool {
        guard let canvas else { return true }
        let hit = SpriteHit.pixel(x: p.x, y: p.y, scale: scale, height: canvas.height)
        return canvas.pixel(hit.x, hit.y) != nil || agentsCanvas?.pixel(hit.x, hit.y) != nil
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
        case .drag(let velocity): onDragEnded?(velocity, tracker.isShaken)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(event)
    }
}


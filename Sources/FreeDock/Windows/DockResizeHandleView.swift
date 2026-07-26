import Cocoa

class DockResizeHandleView: NSView {
    weak var dockPanel: DockPanel?
    var orientation: Orientation = .horizontal

    private var dragStartLocation: NSPoint = .zero
    private var dragStartIconSize: Double = 48
    private var isHovered = false
    private var isResizing = false
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        updateTrackingArea()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let accent = NSColor.controlAccentColor
        let visible = isHovered || isResizing

        // Keep the handle quiet at rest, then reveal a soft hit-area on hover.
        if visible {
            let backgroundRect = orientation == .horizontal
                ? NSRect(x: bounds.midX - 5, y: bounds.midY - 18, width: 10, height: 36)
                : NSRect(x: bounds.midX - 18, y: bounds.midY - 5, width: 36, height: 10)
            accent.withAlphaComponent(isResizing ? 0.22 : 0.12).setFill()
            NSBezierPath(
                roundedRect: backgroundRect,
                xRadius: backgroundRect.width / 2,
                yRadius: backgroundRect.height / 2
            ).fill()
        }

        let dotColor = isResizing
            ? accent
            : (visible ? accent.withAlphaComponent(0.9) : NSColor.secondaryLabelColor.withAlphaComponent(0.6))
        dotColor.setFill()

        let dotRadius: CGFloat = visible ? 1.7 : 1.35
        for offset in [-6.0, 0.0, 6.0] {
            let center = orientation == .horizontal
                ? NSPoint(x: bounds.midX, y: bounds.midY + offset)
                : NSPoint(x: bounds.midX + offset, y: bounds.midY)
            NSBezierPath(
                ovalIn: NSRect(
                    x: center.x - dotRadius,
                    y: center.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
            ).fill()
        }
    }

    override func mouseEntered(with _: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with _: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: orientation == .horizontal ? .resizeLeftRight : .resizeUpDown)
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with _: NSEvent) {
        guard let panel = dockPanel else { return }
        dragStartLocation = NSEvent.mouseLocation
        // Snapshot the current icon size at drag start
        dragStartIconSize = panel.dockDelegate?.currentIconSize(for: panel) ?? 48
        isResizing = true
        needsDisplay = true
    }

    override func mouseDragged(with _: NSEvent) {
        guard let panel = dockPanel else { return }
        let current = NSEvent.mouseLocation
        let delta = orientation == .horizontal
            ? current.x - dragStartLocation.x
            : -(current.y - dragStartLocation.y) // drag down = smaller for vertical

        let newSize = (dragStartIconSize + delta * 0.4).clamped(to: 16 ... 128)
        panel.dockDelegate?.dockPanelDidResize(panel, proposedIconSize: newSize)
    }

    override func mouseUp(with _: NSEvent) {
        guard let panel = dockPanel else { return }
        panel.dockDelegate?.dockPanelDidFinishResize(panel)
        isResizing = false
        needsDisplay = true
    }
}

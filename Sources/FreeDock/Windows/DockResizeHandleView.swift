import Cocoa

class DockResizeHandleView: NSView {
    weak var dockPanel: DockPanel?
    var orientation: Orientation = .horizontal

    private var dragStartLocation: NSPoint = .zero
    private var dragStartIconSize: Double = 48
    private var isHovered = false
    private var isResizing = false
    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { false }

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

        guard visible else { return }

        let handleLength = orientation == .horizontal
            ? min(30, max(18, bounds.height - 16))
            : min(30, max(18, bounds.width - 16))
        let backgroundRect = orientation == .horizontal
            ? NSRect(x: bounds.midX - 6, y: bounds.midY - handleLength / 2, width: 12, height: handleLength)
            : NSRect(x: bounds.midX - handleLength / 2, y: bounds.midY - 6, width: handleLength, height: 12)

        (isResizing ? accent : NSColor.controlBackgroundColor)
            .withAlphaComponent(isResizing ? 0.20 : 0.42)
            .setFill()
        NSBezierPath(
            roundedRect: backgroundRect,
            xRadius: 6,
            yRadius: 6
        ).fill()

        let marks = NSBezierPath()
        for offset in [-2.25, 2.25] {
            if orientation == .horizontal {
                marks.move(to: NSPoint(x: bounds.midX + offset, y: bounds.midY - 5))
                marks.line(to: NSPoint(x: bounds.midX + offset, y: bounds.midY + 5))
            } else {
                marks.move(to: NSPoint(x: bounds.midX - 5, y: bounds.midY + offset))
                marks.line(to: NSPoint(x: bounds.midX + 5, y: bounds.midY + offset))
            }
        }
        marks.lineWidth = 1.4
        marks.lineCapStyle = .round
        (isResizing ? accent : NSColor.secondaryLabelColor.withAlphaComponent(0.72)).setStroke()
        marks.stroke()
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

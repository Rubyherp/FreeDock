import Cocoa

class DockResizeHandleView: NSView {
    weak var dockPanel: DockPanel?
    var orientation: Orientation = .horizontal

    private var dragStartLocation: NSPoint = .zero
    private var dragStartIconSize: Double = 48

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder _: NSCoder) {
        nil
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
    }
}

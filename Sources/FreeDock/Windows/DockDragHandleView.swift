import Cocoa

class DockDragHandleView: NSView {
    weak var dockPanel: DockPanel?
    private var positionBeforeDrag: NSPoint?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let padding: CGFloat = 8
        let inPadding = point.x < padding || point.y < padding ||
                        point.x > bounds.width - padding || point.y > bounds.height - padding
        guard inPadding, !(dockPanel?.dockDelegate?.lockPositions ?? false) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard let panel = dockPanel else { return }
        positionBeforeDrag = panel.frame.origin
        panel.performDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard let panel = dockPanel else { return }
        if let before = positionBeforeDrag, panel.frame.origin != before {
            panel.dockDelegate?.dockPanelDidMove(panel)
        }
        positionBeforeDrag = nil
    }
}

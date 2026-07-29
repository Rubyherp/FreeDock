import Cocoa

class DockDragHandleView: NSView {
    weak var dockPanel: DockPanel?
    var orientation: Orientation = .horizontal {
        didSet { needsLayout = true }
    }

    private let highlightLayer = CALayer()
    private var tracking: NSTrackingArea?

    private var stripRect: NSRect {
        if orientation == .horizontal {
            return bounds.insetBy(dx: 3, dy: 8)
        }

        return bounds.insetBy(dx: 8, dy: 3)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        highlightLayer.cornerRadius = 3
        highlightLayer.borderWidth = 1
        layer?.addSublayer(highlightLayer)
        updateAppearance(isHovered: false)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }

    override func layout() {
        super.layout()
        let pillW: CGFloat = 3
        let pillH = CGFloat(18)

        if orientation == .horizontal {
            highlightLayer.frame = NSRect(
                x: stripRect.midX - pillW / 2,
                y: stripRect.midY - pillH / 2,
                width: pillW,
                height: pillH
            )
            highlightLayer.cornerRadius = pillW / 2
        } else {
            highlightLayer.frame = NSRect(
                x: stripRect.midX - pillH / 2,
                y: stripRect.midY - pillW / 2,
                width: pillH,
                height: pillW
            )
            highlightLayer.cornerRadius = pillW / 2
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateAppearance(isHovered: true)
        dockPanel?.cancelAutoHide()
    }

    override func mouseExited(with event: NSEvent) {
        updateAppearance(isHovered: false)
        guard let panel = dockPanel else {
            super.mouseExited(with: event)
            return
        }
        if panel.frame.contains(NSEvent.mouseLocation) {
            panel.cancelAutoHide()
        } else {
            super.mouseExited(with: event)
        }
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard super.hitTest(point) != nil else { return nil }
        guard stripRect.contains(point) else { return nil }
        guard !(dockPanel?.dockDelegate?.lockPositions ?? false) else { return nil }
        return self
    }

    private func updateAppearance(isHovered: Bool) {
        let locked = dockPanel?.dockDelegate?.lockPositions ?? false
        highlightLayer.backgroundColor = NSColor.labelColor
            .withAlphaComponent(isHovered ? 0.38 : 0)
            .cgColor
        highlightLayer.borderColor = NSColor.white
            .withAlphaComponent(isHovered ? 0.24 : 0)
            .cgColor
        alphaValue = locked ? 0.4 : 1.0
    }

    override func mouseDown(with event: NSEvent) {
        guard let panel = dockPanel else { return }
        let before = panel.frame.origin
        panel.performDrag(with: event)
        if panel.frame.origin != before {
            panel.dockDelegate?.dockPanelDidMove(panel)
        }
    }
}

import Cocoa

class DockDragHandleView: NSView {
    weak var dockPanel: DockPanel?
    var orientation: Orientation = .horizontal {
        didSet { needsLayout = true }
    }

    private let highlightLayer = CALayer()
    private var tracking: NSTrackingArea?

    private var stripRect: NSRect {
        let edgeInset: CGFloat = 8

        if orientation == .horizontal {
            let hitWidth: CGFloat = 24
            return NSRect(
                x: edgeInset,
                y: edgeInset,
                width: hitWidth,
                height: max(0, bounds.height - edgeInset * 2)
            )
        }

        let hitHeight: CGFloat = 24
        return NSRect(
            x: edgeInset,
            y: edgeInset,
            width: max(0, bounds.width - edgeInset * 2),
            height: hitHeight
        )
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        highlightLayer.cornerRadius = 8
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
        let pillW: CGFloat = 5
        let pillH = CGFloat(22)

        if orientation == .horizontal {
            highlightLayer.frame = NSRect(
                x: (stripRect.width - pillW) / 2 + stripRect.minX,
                y: (bounds.height - pillH) / 2,
                width: pillW,
                height: pillH
            )
            highlightLayer.cornerRadius = pillW / 2
        } else {
            highlightLayer.frame = NSRect(
                x: (bounds.width - pillH) / 2,
                y: (stripRect.height - pillW) / 2 + stripRect.minY,
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
        highlightLayer.backgroundColor = NSColor.white
            .withAlphaComponent(isHovered ? 0.55 : 0.25)
            .cgColor
        highlightLayer.borderColor = NSColor.white
            .withAlphaComponent(isHovered ? 0.70 : 0.35)
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

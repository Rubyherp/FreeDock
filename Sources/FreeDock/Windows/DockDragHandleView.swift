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
            // y: max(0, bounds.height - edgeInset - hitHeight),
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

    required init?(coder: NSCoder) { nil }

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
        highlightLayer.frame = stripRect.insetBy(dx: 2, dy: 2)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateAppearance(isHovered: true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        updateAppearance(isHovered: false)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
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
        let fillAlpha: CGFloat
        if locked {
            fillAlpha = 0.06
        } else {
            fillAlpha = isHovered ? 0.30 : 0.20
        }
        highlightLayer.backgroundColor = NSColor.systemBlue.withAlphaComponent(fillAlpha).cgColor
        highlightLayer.borderColor = NSColor.white.withAlphaComponent(locked ? 0.12 : 0.38).cgColor
        alphaValue = locked ? 0.6 : 1.0
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

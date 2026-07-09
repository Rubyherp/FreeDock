import Cocoa

class DockDragHandleView: NSView {
    weak var dockPanel: DockPanel?
    private var positionBeforeDrag: NSPoint?
    private var isVertical: Bool { dockPanel?.dockOrientation == .vertical }

    private lazy var gripLayer: CALayer = {
        let layer = CALayer()
        layer.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        layer.cornerRadius = 2
        return layer
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        if !isVertical {
            gripLayer.frame = NSRect(x: bounds.midX - 1.5, y: bounds.midY - 18, width: 10, height: 70)
        } else {
            gripLayer.frame = NSRect(x: bounds.midX - 18, y: bounds.midY - 1.5, width: 70, height: 10)
        }
        if gripLayer.superlayer == nil { layer?.addSublayer(gripLayer) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard super.hitTest(point) != nil else { return nil }
        guard !(dockPanel?.dockDelegate?.lockPositions ?? false) else { return nil }
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

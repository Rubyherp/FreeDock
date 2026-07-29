import Cocoa

enum DockRevealEdge {
    case left
    case right
    case top
    case bottom
}

class DockContainerView: NSView {
    weak var dockPanel: DockPanel?

    private var trackingArea: NSTrackingArea?
    private let revealIndicatorLayer = CALayer()
    private var revealEdge: DockRevealEdge?

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        revealIndicatorLayer.opacity = 0
        revealIndicatorLayer.borderWidth = 0.5
        revealIndicatorLayer.shadowOpacity = 0.16
        revealIndicatorLayer.shadowRadius = 3
        revealIndicatorLayer.shadowOffset = CGSize(width: 0, height: 1)
        revealIndicatorLayer.zPosition = 1_000
        layer?.addSublayer(revealIndicatorLayer)
        updateRevealAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        revealIndicatorLayer.zPosition = 1_000
        layer?.addSublayer(revealIndicatorLayer)
        updateRevealAppearance()
    }

    override func layout() {
        super.layout()
        layoutRevealIndicator()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateRevealAppearance()
    }

    func showRevealIndicator(at edge: DockRevealEdge) {
        revealEdge = edge
        layoutRevealIndicator()
        revealIndicatorLayer.opacity = 1
    }

    func hideRevealIndicator() {
        revealIndicatorLayer.opacity = 0
        revealEdge = nil
    }

    private func layoutRevealIndicator() {
        guard let revealEdge else { return }

        let thickness: CGFloat = 4
        let length: CGFloat = 42
        let frame: NSRect

        switch revealEdge {
        case .left:
            frame = NSRect(x: bounds.maxX - thickness - 1, y: bounds.midY - length / 2, width: thickness, height: length)
        case .right:
            frame = NSRect(x: 1, y: bounds.midY - length / 2, width: thickness, height: length)
        case .bottom:
            frame = NSRect(x: bounds.midX - length / 2, y: bounds.maxY - thickness - 1, width: length, height: thickness)
        case .top:
            frame = NSRect(x: bounds.midX - length / 2, y: 1, width: length, height: thickness)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        revealIndicatorLayer.frame = frame
        revealIndicatorLayer.cornerRadius = thickness / 2
        CATransaction.commit()
    }

    private func updateRevealAppearance() {
        revealIndicatorLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.34).cgColor
        revealIndicatorLayer.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        revealIndicatorLayer.shadowColor = NSColor.black.cgColor
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [
                .mouseEnteredAndExited,
                .activeAlways,
                .inVisibleRect,
            ],
            owner: self,
            userInfo: nil
        )

        addTrackingArea(trackingArea!)
        super.updateTrackingAreas()
    }

    override func mouseEntered(with _: NSEvent) {
        dockPanel?.cancelAutoHide()
    }

    override func mouseExited(with _: NSEvent) {
        dockPanel?.scheduleAutoHide()
    }
}

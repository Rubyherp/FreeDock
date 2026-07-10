import Cocoa

class DockContainerView: NSView {
    weak var dockPanel: DockPanel?

    private var trackingArea: NSTrackingArea?

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

import Cocoa

enum DockResizeGestureMath {
    static let minimumDragDistance: CGFloat = 2
    static var iconSizeRange: ClosedRange<Double> {
        DockConfig.iconSizeRange
    }

    static func resizableItemCount(in items: [DockItem]) -> Int {
        items.reduce(into: 0) { count, item in
            if !item.isSeparator {
                count += 1
            }
        }
    }

    static func sensitivity(forResizableItemCount itemCount: Int) -> Double {
        1 / Double(max(1, itemCount))
    }

    static func axisDelta(
        from start: NSPoint,
        to current: NSPoint,
        orientation: Orientation
    ) -> CGFloat {
        switch orientation {
        case .horizontal:
            return current.x - start.x
        case .vertical:
            // The vertical handle sits at the bottom of the dock. In AppKit's
            // screen coordinates, dragging it downward decreases y.
            return start.y - current.y
        }
    }

    static func proposedIconSize(
        startingAt iconSize: Double,
        from start: NSPoint,
        to current: NSPoint,
        orientation: Orientation,
        resizableItemCount: Int
    ) -> Double {
        let delta = axisDelta(
            from: start,
            to: current,
            orientation: orientation
        )
        let iconPointsPerDragPoint = sensitivity(
            forResizableItemCount: resizableItemCount
        )
        return (iconSize + Double(delta) * iconPointsPerDragPoint)
            .clamped(to: iconSizeRange)
    }

    static func committedIconSize(_ iconSize: Double) -> Double {
        iconSize.rounded().clamped(to: iconSizeRange)
    }
}

class DockResizeHandleView: NSView {
    weak var dockPanel: DockPanel?
    var resizableItemCount = 0
    var orientation: Orientation = .horizontal {
        didSet {
            guard orientation != oldValue else { return }
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }

    private var dragStartLocation: NSPoint = .zero
    private var dragStartIconSize: Double = 48
    private var dragResizableItemCount = 0
    private var lastProposedIconSize: Double?
    private var isHovered = false
    private var isResizing = false
    private var didResize = false
    private var trackingArea: NSTrackingArea?
    private var resizeInteractionToken: UUID?

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

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            finishResize(notifyDelegate: true)
            NSCursor.arrow.set()
        }
        super.viewWillMove(toWindow: newWindow)
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
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
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

    override func mouseDown(with event: NSEvent) {
        guard let panel = dockPanel else { return }

        finishResize(notifyDelegate: true)
        dragStartLocation = screenLocation(for: event)
        dragStartIconSize = panel.dockDelegate?.currentIconSize(for: panel) ?? 48
        dragResizableItemCount = resizableItemCount
        lastProposedIconSize = dragStartIconSize
        didResize = false
        isResizing = true
        resizeInteractionToken = panel.beginResizeInteraction()
        resizeCursor.set()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isResizing, let panel = dockPanel else { return }
        resizeCursor.set()
        let current = screenLocation(for: event)
        let delta = DockResizeGestureMath.axisDelta(
            from: dragStartLocation,
            to: current,
            orientation: orientation
        )
        guard didResize
                || abs(delta) >= DockResizeGestureMath.minimumDragDistance
        else {
            return
        }

        let newSize = DockResizeGestureMath.proposedIconSize(
            startingAt: dragStartIconSize,
            from: dragStartLocation,
            to: current,
            orientation: orientation,
            resizableItemCount: dragResizableItemCount
        )
        guard lastProposedIconSize != newSize else { return }

        didResize = true
        lastProposedIconSize = newSize
        panel.dockDelegate?.dockPanelDidResize(panel, proposedIconSize: newSize)
    }

    override func mouseUp(with _: NSEvent) {
        finishResize(notifyDelegate: true)
    }

    private func finishResize(notifyDelegate: Bool) {
        guard isResizing
                || resizeInteractionToken != nil
        else {
            return
        }

        let panel = dockPanel
        let shouldNotifyDelegate = notifyDelegate && didResize

        isResizing = false
        didResize = false
        lastProposedIconSize = nil

        if shouldNotifyDelegate, let panel {
            panel.dockDelegate?.dockPanelDidFinishResize(panel)
        }
        if let resizeInteractionToken {
            panel?.endResizeInteraction(resizeInteractionToken)
            self.resizeInteractionToken = nil
        }

        updateCursorAfterResize()
        needsDisplay = true
    }

    private func screenLocation(for event: NSEvent?) -> NSPoint {
        guard let event, let eventWindow = event.window else {
            return NSEvent.mouseLocation
        }
        return eventWindow.convertPoint(toScreen: event.locationInWindow)
    }

    private var resizeCursor: NSCursor {
        orientation == .horizontal ? .resizeLeftRight : .resizeUpDown
    }

    private func updateCursorAfterResize() {
        window?.invalidateCursorRects(for: self)
        guard let window else {
            NSCursor.arrow.set()
            return
        }

        let windowPoint = window.convertPoint(
            fromScreen: NSEvent.mouseLocation
        )
        let localPoint = convert(windowPoint, from: nil)
        (bounds.contains(localPoint) ? resizeCursor : .arrow).set()
    }
}

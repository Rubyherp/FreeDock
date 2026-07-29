import Foundation

enum DockPanelResizeGeometry {
    static func dockedEdge(
        of frame: CGRect,
        in visibleFrame: CGRect,
        orientation: Orientation,
        tolerance: CGFloat
    ) -> DockScreenEdge? {
        let candidates: [(edge: DockScreenEdge, distance: CGFloat)]

        if orientation == .horizontal {
            candidates = [
                (.bottom, abs(frame.minY - visibleFrame.minY)),
                (.top, abs(frame.maxY - visibleFrame.maxY)),
            ]
        } else {
            candidates = [
                (.left, abs(frame.minX - visibleFrame.minX)),
                (.right, abs(frame.maxX - visibleFrame.maxX)),
            ]
        }

        return candidates
            .filter { $0.distance <= tolerance }
            .min { $0.distance < $1.distance }?
            .edge
    }

    static func anchoredFrame(
        from referenceFrame: CGRect,
        size: CGSize,
        orientation: Orientation,
        dockedEdge: DockScreenEdge?
    ) -> CGRect {
        var frame = CGRect(origin: referenceFrame.origin, size: size)

        if dockedEdge == .right {
            frame.origin.x = referenceFrame.maxX - size.width
        }

        if orientation == .horizontal {
            if dockedEdge == .top {
                frame.origin.y = referenceFrame.maxY - size.height
            }
        } else if dockedEdge == .bottom {
            frame.origin.y = referenceFrame.minY
        } else {
            frame.origin.y = referenceFrame.maxY - size.height
        }

        return frame
    }
}

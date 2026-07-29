import Foundation

enum WindowPreviewPanelSide: Equatable, Sendable {
    case above
    case below
    case left
    case right

    var opposite: WindowPreviewPanelSide {
        switch self {
        case .above: return .below
        case .below: return .above
        case .left: return .right
        case .right: return .left
        }
    }
}

struct WindowPreviewPanelPlacement: Equatable, Sendable {
    let frame: CGRect
    let side: WindowPreviewPanelSide
}

enum WindowPreviewPanelGeometry {
    private static let minimumUsableSize = CGSize(
        width: 260,
        height: 140
    )

    static func placement(
        size requestedSize: CGSize,
        sourceRect: CGRect,
        dockFrame: CGRect,
        visibleFrame: CGRect,
        orientation: Orientation,
        dockedEdge: DockScreenEdge? = nil,
        gap: CGFloat = 8,
        inset: CGFloat = 8
    ) -> WindowPreviewPanelPlacement {
        let visibleFrame = visibleFrame.standardized
        let availableFrame = insetFrame(
            visibleFrame,
            by: max(0, inset)
        )
        let preferredSide = preferredSide(
            dockFrame: dockFrame,
            visibleFrame: visibleFrame,
            orientation: orientation,
            dockedEdge: dockedEdge
        )
        let anchorRect = resolvedSourceRect(
            sourceRect,
            dockFrame: dockFrame,
            side: preferredSide
        )
        let boundedSize = CGSize(
            width: min(
                max(1, finite(requestedSize.width, fallback: 1)),
                max(1, availableFrame.width)
            ),
            height: min(
                max(1, finite(requestedSize.height, fallback: 1)),
                max(1, availableFrame.height)
            )
        )
        let gap = max(0, gap)
        let preferredCapacity = availableExtent(
            on: preferredSide,
            from: anchorRect,
            in: availableFrame,
            gap: gap
        )
        let oppositeCapacity = availableExtent(
            on: preferredSide.opposite,
            from: anchorRect,
            in: availableFrame,
            gap: gap
        )
        let requestedExtent = extent(
            of: boundedSize,
            on: preferredSide
        )
        let side = preferredCapacity < requestedExtent
            && oppositeCapacity > preferredCapacity
            ? preferredSide.opposite
            : preferredSide
        let fittedSize = fittedSize(
            boundedSize,
            on: side,
            capacity: availableExtent(
                on: side,
                from: anchorRect,
                in: availableFrame,
                gap: gap
            )
        )
        let frame = clamped(
            candidateFrame(
                size: fittedSize,
                sourceRect: anchorRect,
                side: side,
                gap: gap
            ),
            to: availableFrame
        )

        return WindowPreviewPanelPlacement(
            frame: frame,
            side: side
        )
    }

    private static func preferredSide(
        dockFrame: CGRect,
        visibleFrame: CGRect,
        orientation: Orientation,
        dockedEdge: DockScreenEdge?
    ) -> WindowPreviewPanelSide {
        if let dockedEdge {
            switch dockedEdge {
            case .bottom: return .above
            case .top: return .below
            case .left: return .right
            case .right: return .left
            }
        }

        if orientation == .horizontal {
            return dockFrame.midY <= visibleFrame.midY
                ? .above
                : .below
        }
        return dockFrame.midX <= visibleFrame.midX
            ? .right
            : .left
    }

    private static func resolvedSourceRect(
        _ sourceRect: CGRect,
        dockFrame: CGRect,
        side: WindowPreviewPanelSide
    ) -> CGRect {
        let standardizedSource = sourceRect.standardized
        guard !standardizedSource.isEmpty,
              standardizedSource.origin.x.isFinite,
              standardizedSource.origin.y.isFinite,
              standardizedSource.width.isFinite,
              standardizedSource.height.isFinite
        else {
            let point: CGPoint
            switch side {
            case .above:
                point = CGPoint(x: dockFrame.midX, y: dockFrame.maxY)
            case .below:
                point = CGPoint(x: dockFrame.midX, y: dockFrame.minY)
            case .left:
                point = CGPoint(x: dockFrame.minX, y: dockFrame.midY)
            case .right:
                point = CGPoint(x: dockFrame.maxX, y: dockFrame.midY)
            }
            return CGRect(origin: point, size: .zero)
        }
        return standardizedSource
    }

    private static func fittedSize(
        _ size: CGSize,
        on side: WindowPreviewPanelSide,
        capacity: CGFloat
    ) -> CGSize {
        var result = size
        switch side {
        case .above, .below:
            let minimumExtent = min(
                size.height,
                minimumUsableSize.height
            )
            if capacity >= minimumExtent {
                result.height = min(size.height, max(1, capacity))
            }
        case .left, .right:
            let minimumExtent = min(
                size.width,
                minimumUsableSize.width
            )
            if capacity >= minimumExtent {
                result.width = min(size.width, max(1, capacity))
            }
        }
        return result
    }

    private static func extent(
        of size: CGSize,
        on side: WindowPreviewPanelSide
    ) -> CGFloat {
        switch side {
        case .above, .below:
            return size.height
        case .left, .right:
            return size.width
        }
    }

    private static func candidateFrame(
        size: CGSize,
        sourceRect: CGRect,
        side: WindowPreviewPanelSide,
        gap: CGFloat
    ) -> CGRect {
        switch side {
        case .above:
            return CGRect(
                x: sourceRect.midX - size.width / 2,
                y: sourceRect.maxY + gap,
                width: size.width,
                height: size.height
            )
        case .below:
            return CGRect(
                x: sourceRect.midX - size.width / 2,
                y: sourceRect.minY - gap - size.height,
                width: size.width,
                height: size.height
            )
        case .left:
            return CGRect(
                x: sourceRect.minX - gap - size.width,
                y: sourceRect.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        case .right:
            return CGRect(
                x: sourceRect.maxX + gap,
                y: sourceRect.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
    }

    private static func availableExtent(
        on side: WindowPreviewPanelSide,
        from sourceRect: CGRect,
        in bounds: CGRect,
        gap: CGFloat
    ) -> CGFloat {
        switch side {
        case .above:
            return max(0, bounds.maxY - sourceRect.maxY - gap)
        case .below:
            return max(0, sourceRect.minY - gap - bounds.minY)
        case .left:
            return max(0, sourceRect.minX - gap - bounds.minX)
        case .right:
            return max(0, bounds.maxX - sourceRect.maxX - gap)
        }
    }

    private static func insetFrame(
        _ frame: CGRect,
        by requestedInset: CGFloat
    ) -> CGRect {
        let horizontalInset = min(
            requestedInset,
            max(0, (frame.width - 1) / 2)
        )
        let verticalInset = min(
            requestedInset,
            max(0, (frame.height - 1) / 2)
        )
        return frame.insetBy(
            dx: horizontalInset,
            dy: verticalInset
        )
    }

    private static func clamped(
        _ frame: CGRect,
        to bounds: CGRect
    ) -> CGRect {
        var frame = frame
        frame.origin.x = min(
            max(frame.minX, bounds.minX),
            max(bounds.minX, bounds.maxX - frame.width)
        )
        frame.origin.y = min(
            max(frame.minY, bounds.minY),
            max(bounds.minY, bounds.maxY - frame.height)
        )
        return frame
    }

    private static func finite(
        _ value: CGFloat,
        fallback: CGFloat
    ) -> CGFloat {
        value.isFinite ? value : fallback
    }
}

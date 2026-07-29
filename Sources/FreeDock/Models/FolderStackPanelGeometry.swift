import Foundation

enum FolderStackPanelSide: Equatable, Sendable {
    case above
    case below
    case left
    case right

    var opposite: FolderStackPanelSide {
        switch self {
        case .above: return .below
        case .below: return .above
        case .left: return .right
        case .right: return .left
        }
    }
}

struct FolderStackPanelPlacement: Equatable, Sendable {
    let frame: CGRect
    let side: FolderStackPanelSide
}

enum FolderStackPanelGeometry {
    private static let minimumUsableHeight: CGFloat = 180
    private static let minimumUsableWidth: CGFloat = 260

    static func placement(
        size: CGSize,
        sourceRect: CGRect,
        dockFrame: CGRect,
        visibleFrame: CGRect,
        orientation: Orientation,
        gap: CGFloat = 10,
        inset: CGFloat = 12
    ) -> FolderStackPanelPlacement {
        let availableFrame = visibleFrame.insetBy(dx: inset, dy: inset)
        let boundedSize = CGSize(
            width: min(size.width, max(1, availableFrame.width)),
            height: min(size.height, max(1, availableFrame.height))
        )
        let preferredSide: FolderStackPanelSide
        if orientation == .horizontal {
            preferredSide = dockFrame.midY <= visibleFrame.midY
                ? .above
                : .below
        } else {
            preferredSide = dockFrame.midX <= visibleFrame.midX
                ? .right
                : .left
        }

        let preferredCapacity = availableExtent(
            on: preferredSide,
            from: sourceRect,
            in: availableFrame,
            gap: gap
        )
        let oppositeCapacity = availableExtent(
            on: preferredSide.opposite,
            from: sourceRect,
            in: availableFrame,
            gap: gap
        )
        let requestedExtent = preferredSide == .above
            || preferredSide == .below
            ? boundedSize.height
            : boundedSize.width
        let side = preferredCapacity < requestedExtent
            && oppositeCapacity > preferredCapacity
            ? preferredSide.opposite
            : preferredSide
        let sideCapacity = availableExtent(
            on: side,
            from: sourceRect,
            in: availableFrame,
            gap: gap
        )
        let minimumUsableExtent: CGFloat
        switch side {
        case .above, .below:
            minimumUsableExtent = min(
                boundedSize.height,
                minimumUsableHeight
            )
        case .left, .right:
            minimumUsableExtent = min(
                boundedSize.width,
                minimumUsableWidth
            )
        }
        let shouldFitBesideSource = sideCapacity >= minimumUsableExtent
        let fittedSize: CGSize
        switch side {
        case .above, .below:
            fittedSize = CGSize(
                width: boundedSize.width,
                height: shouldFitBesideSource
                    ? min(boundedSize.height, max(1, sideCapacity))
                    : boundedSize.height
            )
        case .left, .right:
            fittedSize = CGSize(
                width: shouldFitBesideSource
                    ? min(boundedSize.width, max(1, sideCapacity))
                    : boundedSize.width,
                height: boundedSize.height
            )
        }
        let frame = clamped(
            candidateFrame(
                size: fittedSize,
                sourceRect: sourceRect,
                side: side,
                gap: gap
            ),
            to: availableFrame
        )
        return FolderStackPanelPlacement(frame: frame, side: side)
    }

    private static func candidateFrame(
        size: CGSize,
        sourceRect: CGRect,
        side: FolderStackPanelSide,
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
        on side: FolderStackPanelSide,
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
}

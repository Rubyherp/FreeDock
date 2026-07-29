import CoreGraphics
import Foundation

struct QuickLaunchDockCandidate: Equatable, Sendable {
    let dockID: UUID
    let frame: CGRect
    let configOrder: Int
}

enum QuickLaunchDockRouter {
    static func targetDockID(
        for pointer: CGPoint,
        pointerScreenFrame: CGRect?,
        candidates: [QuickLaunchDockCandidate]
    ) -> UUID? {
        let indexedCandidates = candidates.enumerated().map {
            IndexedCandidate(inputOrder: $0.offset, candidate: $0.element)
        }
        guard !indexedCandidates.isEmpty else {
            return nil
        }

        let screenCandidates: [IndexedCandidate]
        if let pointerScreenFrame,
           let screenFrame = finiteStandardized(pointerScreenFrame)
        {
            screenCandidates = indexedCandidates.filter {
                isAssociated($0.candidate.frame, with: screenFrame)
            }
        } else {
            screenCandidates = []
        }

        guard !screenCandidates.isEmpty else {
            return indexedCandidates.min(by: configOrderPrecedes)?
                .candidate.dockID
        }

        return screenCandidates.min {
            let leftDistance = squaredDistance(
                from: pointer,
                to: $0.candidate.frame
            )
            let rightDistance = squaredDistance(
                from: pointer,
                to: $1.candidate.frame
            )
            if leftDistance != rightDistance {
                return leftDistance < rightDistance
            }
            return configOrderPrecedes($0, $1)
        }?.candidate.dockID
    }

    private struct IndexedCandidate {
        let inputOrder: Int
        let candidate: QuickLaunchDockCandidate
    }

    private static func isAssociated(
        _ candidateFrame: CGRect,
        with screenFrame: CGRect
    ) -> Bool {
        guard let candidateFrame = finiteStandardized(candidateFrame) else {
            return false
        }
        let center = CGPoint(
            x: candidateFrame.midX,
            y: candidateFrame.midY
        )
        return candidateFrame.intersects(screenFrame)
            || screenFrame.contains(center)
    }

    private static func squaredDistance(
        from point: CGPoint,
        to frame: CGRect
    ) -> CGFloat {
        guard point.x.isFinite,
              point.y.isFinite,
              let frame = finiteStandardized(frame)
        else {
            return .infinity
        }

        let deltaX = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let deltaY = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return deltaX * deltaX + deltaY * deltaY
    }

    private static func finiteStandardized(_ frame: CGRect) -> CGRect? {
        let frame = frame.standardized
        guard frame.origin.x.isFinite,
              frame.origin.y.isFinite,
              frame.width.isFinite,
              frame.height.isFinite
        else {
            return nil
        }
        return frame
    }

    private static func configOrderPrecedes(
        _ lhs: IndexedCandidate,
        _ rhs: IndexedCandidate
    ) -> Bool {
        if lhs.candidate.configOrder != rhs.candidate.configOrder {
            return lhs.candidate.configOrder < rhs.candidate.configOrder
        }
        return lhs.inputOrder < rhs.inputOrder
    }
}

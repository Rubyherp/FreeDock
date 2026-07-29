import CoreGraphics
import Foundation
import Testing
@testable import FreeDock

@Test("Quick launch routing returns nil without dock candidates")
func quickLaunchRoutingEmptyCandidates() {
    let selected = QuickLaunchDockRouter.targetDockID(
        for: CGPoint(x: 50, y: 50),
        pointerScreenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
        candidates: []
    )

    #expect(selected == nil)
}

@Test("Quick launch routing only compares docks on the pointer screen")
func quickLaunchRoutingPrefersPointerScreen() {
    let otherScreenDock = quickLaunchDockCandidate(
        1,
        frame: CGRect(x: 90, y: 40, width: 8, height: 20),
        configOrder: 0
    )
    let pointerScreenDock = quickLaunchDockCandidate(
        2,
        frame: CGRect(x: 180, y: 40, width: 15, height: 20),
        configOrder: 1
    )

    let selected = QuickLaunchDockRouter.targetDockID(
        for: CGPoint(x: 101, y: 50),
        pointerScreenFrame: CGRect(x: 100, y: 0, width: 100, height: 100),
        candidates: [otherScreenDock, pointerScreenDock]
    )

    #expect(selected == pointerScreenDock.dockID)
}

@Test("Quick launch routing uses point-to-rectangle distance")
func quickLaunchRoutingDistance() {
    let diagonalDock = quickLaunchDockCandidate(
        1,
        frame: CGRect(x: 100, y: 100, width: 10, height: 10),
        configOrder: 0
    )
    let verticallyCloserDock = quickLaunchDockCandidate(
        2,
        frame: CGRect(x: 0, y: 100, width: 10, height: 10),
        configOrder: 1
    )

    let selected = QuickLaunchDockRouter.targetDockID(
        for: .zero,
        pointerScreenFrame: CGRect(x: 0, y: 0, width: 200, height: 200),
        candidates: [diagonalDock, verticallyCloserDock]
    )

    #expect(selected == verticallyCloserDock.dockID)
}

@Test("A pointer inside a dock has zero routing distance")
func quickLaunchRoutingInsideDock() {
    let nearbyDock = quickLaunchDockCandidate(
        1,
        frame: CGRect(x: 70, y: 70, width: 10, height: 10),
        configOrder: 0
    )
    let containingDock = quickLaunchDockCandidate(
        2,
        frame: CGRect(x: 40, y: 40, width: 20, height: 20),
        configOrder: 1
    )

    let selected = QuickLaunchDockRouter.targetDockID(
        for: CGPoint(x: 50, y: 50),
        pointerScreenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
        candidates: [nearbyDock, containingDock]
    )

    #expect(selected == containingDock.dockID)
}

@Test("Equal routing distances use stable configuration order")
func quickLaunchRoutingConfigOrderTieBreak() {
    let laterDock = quickLaunchDockCandidate(
        1,
        frame: CGRect(x: 60, y: 40, width: 10, height: 20),
        configOrder: 8
    )
    let earlierDock = quickLaunchDockCandidate(
        2,
        frame: CGRect(x: 30, y: 40, width: 10, height: 20),
        configOrder: 2
    )

    let selected = QuickLaunchDockRouter.targetDockID(
        for: CGPoint(x: 50, y: 50),
        pointerScreenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
        candidates: [laterDock, earlierDock]
    )

    #expect(selected == earlierDock.dockID)
}

@Test("Zero-size dock frames can associate by their center point")
func quickLaunchRoutingCenterAssociation() {
    let pointDock = quickLaunchDockCandidate(
        1,
        frame: CGRect(x: 50, y: 50, width: 0, height: 0),
        configOrder: 1
    )
    let offscreenFallback = quickLaunchDockCandidate(
        2,
        frame: CGRect(x: 200, y: 200, width: 10, height: 10),
        configOrder: 0
    )

    let selected = QuickLaunchDockRouter.targetDockID(
        for: CGPoint(x: 50, y: 50),
        pointerScreenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
        candidates: [offscreenFallback, pointDock]
    )

    #expect(selected == pointDock.dockID)
}

@Test("No pointer-screen match falls back to first configuration order")
func quickLaunchRoutingNoScreenMatchFallback() {
    let geometricallyCloser = quickLaunchDockCandidate(
        1,
        frame: CGRect(x: 90, y: 40, width: 5, height: 20),
        configOrder: 7
    )
    let firstConfigured = quickLaunchDockCandidate(
        2,
        frame: CGRect(x: -200, y: 40, width: 10, height: 20),
        configOrder: 1
    )

    let selected = QuickLaunchDockRouter.targetDockID(
        for: CGPoint(x: 101, y: 50),
        pointerScreenFrame: CGRect(x: 100, y: 0, width: 100, height: 100),
        candidates: [geometricallyCloser, firstConfigured]
    )

    #expect(selected == firstConfigured.dockID)
}

@Test("Missing pointer screen falls back deterministically")
func quickLaunchRoutingMissingScreenFallback() {
    let laterDock = quickLaunchDockCandidate(
        1,
        frame: CGRect(x: 0, y: 0, width: 10, height: 10),
        configOrder: 3
    )
    let firstDock = quickLaunchDockCandidate(
        2,
        frame: CGRect(x: 20, y: 0, width: 10, height: 10),
        configOrder: 0
    )

    let selected = QuickLaunchDockRouter.targetDockID(
        for: .zero,
        pointerScreenFrame: nil,
        candidates: [laterDock, firstDock]
    )

    #expect(selected == firstDock.dockID)
}

@Test("Duplicate configuration order preserves candidate input order")
func quickLaunchRoutingDuplicateConfigOrder() {
    let firstInput = quickLaunchDockCandidate(
        1,
        frame: CGRect(x: 40, y: 40, width: 20, height: 20),
        configOrder: 0
    )
    let secondInput = quickLaunchDockCandidate(
        2,
        frame: CGRect(x: 40, y: 40, width: 20, height: 20),
        configOrder: 0
    )

    let selected = QuickLaunchDockRouter.targetDockID(
        for: CGPoint(x: 50, y: 50),
        pointerScreenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
        candidates: [firstInput, secondInput]
    )

    #expect(selected == firstInput.dockID)
}

private func quickLaunchDockCandidate(
    _ id: Int,
    frame: CGRect,
    configOrder: Int
) -> QuickLaunchDockCandidate {
    QuickLaunchDockCandidate(
        dockID: quickLaunchDockID(id),
        frame: frame,
        configOrder: configOrder
    )
}

private func quickLaunchDockID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", value))!
}

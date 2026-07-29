import Foundation
import Testing
@testable import FreeDock

@Test("Resize edge detection follows the dock orientation without auto-hide")
func resizeEdgeDetectionFollowsOrientation() {
    let visibleFrame = CGRect(x: -1440, y: -120, width: 1440, height: 900)
    let horizontalDock = CGRect(x: -980, y: 708, width: 520, height: 72)
    let verticalDock = CGRect(x: -1440, y: 160, width: 72, height: 420)

    #expect(DockPanelResizeGeometry.dockedEdge(
        of: horizontalDock,
        in: visibleFrame,
        orientation: .horizontal,
        tolerance: 2
    ) == .top)
    #expect(DockPanelResizeGeometry.dockedEdge(
        of: verticalDock,
        in: visibleFrame,
        orientation: .vertical,
        tolerance: 2
    ) == .left)
}

@Test("Resize edge detection ignores incompatible screen edges")
func resizeEdgeDetectionIgnoresIncompatibleEdges() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let horizontalDockAtLeft = CGRect(x: 0, y: 300, width: 520, height: 72)
    let verticalDockAtTop = CGRect(x: 700, y: 480, width: 72, height: 420)

    #expect(DockPanelResizeGeometry.dockedEdge(
        of: horizontalDockAtLeft,
        in: visibleFrame,
        orientation: .horizontal,
        tolerance: 2
    ) == nil)
    #expect(DockPanelResizeGeometry.dockedEdge(
        of: verticalDockAtTop,
        in: visibleFrame,
        orientation: .vertical,
        tolerance: 2
    ) == nil)
}

@Test("Resize edge detection respects its tolerance")
func resizeEdgeDetectionRespectsTolerance() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let nearlyBottomDock = CGRect(x: 460, y: 2, width: 520, height: 72)

    #expect(DockPanelResizeGeometry.dockedEdge(
        of: nearlyBottomDock,
        in: visibleFrame,
        orientation: .horizontal,
        tolerance: 2
    ) == .bottom)
    #expect(DockPanelResizeGeometry.dockedEdge(
        of: nearlyBottomDock,
        in: visibleFrame,
        orientation: .horizontal,
        tolerance: 1
    ) == nil)
}

@Test("Composed resize geometry preserves a physically snapped edge")
func composedResizeGeometryPreservesPhysicalEdge() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let reference = CGRect(x: 460, y: 828, width: 520, height: 72)
    let edge = DockPanelResizeGeometry.dockedEdge(
        of: reference,
        in: visibleFrame,
        orientation: .horizontal,
        tolerance: 2
    )
    let resized = DockPanelResizeGeometry.anchoredFrame(
        from: reference,
        size: CGSize(width: 760, height: 108),
        orientation: .horizontal,
        dockedEdge: edge
    )

    #expect(edge == .top)
    #expect(resized.maxY == visibleFrame.maxY)
}

@Test("Horizontal dock resizing keeps the trailing handle's opposite corner fixed")
func horizontalResizeKeepsOppositeCornerFixed() {
    let reference = CGRect(x: 120, y: 40, width: 400, height: 70)
    let resized = DockPanelResizeGeometry.anchoredFrame(
        from: reference,
        size: CGSize(width: 560, height: 96),
        orientation: .horizontal,
        dockedEdge: .bottom
    )

    #expect(resized.minX == reference.minX)
    #expect(resized.minY == reference.minY)
}

@Test("Top horizontal docks grow down while preserving the screen edge")
func topHorizontalResizePreservesTopEdge() {
    let reference = CGRect(x: 120, y: 790, width: 400, height: 70)
    let resized = DockPanelResizeGeometry.anchoredFrame(
        from: reference,
        size: CGSize(width: 560, height: 96),
        orientation: .horizontal,
        dockedEdge: .top
    )

    #expect(resized.minX == reference.minX)
    #expect(resized.maxY == reference.maxY)
}

@Test("Right vertical docks preserve the right edge and top resize anchor")
func rightVerticalResizePreservesDockAndHandleAnchors() {
    let reference = CGRect(x: 1370, y: 250, width: 70, height: 400)
    let resized = DockPanelResizeGeometry.anchoredFrame(
        from: reference,
        size: CGSize(width: 96, height: 560),
        orientation: .vertical,
        dockedEdge: .right
    )

    #expect(resized.maxX == reference.maxX)
    #expect(resized.maxY == reference.maxY)
}

@Test("Left vertical docks preserve the left edge and top resize anchor")
func leftVerticalResizePreservesDockAndHandleAnchors() {
    let reference = CGRect(x: 0, y: 250, width: 70, height: 400)
    let resized = DockPanelResizeGeometry.anchoredFrame(
        from: reference,
        size: CGSize(width: 96, height: 560),
        orientation: .vertical,
        dockedEdge: .left
    )

    #expect(resized.minX == reference.minX)
    #expect(resized.maxY == reference.maxY)
}

@Test("Repeated live resize frames use one stable reference")
func repeatedResizeUsesStableReference() {
    let reference = CGRect(x: 1370, y: 250, width: 70, height: 400)
    let first = DockPanelResizeGeometry.anchoredFrame(
        from: reference,
        size: CGSize(width: 80, height: 440),
        orientation: .vertical,
        dockedEdge: .right
    )
    let second = DockPanelResizeGeometry.anchoredFrame(
        from: reference,
        size: CGSize(width: 96, height: 560),
        orientation: .vertical,
        dockedEdge: .right
    )

    #expect(first.maxX == second.maxX)
    #expect(first.maxY == second.maxY)
    #expect(second.maxX == reference.maxX)
    #expect(second.maxY == reference.maxY)
}

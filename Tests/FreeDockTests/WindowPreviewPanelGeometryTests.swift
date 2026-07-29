import Foundation
import Testing
@testable import FreeDock

@Test("Window previews open inward from every docked screen edge")
func windowPreviewPanelOpensInwardFromDockedEdges() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let size = CGSize(width: 320, height: 210)

    let bottom = WindowPreviewPanelGeometry.placement(
        size: size,
        sourceRect: CGRect(x: 690, y: 14, width: 60, height: 60),
        dockFrame: CGRect(x: 520, y: 0, width: 400, height: 82),
        visibleFrame: visibleFrame,
        orientation: .horizontal,
        dockedEdge: .bottom
    )
    #expect(bottom.side == .above)
    #expect(bottom.frame.minY >= 82)

    let top = WindowPreviewPanelGeometry.placement(
        size: size,
        sourceRect: CGRect(x: 690, y: 826, width: 60, height: 60),
        dockFrame: CGRect(x: 520, y: 818, width: 400, height: 82),
        visibleFrame: visibleFrame,
        orientation: .horizontal,
        dockedEdge: .top
    )
    #expect(top.side == .below)
    #expect(top.frame.maxY <= 826)

    let left = WindowPreviewPanelGeometry.placement(
        size: size,
        sourceRect: CGRect(x: 14, y: 420, width: 60, height: 60),
        dockFrame: CGRect(x: 0, y: 250, width: 82, height: 400),
        visibleFrame: visibleFrame,
        orientation: .vertical,
        dockedEdge: .left
    )
    #expect(left.side == .right)
    #expect(left.frame.minX >= 82)

    let right = WindowPreviewPanelGeometry.placement(
        size: size,
        sourceRect: CGRect(x: 1366, y: 420, width: 60, height: 60),
        dockFrame: CGRect(x: 1358, y: 250, width: 82, height: 400),
        visibleFrame: visibleFrame,
        orientation: .vertical,
        dockedEdge: .right
    )
    #expect(right.side == .left)
    #expect(right.frame.maxX <= 1366)
}

@Test("Window previews flip when the inward side has less capacity")
func windowPreviewPanelFlipsToRoomierSide() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 700)
    let sourceRect = CGRect(x: 470, y: 610, width: 60, height: 60)

    let placement = WindowPreviewPanelGeometry.placement(
        size: CGSize(width: 420, height: 260),
        sourceRect: sourceRect,
        dockFrame: CGRect(x: 300, y: 590, width: 400, height: 90),
        visibleFrame: visibleFrame,
        orientation: .horizontal,
        dockedEdge: .bottom
    )

    #expect(placement.side == .below)
    #expect(placement.frame.maxY <= sourceRect.minY - 8)
}

@Test("Window previews stay bounded on negative-origin displays")
func windowPreviewPanelHandlesNegativeDisplayOrigins() {
    let visibleFrame = CGRect(
        x: -1600,
        y: -900,
        width: 1600,
        height: 900
    )
    let availableFrame = visibleFrame.insetBy(dx: 8, dy: 8)
    let sourceRect = CGRect(x: -1586, y: -490, width: 58, height: 58)

    let placement = WindowPreviewPanelGeometry.placement(
        size: CGSize(width: 500, height: 420),
        sourceRect: sourceRect,
        dockFrame: CGRect(x: -1600, y: -620, width: 82, height: 360),
        visibleFrame: visibleFrame,
        orientation: .vertical,
        dockedEdge: .left
    )

    #expect(placement.side == .right)
    #expect(availableFrame.contains(placement.frame))
    #expect(placement.frame.minX >= sourceRect.maxX + 8)
}

@Test("Oversized window previews are bounded to the visible frame")
func oversizedWindowPreviewPanelIsBounded() {
    let visibleFrame = CGRect(x: 50, y: 30, width: 420, height: 280)
    let availableFrame = visibleFrame.insetBy(dx: 8, dy: 8)

    let placement = WindowPreviewPanelGeometry.placement(
        size: CGSize(width: 900, height: 700),
        sourceRect: CGRect(x: 225, y: 35, width: 70, height: 55),
        dockFrame: CGRect(x: 120, y: 30, width: 280, height: 65),
        visibleFrame: visibleFrame,
        orientation: .horizontal,
        dockedEdge: .bottom
    )

    #expect(placement.frame.width == availableFrame.width)
    #expect(placement.frame.height <= availableFrame.height)
    #expect(availableFrame.contains(placement.frame))
}

@Test("Compact previews shrink to avoid covering their source")
func compactWindowPreviewPanelAvoidsSource() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 360, height: 240)
    let availableFrame = visibleFrame.insetBy(dx: 8, dy: 8)
    let sourceRect = CGRect(x: 150, y: 10, width: 60, height: 45)

    let placement = WindowPreviewPanelGeometry.placement(
        size: CGSize(width: 500, height: 300),
        sourceRect: sourceRect,
        dockFrame: CGRect(x: 70, y: 0, width: 220, height: 60),
        visibleFrame: visibleFrame,
        orientation: .horizontal,
        dockedEdge: .bottom
    )

    #expect(placement.side == .above)
    #expect(placement.frame.width == availableFrame.width)
    #expect(placement.frame.minY >= sourceRect.maxY + 8)
    #expect(!placement.frame.intersects(sourceRect))
    #expect(availableFrame.contains(placement.frame))
}

@Test("Zero source rectangles anchor previews at the inward dock boundary")
func zeroSourceWindowPreviewUsesDockBoundary() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let dockFrame = CGRect(x: 400, y: 0, width: 400, height: 74)

    let placement = WindowPreviewPanelGeometry.placement(
        size: CGSize(width: 320, height: 210),
        sourceRect: .zero,
        dockFrame: dockFrame,
        visibleFrame: visibleFrame,
        orientation: .horizontal,
        dockedEdge: .bottom
    )

    #expect(placement.side == .above)
    #expect(placement.frame.minY == dockFrame.maxY + 8)
    #expect(placement.frame.midX == dockFrame.midX)
}

@Test("Floating docks infer preview direction from their orientation and position")
func floatingWindowPreviewInfersDirection() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 800)

    let horizontal = WindowPreviewPanelGeometry.placement(
        size: CGSize(width: 320, height: 210),
        sourceRect: CGRect(x: 570, y: 150, width: 60, height: 60),
        dockFrame: CGRect(x: 400, y: 140, width: 400, height: 80),
        visibleFrame: visibleFrame,
        orientation: .horizontal,
        dockedEdge: nil
    )
    #expect(horizontal.side == .above)

    let vertical = WindowPreviewPanelGeometry.placement(
        size: CGSize(width: 320, height: 210),
        sourceRect: CGRect(x: 1020, y: 370, width: 60, height: 60),
        dockFrame: CGRect(x: 1010, y: 220, width: 80, height: 360),
        visibleFrame: visibleFrame,
        orientation: .vertical,
        dockedEdge: nil
    )
    #expect(vertical.side == .left)
}

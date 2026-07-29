import Foundation
import Testing
@testable import FreeDock

@Test("Bottom horizontal docks place folder stacks above the source")
func folderStackPanelAppearsAboveBottomDock() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let dockFrame = CGRect(x: 500, y: 0, width: 440, height: 80)
    let sourceRect = CGRect(x: 620, y: 18, width: 56, height: 56)

    let placement = FolderStackPanelGeometry.placement(
        size: CGSize(width: 492, height: 424),
        sourceRect: sourceRect,
        dockFrame: dockFrame,
        visibleFrame: visibleFrame,
        orientation: .horizontal
    )

    #expect(placement.side == .above)
    #expect(placement.frame.minY > sourceRect.maxY)
    #expect(visibleFrame.insetBy(dx: 12, dy: 12).contains(placement.frame))
}

@Test("Folder stack panels flip when the preferred side lacks room")
func folderStackPanelFlipsToAvailableSide() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 700)
    let dockFrame = CGRect(x: 300, y: 310, width: 400, height: 80)
    let sourceRect = CGRect(x: 470, y: 330, width: 60, height: 60)

    let placement = FolderStackPanelGeometry.placement(
        size: CGSize(width: 460, height: 340),
        sourceRect: sourceRect,
        dockFrame: dockFrame,
        visibleFrame: visibleFrame,
        orientation: .horizontal
    )

    #expect(placement.side == .below)
    #expect(placement.frame.maxY < sourceRect.minY)
}

@Test("Vertical dock stacks open inward from the screen edge")
func folderStackPanelOpensInwardFromVerticalDock() {
    let visibleFrame = CGRect(x: -1200, y: 0, width: 1200, height: 900)
    let dockFrame = CGRect(x: -1200, y: 220, width: 78, height: 420)
    let sourceRect = CGRect(x: -1188, y: 360, width: 56, height: 56)

    let placement = FolderStackPanelGeometry.placement(
        size: CGSize(width: 492, height: 424),
        sourceRect: sourceRect,
        dockFrame: dockFrame,
        visibleFrame: visibleFrame,
        orientation: .vertical
    )

    #expect(placement.side == .right)
    #expect(placement.frame.minX > sourceRect.maxX)
}

@Test("Folder stack panels stay inside small negative-origin displays")
func folderStackPanelClampsToSmallDisplay() {
    let visibleFrame = CGRect(x: -900, y: -500, width: 700, height: 500)
    let dockFrame = CGRect(x: -500, y: -80, width: 280, height: 70)
    let sourceRect = CGRect(x: -270, y: -65, width: 48, height: 48)

    let placement = FolderStackPanelGeometry.placement(
        size: CGSize(width: 900, height: 700),
        sourceRect: sourceRect,
        dockFrame: dockFrame,
        visibleFrame: visibleFrame,
        orientation: .horizontal
    )
    let available = visibleFrame.insetBy(dx: 12, dy: 12)

    #expect(placement.frame.width == available.width)
    #expect(available.contains(placement.frame))
    #expect(!placement.frame.intersects(sourceRect))
}

@Test("Folder stack panels keep a usable size when neither side has room")
func folderStackPanelKeepsUsableFallbackSize() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 600, height: 400)
    let dockFrame = CGRect(x: 200, y: 180, width: 200, height: 80)
    let sourceRect = CGRect(x: 270, y: 190, width: 60, height: 60)

    let placement = FolderStackPanelGeometry.placement(
        size: CGSize(width: 460, height: 300),
        sourceRect: sourceRect,
        dockFrame: dockFrame,
        visibleFrame: visibleFrame,
        orientation: .horizontal
    )
    let available = visibleFrame.insetBy(dx: 12, dy: 12)

    #expect(available.contains(placement.frame))
    #expect(placement.frame.height == 300)
}

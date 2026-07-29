import AppKit
import Testing
@testable import FreeDock

@Test("Horizontal resize follows screen x and ignores y")
func horizontalResizeGestureMath() {
    let start = NSPoint(x: 100, y: 200)

    #expect(
        DockResizeGestureMath.axisDelta(
            from: start,
            to: NSPoint(x: 120, y: 80),
            orientation: .horizontal
        ) == 20
    )
    #expect(
        DockResizeGestureMath.proposedIconSize(
            startingAt: 48,
            from: start,
            to: NSPoint(x: 120, y: 80),
            orientation: .horizontal,
            resizableItemCount: 4
        ) == 53
    )
}

@Test("Vertical resize grows downward and shrinks upward")
func verticalResizeGestureMath() {
    let start = NSPoint(x: 100, y: 200)

    #expect(
        DockResizeGestureMath.proposedIconSize(
            startingAt: 48,
            from: start,
            to: NSPoint(x: 500, y: 180),
            orientation: .vertical,
            resizableItemCount: 4
        ) == 53
    )
    #expect(
        DockResizeGestureMath.proposedIconSize(
            startingAt: 48,
            from: start,
            to: NSPoint(x: -500, y: 220),
            orientation: .vertical,
            resizableItemCount: 4
        ) == 43
    )
}

@Test("Resize gesture clamps icon sizes at supported bounds")
func resizeGestureMathClampsBounds() {
    let start = NSPoint(x: 0, y: 0)

    #expect(DockResizeGestureMath.iconSizeRange == DockConfig.iconSizeRange)
    #expect(
        DockResizeGestureMath.proposedIconSize(
            startingAt: 48,
            from: start,
            to: NSPoint(x: 10_000, y: 0),
            orientation: .horizontal,
            resizableItemCount: 4
        ) == DockResizeGestureMath.iconSizeRange.upperBound
    )
    #expect(
        DockResizeGestureMath.proposedIconSize(
            startingAt: 48,
            from: start,
            to: NSPoint(x: -10_000, y: 0),
            orientation: .horizontal,
            resizableItemCount: 4
        ) == DockResizeGestureMath.iconSizeRange.lowerBound
    )
}

@Test("Resize stays smooth live and commits whole-point icon sizes")
func resizeGestureMathCommitsWholePointIconSize() {
    let start = NSPoint(x: 100, y: 100)

    let liveSize = DockResizeGestureMath.proposedIconSize(
        startingAt: 36.2125,
        from: start,
        to: NSPoint(x: 103, y: 100),
        orientation: .horizontal,
        resizableItemCount: 3
    )

    #expect(liveSize == 37.2125)
    #expect(DockResizeGestureMath.committedIconSize(liveSize) == 37)
    #expect(
        DockResizeGestureMath.proposedIconSize(
            startingAt: 40,
            from: start,
            to: NSPoint(x: 100, y: 103),
            orientation: .vertical,
            resizableItemCount: 3
        ) == 39
    )
}

@Test("Resize sensitivity keeps the handle aligned across dock sizes")
func resizeSensitivityTracksItemCount() {
    #expect(DockResizeGestureMath.sensitivity(forResizableItemCount: 0) == 1)
    #expect(DockResizeGestureMath.sensitivity(forResizableItemCount: 1) == 1)
    #expect(DockResizeGestureMath.sensitivity(forResizableItemCount: 4) == 0.25)
    #expect(DockResizeGestureMath.sensitivity(forResizableItemCount: 10) == 0.1)

    let start = NSPoint(x: 100, y: 100)
    let resized = DockResizeGestureMath.proposedIconSize(
        startingAt: 48,
        from: start,
        to: NSPoint(x: 105, y: 100),
        orientation: .horizontal,
        resizableItemCount: 10
    )

    #expect((resized - 48) * 10 == 5)
}

@Test("Separators do not affect resize sensitivity")
func separatorsDoNotAffectResizeSensitivity() {
    let items = [
        DockItem(appPath: "/Applications/One.app"),
        .separator(),
        DockItem(appPath: "/Applications/Two.app"),
        .separator(),
    ]

    #expect(DockResizeGestureMath.resizableItemCount(in: items) == 2)
}

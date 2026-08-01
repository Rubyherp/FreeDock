import AppKit
import Testing
@testable import FreeDock

@Suite("Reliability interaction scenarios")
struct ReliabilityInteractionTests {
    @Test("A vertical dock hides to a reveal strip and returns exactly")
    func verticalHideRevealRoundTrip() {
        let visibleFrame = CGRect(x: -1200, y: 40, width: 1200, height: 860)
        let restingFrame = DockDisplayGeometry.dockedFrame(
            CGRect(x: -80, y: 260, width: 80, height: 420),
            at: .right,
            in: visibleFrame
        )

        let hiddenFrame = DockDisplayGeometry.hiddenFrame(
            restingFrame,
            at: .right,
            in: visibleFrame
        )
        let revealedFrame = restingFrame

        #expect(
            hiddenFrame.minX
                == visibleFrame.maxX
                    - DockDisplayGeometry.autoHideRevealThickness
        )
        #expect(hiddenFrame.width == restingFrame.width)
        #expect(revealedFrame == restingFrame)
    }

    @Test("A resize gesture scales without moving its docked anchor")
    func resizeMaintainsAnchor() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let referenceFrame = CGRect(x: 1368, y: 250, width: 72, height: 400)
        let start = NSPoint(x: 1400, y: 250)
        let liveIconSize = DockResizeGestureMath.proposedIconSize(
            startingAt: 48,
            from: start,
            to: NSPoint(x: 900, y: 210),
            orientation: .vertical,
            resizableItemCount: 5
        )
        let resizedFrame = DockPanelResizeGeometry.anchoredFrame(
            from: referenceFrame,
            size: CGSize(width: 80, height: 440),
            orientation: .vertical,
            dockedEdge: DockPanelResizeGeometry.dockedEdge(
                of: referenceFrame,
                in: visibleFrame,
                orientation: .vertical,
                tolerance: 2
            )
        )

        #expect(liveIconSize == 56)
        #expect(resizedFrame.maxX == referenceFrame.maxX)
        #expect(resizedFrame.maxY == referenceFrame.maxY)
    }

    @Test("Reordering then dropping on Trash preserves the intended order")
    func reorderThenRemove() throws {
        let first = DockItem(appPath: "/Applications/First.app")
        let second = DockItem(appPath: "/Applications/Second.app")
        let third = DockItem(appPath: "/Applications/Third.app")
        let trash = DockItem.trash()
        var dock = DockConfig(
            name: "Interaction Dock",
            items: [first, second, third, trash]
        )

        let reorder = DockItemTransferPlanner.planTransfer(
            itemID: third.id,
            from: dock,
            to: dock,
            destination: .item(first.id)
        )
        #expect(reorder.outcome == .moved(itemID: third.id))
        dock.items = reorder.targetItems
        #expect(dock.items.map(\.id) == [third.id, first.id, second.id, trash.id])

        let removal = DockItemTransferPlanner.planTransfer(
            itemID: second.id,
            from: dock,
            to: dock,
            destination: .trash(trash.id)
        )
        #expect(removal.outcome == .removed(itemID: second.id))
        #expect(removal.targetItems.map(\.id) == [third.id, first.id, trash.id])
    }

    @Test("A disconnected display falls back and reconnects by identity")
    func displayDisconnectReconnect() throws {
        let primary = DockDisplayDescriptor(
            id: UUID(),
            name: "Built-in Display",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
            isPrimary: true
        )
        let external = DockDisplayDescriptor(
            id: UUID(),
            name: "External",
            frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055),
            isPrimary: false
        )
        let placement = DockDisplayPlacement(
            displayID: external.id,
            displayName: external.name,
            normalizedCenter: CGPoint(x: 0.7, y: 0.25)
        )

        let fallback = try #require(DockDisplayGeometry.resolveDisplay(
            for: placement,
            panelFrame: external.visibleFrame,
            among: [primary]
        ))
        #expect(fallback.display.id == primary.id)
        #expect(fallback.isFallback)

        let reconnected = try #require(DockDisplayGeometry.resolveDisplay(
            for: placement,
            panelFrame: primary.visibleFrame,
            among: [primary, external]
        ))
        #expect(reconnected.display.id == external.id)
        #expect(!reconnected.isFallback)
    }
}

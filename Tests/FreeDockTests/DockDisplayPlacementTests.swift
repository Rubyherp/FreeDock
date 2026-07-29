import Foundation
import Testing
@testable import FreeDock

@Test("Display placement normalizes negative-origin monitor coordinates")
func displayPlacementNormalizesNegativeOrigin() {
    let visibleFrame = CGRect(x: -1920, y: 0, width: 1920, height: 1050)
    let dockFrame = CGRect(x: -1510, y: 120, width: 420, height: 86)
    let center = DockDisplayGeometry.normalizedCenter(
        of: dockFrame,
        in: visibleFrame
    )
    let placement = DockDisplayPlacement(
        displayID: UUID(),
        normalizedCenter: center
    )

    let restored = DockDisplayGeometry.frame(
        size: dockFrame.size,
        placement: placement,
        in: visibleFrame
    )

    #expect(abs(restored.origin.x - dockFrame.origin.x) < 0.001)
    #expect(abs(restored.origin.y - dockFrame.origin.y) < 0.001)
}

@Test("Display placement survives resolution and arrangement changes")
func displayPlacementSurvivesResolutionChange() {
    let originalDisplay = CGRect(x: 0, y: 0, width: 1920, height: 1050)
    let originalDock = CGRect(x: 1140, y: 650, width: 360, height: 80)
    let placement = DockDisplayPlacement(
        displayID: UUID(),
        normalizedCenter: DockDisplayGeometry.normalizedCenter(
            of: originalDock,
            in: originalDisplay
        )
    )
    let changedDisplay = CGRect(x: -2560, y: 1080, width: 2560, height: 1415)

    let restored = DockDisplayGeometry.frame(
        size: originalDock.size,
        placement: placement,
        in: changedDisplay
    )
    let restoredCenter = DockDisplayGeometry.normalizedCenter(
        of: restored,
        in: changedDisplay
    )

    #expect(abs(restoredCenter.x - placement.normalizedCenter.x) < 0.001)
    #expect(abs(restoredCenter.y - placement.normalizedCenter.y) < 0.001)
}

@Test("Display placement restores exact edges and clamps oversized docks")
func displayPlacementRestoresEdgesAndOversizedFrames() {
    let visibleFrame = CGRect(x: 100, y: 200, width: 800, height: 600)
    let placement = DockDisplayPlacement(
        displayID: UUID(),
        normalizedCenter: CGPoint(x: 0.75, y: 0.25),
        edge: .top
    )

    let edgeFrame = DockDisplayGeometry.frame(
        size: CGSize(width: 300, height: 70),
        placement: placement,
        in: visibleFrame
    )
    #expect(edgeFrame.maxY == visibleFrame.maxY)

    let oversizedFrame = DockDisplayGeometry.frame(
        size: CGSize(width: 1200, height: 900),
        placement: placement,
        in: visibleFrame
    )
    #expect(oversizedFrame.origin.x == visibleFrame.minX)
    #expect(oversizedFrame.origin.y == visibleFrame.minY)
}

@Test("Display resolution favors intersection then nearest screen")
func displayGeometrySelectsBestScreen() {
    let left = DockDisplayDescriptor(
        id: UUID(),
        name: "Left",
        frame: CGRect(x: -1200, y: 0, width: 1200, height: 900),
        visibleFrame: CGRect(x: -1200, y: 0, width: 1200, height: 875),
        isPrimary: false
    )
    let right = DockDisplayDescriptor(
        id: UUID(),
        name: "Right",
        frame: CGRect(x: 200, y: 0, width: 1400, height: 1000),
        visibleFrame: CGRect(x: 200, y: 0, width: 1400, height: 975),
        isPrimary: true
    )

    let mostlyLeft = CGRect(x: -300, y: 100, width: 600, height: 100)
    #expect(
        DockDisplayGeometry.bestDisplay(
            for: mostlyLeft,
            among: [left, right]
        )?.id == left.id
    )

    let inGapNearRight = CGRect(x: 140, y: 300, width: 20, height: 20)
    #expect(
        DockDisplayGeometry.bestDisplay(
            for: inGapNearRight,
            among: [left, right]
        )?.id == right.id
    )
}

@Test("Display placement decoding clamps coordinates and tolerates future edges")
func displayPlacementDecodingIsTolerant() throws {
    let displayID = UUID()
    let data = """
    {
      "displayID": "\(displayID.uuidString)",
      "displayName": "External",
      "normalizedCenter": [4, -2],
      "edge": "future-edge"
    }
    """.data(using: .utf8)!

    let placement = try JSONDecoder().decode(
        DockDisplayPlacement.self,
        from: data
    )

    #expect(placement.displayID == displayID)
    #expect(placement.normalizedCenter == CGPoint(x: 1, y: 0))
    #expect(placement.edge == nil)
}

@Test("Display placement keeps identity when optional metadata is malformed")
func displayPlacementKeepsIdentityWithMalformedMetadata() throws {
    let displayID = UUID()
    let data = """
    {
      "displayID": "\(displayID.uuidString)",
      "displayName": ["not", "a", "name"],
      "normalizedCenter": "not-a-point",
      "edge": "right"
    }
    """.data(using: .utf8)!

    let placement = try JSONDecoder().decode(
        DockDisplayPlacement.self,
        from: data
    )

    #expect(placement.displayID == displayID)
    #expect(placement.displayName == nil)
    #expect(placement.normalizedCenter == CGPoint(x: 0.5, y: 0.5))
    #expect(placement.edge == .right)
}

@Test("Malformed display placement does not break older dock data")
func malformedDisplayPlacementFallsBackToAutomatic() throws {
    let data = """
    {
      "id": "F8CCF00C-3001-4D86-B572-1B5E4B5DBFEA",
      "name": "Legacy Dock",
      "position": [40, 80],
      "displayPlacement": {
        "displayID": "not-a-uuid",
        "normalizedCenter": [0.5, 0.5]
      },
      "orientation": "horizontal",
      "iconSize": 48,
      "items": []
    }
    """.data(using: .utf8)!

    let dock = try JSONDecoder().decode(DockConfig.self, from: data)
    #expect(dock.displayPlacement == nil)
}

@Test("Display edges are sanitized when behavior or orientation changes")
func displayEdgesAreSanitized() {
    let placement = DockDisplayPlacement(
        displayID: UUID(),
        edge: .bottom
    )
    var dock = DockConfig(
        name: "Dock",
        displayPlacement: placement,
        orientation: .horizontal,
        autoHideWhenDocked: true
    )

    dock.apply(.orientation(.vertical))
    #expect(dock.displayPlacement?.edge == nil)

    dock.displayPlacement = DockDisplayPlacement(
        displayID: placement.displayID,
        edge: .left
    )
    dock.apply(.autoHideWhenDocked(false))
    #expect(dock.displayPlacement?.edge == nil)

    let handEdited = DockConfig(
        name: "Hand Edited",
        displayPlacement: DockDisplayPlacement(
            displayID: placement.displayID,
            edge: .right
        ),
        orientation: .vertical,
        autoHideWhenDocked: false
    )
    #expect(handEdited.displayPlacement?.edge == nil)
}

@Test("Duplicate placement offsets normalized center without fabricated dock size")
func duplicatePlacementOffsetsNormalizedCenter() {
    let displayID = UUID()
    let placement = DockDisplayPlacement(
        displayID: displayID,
        displayName: "External",
        normalizedCenter: CGPoint(x: 0.4, y: 0.6),
        edge: .bottom
    )
    let visibleFrame = CGRect(x: -1600, y: 0, width: 1600, height: 900)

    let duplicate = DockDisplayGeometry.offset(
        placement,
        by: CGPoint(x: 32, y: 0),
        in: visibleFrame
    )

    #expect(abs(duplicate.normalizedCenter.x - 0.42) < 0.001)
    #expect(duplicate.normalizedCenter.y == placement.normalizedCenter.y)
    #expect(duplicate.displayID == displayID)
    #expect(duplicate.displayName == placement.displayName)
    #expect(duplicate.edge == placement.edge)
}

@Test("Display resolution uses UUID with duplicate names and stable fallback")
func displayResolutionUsesUUIDAndStableFallback() {
    let primaryID = UUID()
    let desiredID = UUID()
    let primary = DockDisplayDescriptor(
        id: primaryID,
        name: "Studio Display",
        frame: CGRect(x: 0, y: 0, width: 1200, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 875),
        isPrimary: true
    )
    let desired = DockDisplayDescriptor(
        id: desiredID,
        name: "Studio Display",
        frame: CGRect(x: 1200, y: 0, width: 1200, height: 900),
        visibleFrame: CGRect(x: 1200, y: 0, width: 1200, height: 875),
        isPrimary: false
    )
    let placement = DockDisplayPlacement(
        displayID: desiredID,
        displayName: "Studio Display",
        normalizedCenter: CGPoint(x: 0.75, y: 0.25)
    )
    let frameOnPrimary = CGRect(x: 100, y: 100, width: 300, height: 80)

    for displays in [[primary, desired], [desired, primary]] {
        let resolution = DockDisplayGeometry.resolveDisplay(
            for: placement,
            panelFrame: frameOnPrimary,
            among: displays
        )
        #expect(resolution?.display.id == desiredID)
        #expect(resolution?.isFallback == false)
    }

    let missingPlacement = DockDisplayPlacement(
        displayID: UUID(),
        displayName: "Disconnected",
        normalizedCenter: placement.normalizedCenter
    )
    let fallback = DockDisplayGeometry.resolveDisplay(
        for: missingPlacement,
        panelFrame: desired.frame,
        among: [desired, primary]
    )
    #expect(fallback?.display.id == primaryID)
    #expect(fallback?.isFallback == true)
    #expect(missingPlacement.displayName == "Disconnected")
    #expect(missingPlacement.normalizedCenter == placement.normalizedCenter)
}

@Test("Display selection tie-breaking is independent of catalog order")
func displaySelectionTieBreakingIsStable() {
    let primary = DockDisplayDescriptor(
        id: UUID(),
        name: "Left",
        frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 775),
        isPrimary: true
    )
    let right = DockDisplayDescriptor(
        id: UUID(),
        name: "Right",
        frame: CGRect(x: 1000, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 775),
        isPrimary: false
    )
    let equallySplit = CGRect(x: 800, y: 200, width: 400, height: 100)

    #expect(
        DockDisplayGeometry.bestDisplay(
            for: equallySplit,
            among: [primary, right]
        )?.id == right.id
    )
    #expect(
        DockDisplayGeometry.bestDisplay(
            for: equallySplit,
            among: [right, primary]
        )?.id == right.id
    )
}

@Test("Duplicate display names receive deterministic spatial labels")
func duplicateDisplayNamesReceiveSpatialLabels() {
    let primary = DockDisplayDescriptor(
        id: UUID(),
        name: "Studio Display",
        frame: CGRect(x: 0, y: 0, width: 1200, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 875),
        isPrimary: true
    )
    let right = DockDisplayDescriptor(
        id: UUID(),
        name: "Studio Display",
        frame: CGRect(x: 1200, y: 0, width: 1200, height: 900),
        visibleFrame: CGRect(x: 1200, y: 0, width: 1200, height: 875),
        isPrimary: false
    )

    let labeled = DockDisplayGeometry.uniquelyLabeled([right, primary])
    #expect(labeled.first(where: { $0.id == primary.id })?.label == "Studio Display")
    #expect(labeled.first(where: { $0.id == right.id })?.label == "Studio Display — Right")
}

@Test("Auto-hide avoids internal monitor seams")
func autoHideAvoidsInternalMonitorSeams() {
    let left = DockDisplayDescriptor(
        id: UUID(),
        name: "Left",
        frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 775),
        isPrimary: true
    )
    let right = DockDisplayDescriptor(
        id: UUID(),
        name: "Right",
        frame: CGRect(x: 1000, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 775),
        isPrimary: false
    )
    let dock = CGRect(x: 920, y: 250, width: 80, height: 300)

    let exposed = DockDisplayGeometry.exposedEdges(
        for: dock,
        on: left,
        among: [left, right]
    )
    #expect(!exposed.contains(.right))
    #expect(exposed.contains(.left))
    #expect(
        DockDisplayGeometry.preferredDockingEdge(
            of: dock,
            on: left,
            among: [left, right],
            orientation: .vertical
        ) == .left
    )
}

@Test("Docking clamps oversized docks safely")
func dockingClampsOversizedDocks() {
    let visibleFrame = CGRect(x: 100, y: 200, width: 800, height: 600)
    let oversized = CGRect(x: -500, y: 750, width: 1200, height: 100)

    let docked = DockDisplayGeometry.dockedFrame(
        oversized,
        at: .top,
        in: visibleFrame
    )

    #expect(docked.origin.x == visibleFrame.minX)
    #expect(docked.maxY == visibleFrame.maxY)
}

@Test("Temporary clamping does not replace the durable normalized center")
func temporaryClampingPreservesDurableCenter() {
    let placement = DockDisplayPlacement(
        displayID: UUID(),
        normalizedCenter: CGPoint(x: 0.8, y: 0.5)
    )
    let small = CGRect(x: 0, y: 0, width: 500, height: 400)
    let large = CGRect(x: 0, y: 0, width: 2000, height: 1200)
    let size = CGSize(width: 400, height: 80)

    let temporarilyClamped = DockDisplayGeometry.frame(
        size: size,
        placement: placement,
        in: small
    )
    let restored = DockDisplayGeometry.frame(
        size: size,
        placement: placement,
        in: large
    )

    #expect(
        DockDisplayGeometry.normalizedCenter(
            of: temporarilyClamped,
            in: small
        ).x != placement.normalizedCenter.x
    )
    #expect(
        abs(
            DockDisplayGeometry.normalizedCenter(
                of: restored,
                in: large
            ).x - placement.normalizedCenter.x
        ) < 0.001
    )
}

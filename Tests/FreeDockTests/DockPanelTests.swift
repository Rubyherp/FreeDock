import Cocoa
import SwiftUI
import Testing
@testable import FreeDock

@MainActor
@Test("Dock panel accepts key focus only during Quick Launch")
func dockPanelScopesKeyFocusToQuickLaunch() {
    _ = NSApplication.shared
    let panel = DockPanel(
        dockID: UUID(),
        contentRect: NSRect(x: 0, y: 0, width: 240, height: 80)
    )
    defer { panel.tearDown() }

    #expect(!panel.canBecomeKey)
    #expect(!panel.isMovableByWindowBackground)

    panel.setQuickLaunchKeyMode(true)
    #expect(panel.canBecomeKey)

    panel.setQuickLaunchKeyMode(false)
    #expect(!panel.canBecomeKey)

    panel.setPositionLocked(false)
    #expect(!panel.isMovableByWindowBackground)

    panel.setContentView(EmptyView())
    #expect(panel.contentView?.mouseDownCanMoveWindow == false)
    #expect(panel.contentView?.subviews.first?.mouseDownCanMoveWindow == false)
    #expect(panel.contentView?.subviews.first?.acceptsFirstMouse(for: nil) == true)
}

@MainActor
@Test("Hidden dock reveal tracking remains active during Finder drags")
func hiddenDockRevealTrackingSupportsExternalDrags() throws {
    _ = NSApplication.shared
    let container = DockContainerView(
        frame: NSRect(x: 0, y: 0, width: 240, height: 80)
    )
    container.updateTrackingAreas()

    let trackingArea = try #require(
        container.trackingAreas.first {
            $0.owner === container
        }
    )
    let options = trackingArea.options
    #expect(options.contains(.mouseEnteredAndExited))
    #expect(options.contains(.activeAlways))
    #expect(options.contains(.enabledDuringMouseDrag))
    #expect(options.contains(.inVisibleRect))
}

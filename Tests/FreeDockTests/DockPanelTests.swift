import Cocoa
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

    panel.setQuickLaunchKeyMode(true)
    #expect(panel.canBecomeKey)

    panel.setQuickLaunchKeyMode(false)
    #expect(!panel.canBecomeKey)
}

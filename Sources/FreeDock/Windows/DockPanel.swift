import Cocoa
import SwiftUI

class DockPanel: NSPanel {
    let dockID: UUID

    init(dockID: UUID, contentRect: NSRect) {
        self.dockID = dockID
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
    }

    func setContentView<V: View>(_ view: V) {
        let container = NSView(frame: NSRect(origin: .zero, size: NSSize(width: 400, height: 70)))
        let hosting = NSHostingView(rootView: view)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 14
        hosting.layer?.masksToBounds = true
        container.addSubview(hosting)
        contentView = container
        container.setFrameSize(hosting.intrinsicContentSize)
        setContentSize(container.frame.size)
    }

    /// Prevent docks from landing off-screen (e.g., after monitor disconnect)
    func clampToVisibleFrame() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        var f = frame
        f.origin.x = min(max(f.origin.x, vf.minX), vf.maxX - f.width)
        f.origin.y = min(max(f.origin.y, vf.minY), vf.maxY - f.height)
        setFrame(f, display: true)
    }
}

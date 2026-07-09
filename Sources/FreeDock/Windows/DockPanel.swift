import Cocoa
import SwiftUI

class DockPanel: NSPanel {
    let dockID: UUID
    var dockOrientation: Orientation = .horizontal
    weak var dockDelegate: DockPanelDelegate?

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
        hidesOnDeactivate = false
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
        let intrinsicSize = hosting.intrinsicContentSize
        let enforcedSize = NSSize(
            width: max(intrinsicSize.width, 320),
            height: max(intrinsicSize.height, 72)
        )
        container.setFrameSize(enforcedSize)
        hosting.frame = container.bounds
        setContentSize(enforcedSize)
    }

    func addDragHandle(orientation: Orientation) {
        guard let container = contentView else { return }
        let stripWidth: CGFloat = 24
        let handle: DockDragHandleView

        if orientation == .horizontal {
            handle = DockDragHandleView(
                frame: NSRect(
                    x: 102, // change handle position, shift to the right
                    y: -10, // make the handle longer towards -10
                    width: 24,
                    height: container.bounds.height - 16,
                )
            )
            handle.autoresizingMask = [.height, .maxXMargin]
        } else {
            handle = DockDragHandleView(
                frame: NSRect(
                    x: -10,
                    y: container.bounds.height - 20,
                    width: container.bounds.width - 16,
                    height: 24,
                )
            )
            handle.autoresizingMask = [.width, .maxYMargin]
        }

        handle.wantsLayer = true
        handle.layer?.backgroundColor = NSColor.clear.cgColor
        handle.dockPanel = self
        container.addSubview(handle)
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

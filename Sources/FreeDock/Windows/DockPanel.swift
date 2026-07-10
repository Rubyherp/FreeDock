import Cocoa
import SwiftUI

class DockPanel: NSPanel {
    let dockID: UUID
    var dockOrientation: Orientation = .horizontal
    weak var dockDelegate: DockPanelDelegate?
    private weak var hostingView: NSView?
    private var containerView: NSView?
    private var hideWorkItem: DispatchWorkItem?

    private func enforcedSize(for intrinsicSize: NSSize) -> NSSize {
        if dockOrientation == .vertical {
            return NSSize(
                width: max(intrinsicSize.width, 72),
                height: max(intrinsicSize.height, 320)
            )
        }
        return NSSize(
            width: max(intrinsicSize.width, 320),
            height: max(intrinsicSize.height, 72)
        )
    }

    init(dockID: UUID, contentRect: NSRect) {
        self.dockID = dockID
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        alphaValue = 1.0
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
        let container = DockContainerView(frame: NSRect(origin: .zero, size: NSSize(width: 400, height: 70)))
        container.dockPanel = self
        containerView = container

        let hosting = NSHostingView(rootView: view)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 14
        hosting.layer?.masksToBounds = true
        container.addSubview(hosting)
        hostingView = hosting
        contentView = container
        let intrinsicSize = hosting.intrinsicContentSize
        let enforcedSize = enforcedSize(for: intrinsicSize)
        container.setFrameSize(enforcedSize)
        hosting.frame = container.bounds
        setContentSize(enforcedSize)
    }

    func resizeToFitContent() {
        guard let container = contentView,
              let hosting = hostingView
        else { return }

        hosting.invalidateIntrinsicContentSize()
        let intrinsicSize = hosting.fittingSize
        let enforcedSize = enforcedSize(for: intrinsicSize)
        container.setFrameSize(enforcedSize)
        hosting.frame = container.bounds
        setContentSize(enforcedSize)
    }

    func addDragHandle(orientation: Orientation) {
        guard let container = containerView else {
            print("containerView is nil")
            return
        }
        let handle = DockDragHandleView(frame: container.bounds)

        handle.autoresizingMask = [.width, .height]
        handle.orientation = orientation
        handle.wantsLayer = true
        handle.layer?.backgroundColor = NSColor.clear.cgColor
        handle.dockPanel = self
        container.addSubview(handle, positioned: .above, relativeTo: nil)
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

    func scheduleAutoHide() {
        hideWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                self.animator().alphaValue = 0.40
            }
        }

        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.0, execute: work)
    }

    func cancelAutoHide() {
        hideWorkItem?.cancel()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.40
            self.animator().alphaValue = 1.0
        }
    }
}

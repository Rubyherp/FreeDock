import Cocoa
import OSLog
import SwiftUI

class DockPanel: NSPanel, NSWindowDelegate {
    let dockID: UUID
    var dockOrientation: Orientation = .horizontal
    var autoHideDelay: TimeInterval = 1
    var allowedAutoHideEdges = Set(DockScreenEdge.allCases)
    var autoHideWhenDocked = true {
        didSet {
            guard oldValue != autoHideWhenDocked else { return }
            if autoHideWhenDocked {
                updateAutoHideEdge()
            } else {
                autoHideEdge = nil
                cancelAutoHide()
                shownFrame = nil
            }
        }
    }
    weak var dockDelegate: DockPanelDelegate?
    private weak var hostingView: NSView?
    private var hideWorkItem: DispatchWorkItem?
    private var autoHideEdge: DockScreenEdge?
    private var shownFrame: NSRect?
    private var isAutoHidden = false
    private var isUserMovingWindow = false
    private var moveCompletionWorkItem: DispatchWorkItem?

    private let edgeTolerance: CGFloat = 2
    private let revealThickness = DockDisplayGeometry.autoHideRevealThickness

    /// The frame users expect to restore to, even while an edge-docked panel is hidden.
    var frameForPersistence: NSRect {
        shownFrame ?? frame
    }

    private func enforcedSize(for intrinsicSize: NSSize) -> NSSize {
        if dockOrientation == .vertical {
            return NSSize(
                width: max(intrinsicSize.width, 58),
                height: max(intrinsicSize.height, 86)
            )
        }
        return NSSize(
            width: max(intrinsicSize.width, 86),
            height: max(intrinsicSize.height, 58)
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
        // The shelf draws its own shape-aware shadow; a window shadow would outline
        // the transparent magnification headroom as a second, rectangular border.
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        delegate = self
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        isAutoHidden ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }

    func windowWillMove(_: Notification) {
        guard !isAutoHidden else { return }
        isUserMovingWindow = true
        hideWorkItem?.cancel()
    }

    func windowDidMove(_: Notification) {
        guard isUserMovingWindow else { return }
        moveCompletionWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isUserMovingWindow = false
            self.dockDelegate?.dockPanelDidMove(self)
        }
        moveCompletionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func setContentView<V: View>(_ view: V) {
        let container = DockContainerView(frame: NSRect(origin: .zero, size: NSSize(width: 400, height: 70)))
        container.dockPanel = self

        let hosting = NSHostingView(rootView: view)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        // Corner treatment belongs to the shelf itself, not the larger transparent
        // hosting view that also reserves room for icon magnification.
        hosting.layer?.cornerRadius = 0
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

        let originalFrame = frame
        let preservedEdge = autoHideEdge
        hosting.invalidateIntrinsicContentSize()
        let intrinsicSize = hosting.fittingSize
        let enforcedSize = enforcedSize(for: intrinsicSize)
        setContentSize(enforcedSize)

        var anchoredFrame = frame
        anchoredFrame.size = enforcedSize

        if preservedEdge == .right {
            anchoredFrame.origin.x = originalFrame.maxX - enforcedSize.width
        } else {
            anchoredFrame.origin.x = originalFrame.minX
        }

        if dockOrientation == .horizontal {
            anchoredFrame.origin.y = preservedEdge == .top
                ? originalFrame.maxY - enforcedSize.height
                : originalFrame.minY
        } else {
            anchoredFrame.origin.y = preservedEdge == .bottom
                ? originalFrame.minY
                : originalFrame.maxY - enforcedSize.height
        }

        setFrame(anchoredFrame, display: true)
        container.setFrameSize(enforcedSize)
        hosting.frame = container.bounds
    }

    /// Prevent docks from landing off-screen (e.g., after monitor disconnect)
    func clampToVisibleFrame(on preferredScreen: NSScreen? = nil) {
        guard let screen = preferredScreen ?? activeScreen ?? NSScreen.screens.first else {
            return
        }
        let vf = screen.visibleFrame
        setFrame(DockDisplayGeometry.clamped(frame, to: vf), display: true)
        updateAutoHideEdge()
    }

    /// Enables slide-away auto-hide only when this dock rests on a screen edge.
    func updateAutoHideEdge() {
        guard autoHideWhenDocked,
              !isAutoHidden,
              let visibleFrame = activeScreen?.visibleFrame
        else { return }

        let currentFrame = frame
        shownFrame = currentFrame

        let candidates: [(DockScreenEdge, CGFloat)] = [
            (.left, abs(currentFrame.minX - visibleFrame.minX)),
            (.right, abs(currentFrame.maxX - visibleFrame.maxX)),
            (.bottom, abs(currentFrame.minY - visibleFrame.minY)),
            (.top, abs(currentFrame.maxY - visibleFrame.maxY)),
        ].filter { allowedAutoHideEdges.contains($0.0) }

        autoHideEdge = candidates.min { $0.1 < $1.1 }.flatMap {
            $0.1 <= edgeTolerance ? $0.0 : nil
        }
    }

    func scheduleAutoHide() {
        hideWorkItem?.cancel()

        guard autoHideWhenDocked,
              let edge = autoHideEdge,
              let visibleFrame = activeScreen?.visibleFrame,
              let restingFrame = shownFrame
        else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isAutoHidden else { return }

            self.isAutoHidden = true
            self.dockContainer?.showRevealIndicator(at: self.revealEdge(for: edge))
            self.hostingView?.alphaValue = 0
            self.hostingView?.isHidden = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(
                    self.hiddenFrame(for: restingFrame, at: edge, in: visibleFrame),
                    display: true
                )
            }
        }

        hideWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0.1, autoHideDelay),
            execute: work
        )
    }

    func cancelAutoHide() {
        hideWorkItem?.cancel()
        guard isAutoHidden, let restingFrame = shownFrame else { return }

        isAutoHidden = false
        hostingView?.isHidden = false
        hostingView?.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.hostingView?.animator().alphaValue = 1
            self.animator().setFrame(restingFrame, display: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.dockContainer?.hideRevealIndicator()
        }
    }

    func revealImmediately() {
        hideWorkItem?.cancel()
        guard isAutoHidden, let restingFrame = shownFrame else { return }
        isAutoHidden = false
        hostingView?.isHidden = false
        hostingView?.alphaValue = 1
        dockContainer?.hideRevealIndicator()
        setFrame(restingFrame, display: true)
    }

    func tearDown() {
        hideWorkItem?.cancel()
        moveCompletionWorkItem?.cancel()
        isUserMovingWindow = false
        isAutoHidden = false
        dockContainer?.hideRevealIndicator()
        hostingView?.isHidden = false
        hostingView?.alphaValue = 1
        dockDelegate = nil
        delegate = nil
        orderOut(nil)
        contentView = nil
        close()
    }

    private var dockContainer: DockContainerView? {
        contentView as? DockContainerView
    }

    private func revealEdge(for edge: DockScreenEdge) -> DockRevealEdge {
        switch edge {
        case .left: return .left
        case .right: return .right
        case .top: return .top
        case .bottom: return .bottom
        }
    }

    private var activeScreen: NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })
            ?? screen
            ?? NSScreen.main
    }

    private func hiddenFrame(
        for frame: NSRect,
        at edge: DockScreenEdge,
        in visibleFrame: NSRect
    ) -> NSRect {
        var hidden = frame

        switch edge {
        case .left:
            hidden.origin.x = visibleFrame.minX - frame.width + revealThickness
        case .right:
            hidden.origin.x = visibleFrame.maxX - revealThickness
        case .bottom:
            hidden.origin.y = visibleFrame.minY - frame.height + revealThickness
        case .top:
            hidden.origin.y = visibleFrame.maxY - revealThickness
        }

        return hidden
    }
}

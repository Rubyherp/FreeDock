import Cocoa
import OSLog
import SwiftUI

private final class DockHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}

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
    private var revealCompletionWorkItem: DispatchWorkItem?
    private var autoHideEdge: DockScreenEdge?
    private var shownFrame: NSRect?
    private var isAutoHidden = false
    private var isAutoHideRevealInProgress = false
    private var isUserMovingWindow = false
    private var moveCompletionWorkItem: DispatchWorkItem?
    private var transientInteractionTokens = Set<UUID>()
    private var menuInteractionTokens: [ObjectIdentifier: UUID] = [:]
    private var resizeInteractionTokens = Set<UUID>()
    private var resizeReferenceFrame: NSRect?
    private var resizeReferenceEdge: DockScreenEdge?
    private var quickLaunchKeyModeEnabled = false

    private let edgeTolerance: CGFloat = 2
    private let revealThickness = DockDisplayGeometry.autoHideRevealThickness

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    override var canBecomeKey: Bool { quickLaunchKeyModeEnabled }
    override var canBecomeMain: Bool { false }

    /// The frame users expect to restore to, even while an edge-docked panel is hidden.
    var frameForPersistence: NSRect {
        shownFrame ?? frame
    }

    var dockedEdgeForLayout: DockScreenEdge? {
        resizeAnchorEdge(for: frameForPersistence)
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
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        delegate = self

        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(
            self,
            selector: #selector(menuDidBeginTracking(_:)),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(menuDidEndTracking(_:)),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        isAutoHidden ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }

    func windowWillMove(_: Notification) {
        guard !isAutoHidden, resizeInteractionTokens.isEmpty else { return }
        isUserMovingWindow = true
        hideWorkItem?.cancel()
    }

    func windowDidMove(_: Notification) {
        guard isUserMovingWindow, resizeInteractionTokens.isEmpty else { return }
        moveCompletionWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isUserMovingWindow = false
            self.dockDelegate?.dockPanelDidMove(self)
        }
        moveCompletionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func windowDidResignKey(_: Notification) {
        dockDelegate?.dockPanelDidResignKey(self)
    }

    func setQuickLaunchKeyMode(_ enabled: Bool) {
        quickLaunchKeyModeEnabled = enabled
    }

    func setPositionLocked(_: Bool) {
        // Moving is owned exclusively by DockDragHandleView so AppKit never
        // mistakes an icon reorder gesture for a background-window drag.
        isMovableByWindowBackground = false
    }

    func setContentView<V: View>(_ view: V) {
        let container = DockContainerView(frame: NSRect(origin: .zero, size: NSSize(width: 400, height: 70)))
        container.dockPanel = self

        let hosting = DockHostingView(rootView: view)
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

        let isInteractiveResize = !resizeInteractionTokens.isEmpty
        let originalFrame = isInteractiveResize
            ? (resizeReferenceFrame ?? frame)
            : frame
        let preservedEdge = isInteractiveResize
            ? resizeReferenceEdge
            : resizeAnchorEdge(for: originalFrame)
        hosting.invalidateIntrinsicContentSize()
        let intrinsicSize = hosting.fittingSize
        let enforcedSize = enforcedSize(for: intrinsicSize)
        let anchoredFrame = DockPanelResizeGeometry.anchoredFrame(
            from: originalFrame,
            size: enforcedSize,
            orientation: dockOrientation,
            dockedEdge: preservedEdge
        )

        setFrame(anchoredFrame, display: true)
        container.setFrameSize(enforcedSize)
        hosting.frame = container.bounds
        if shownFrame != nil {
            shownFrame = anchoredFrame
        }
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
              transientInteractionTokens.isEmpty,
              let edge = autoHideEdge,
              let visibleFrame = activeScreen?.visibleFrame,
              let restingFrame = shownFrame
        else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isAutoHidden else { return }

            self.revealCompletionWorkItem?.cancel()
            self.revealCompletionWorkItem = nil
            self.isAutoHideRevealInProgress = false
            self.isAutoHidden = true
            self.dockContainer?.showRevealIndicator(at: self.revealEdge(for: edge))
            self.hostingView?.alphaValue = 0
            self.hostingView?.isHidden = true
            let hiddenFrame = self.hiddenFrame(
                for: restingFrame,
                at: edge,
                in: visibleFrame
            )
            if DockMotionPolicy.shouldAnimate(
                reduceMotion: self.reduceMotion
            ) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = DockMotionPolicy.duration(
                        0.24,
                        reduceMotion: self.reduceMotion
                    )
                    context.timingFunction = CAMediaTimingFunction(
                        name: .easeInEaseOut
                    )
                    self.animator().setFrame(hiddenFrame, display: true)
                }
            } else {
                self.setFrame(hiddenFrame, display: true)
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
        isAutoHideRevealInProgress = true
        revealCompletionWorkItem?.cancel()
        hostingView?.isHidden = false
        if reduceMotion {
            hostingView?.alphaValue = 1
            setFrame(restingFrame, display: true)
            isAutoHideRevealInProgress = false
            dockContainer?.hideRevealIndicator()
            return
        }

        hostingView?.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DockMotionPolicy.duration(
                0.28,
                reduceMotion: self.reduceMotion
            )
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.hostingView?.animator().alphaValue = 1
            self.animator().setFrame(restingFrame, display: true)
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isAutoHideRevealInProgress = false
            self.revealCompletionWorkItem = nil
            self.dockContainer?.hideRevealIndicator()
        }
        revealCompletionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func revealImmediately() {
        hideWorkItem?.cancel()
        guard isAutoHidden || isAutoHideRevealInProgress,
              let restingFrame = shownFrame
        else { return }

        revealCompletionWorkItem?.cancel()
        revealCompletionWorkItem = nil
        isAutoHideRevealInProgress = false
        isAutoHidden = false
        hostingView?.isHidden = false
        hostingView?.alphaValue = 1
        dockContainer?.hideRevealIndicator()
        setFrame(restingFrame, display: true)
    }

    /// Keeps the dock visible while a child interaction, such as a folder stack,
    /// is open. Tokens allow independent interactions to overlap safely.
    func beginTransientInteraction() -> UUID {
        let token = UUID()
        transientInteractionTokens.insert(token)
        revealImmediately()
        hideWorkItem?.cancel()
        return token
    }

    func endTransientInteraction(_ token: UUID) {
        guard transientInteractionTokens.remove(token) != nil,
              transientInteractionTokens.isEmpty
        else {
            return
        }
        updateAutoHideEdge()
        if !pointerIsOverDock {
            scheduleAutoHide()
        }
    }

    @objc private func menuDidBeginTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        let menuID = ObjectIdentifier(menu)
        guard menuInteractionTokens[menuID] == nil else { return }

        let menuAlreadyBelongsToDock = !menuInteractionTokens.isEmpty
        guard menuAlreadyBelongsToDock || pointerIsOverDock else { return }

        dockDelegate?.dockPanelMenuDidBeginTracking(self)
        menuInteractionTokens[menuID] = beginTransientInteraction()
    }

    @objc private func menuDidEndTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
              let token = menuInteractionTokens.removeValue(
                  forKey: ObjectIdentifier(menu)
              )
        else {
            return
        }
        endTransientInteraction(token)
    }

    /// Holds the panel steady for the duration of an interactive resize.
    ///
    /// The token makes cleanup safe when AppKit interrupts a drag because the
    /// view is removed, the mouse-up arrives elsewhere, or the panel closes.
    func beginResizeInteraction() -> UUID {
        let token = UUID()
        let isFirstResizeInteraction = resizeInteractionTokens.isEmpty
        resizeInteractionTokens.insert(token)
        transientInteractionTokens.insert(token)

        guard isFirstResizeInteraction else { return token }

        moveCompletionWorkItem?.cancel()
        moveCompletionWorkItem = nil
        isUserMovingWindow = false
        hideWorkItem?.cancel()
        revealImmediately()
        isMovableByWindowBackground = false
        resizeReferenceFrame = frame
        resizeReferenceEdge = resizeAnchorEdge(for: frame)
        return token
    }

    func endResizeInteraction(_ token: UUID) {
        guard resizeInteractionTokens.remove(token) != nil else { return }
        transientInteractionTokens.remove(token)
        guard resizeInteractionTokens.isEmpty else { return }

        resizeReferenceFrame = nil
        resizeReferenceEdge = nil
        if let dockDelegate {
            setPositionLocked(dockDelegate.lockPositions)
        }
        updateAutoHideEdge()
        if transientInteractionTokens.isEmpty {
            scheduleAutoHide()
        }
    }

    func tearDown() {
        hideWorkItem?.cancel()
        revealCompletionWorkItem?.cancel()
        moveCompletionWorkItem?.cancel()
        NotificationCenter.default.removeObserver(
            self,
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )
        menuInteractionTokens.removeAll()
        transientInteractionTokens.removeAll()
        resizeInteractionTokens.removeAll()
        resizeReferenceFrame = nil
        resizeReferenceEdge = nil
        quickLaunchKeyModeEnabled = false
        isUserMovingWindow = false
        isAutoHidden = false
        isAutoHideRevealInProgress = false
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

    private var pointerIsOverDock: Bool {
        dockContainer?.isPointerInside == true
            || frame.contains(NSEvent.mouseLocation)
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

    private func resizeAnchorEdge(for frame: NSRect) -> DockScreenEdge? {
        if let autoHideEdge {
            return autoHideEdge
        }
        guard let visibleFrame = activeScreen?.visibleFrame else { return nil }
        return DockPanelResizeGeometry.dockedEdge(
            of: frame,
            in: visibleFrame,
            orientation: dockOrientation,
            tolerance: edgeTolerance
        )
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

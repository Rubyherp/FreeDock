import AppKit
import SwiftUI

enum WindowPreviewPanelQueryDecision: Equatable, Sendable {
    case accept
    case retry(afterNanoseconds: UInt64)
    case close
}

enum WindowPreviewPanelQueryPolicy {
    static func decision(
        for status: DockApplicationWindowQueryStatus,
        windowCount: Int,
        retryAttempt: Int
    ) -> WindowPreviewPanelQueryDecision {
        switch status {
        case .ready:
            return windowCount > 0 ? .accept : .close
        case .temporarilyUnavailable:
            let attempt = min(max(0, retryAttempt), 3)
            let delay = UInt64(250_000_000) << attempt
            return .retry(
                afterNanoseconds: min(delay, 1_500_000_000)
            )
        case .permissionRequired, .applicationNotRunning:
            return .close
        }
    }
}

enum WindowPreviewPanelSizing {
    static let cardStride: CGFloat = 182
    static let horizontalPadding: CGFloat = 20
    static let height: CGFloat = 194

    static func preferredSize(windowCount: Int) -> CGSize {
        let visibleCardCount = min(max(1, windowCount), 3)
        return CGSize(
            width:
                CGFloat(visibleCardCount) * cardStride
                    + horizontalPadding,
            height: height
        )
    }
}

enum WindowPreviewPanelEventPolicy {
    static func shouldCloseForGlobalClick(
        monitoredSessionID: UUID?,
        currentSessionID: UUID?
    ) -> Bool {
        guard let monitoredSessionID else { return false }
        return currentSessionID == monitoredSessionID
    }
}

@MainActor
final class WindowPreviewPanelController {
    private struct Target {
        let itemID: DockItem.ID
        let bundleIdentifier: String
        let applicationName: String
        let applicationIcon: NSImage
        var sourceRect: CGRect
    }

    private let applicationWindows: DockApplicationWindowController
    private let panel = WindowPreviewPanel()
    private var hoverState = WindowPreviewHoverState()
    private var target: Target?
    private weak var sourceDock: DockPanel?
    private var windows: [DockApplicationWindow] = []
    private var thumbnails:
        [DockApplicationWindow.ID: NSImage] = [:]
    private var thumbnailLoadingIDs =
        Set<DockApplicationWindow.ID>()
    private var thumbnailUnavailableIDs =
        Set<DockApplicationWindow.ID>()
    private var openWorkItem: DispatchWorkItem?
    private var closeWorkItem: DispatchWorkItem?
    private var refreshTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var hostingView:
        WindowPreviewHostingView<WindowPreviewView>?
    private var autoHideToken: UUID?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var isExplicitPresentation = false

    init(
        applicationWindows: DockApplicationWindowController
            = DockApplicationWindowController()
    ) {
        self.applicationWindows = applicationWindows
    }

    var activeItemID: DockItem.ID? {
        target?.itemID
    }

    var sourceDockID: UUID? {
        sourceDock?.dockID
    }

    var isAccessibilityTrusted: Bool {
        applicationWindows.isAccessibilityTrusted
    }

    var isScreenCaptureTrusted: Bool {
        applicationWindows.isScreenCaptureTrusted
    }

    func enableWindowThumbnails() {
        let granted =
            applicationWindows.requestScreenCaptureAccess()
        guard granted
                || applicationWindows.isScreenCaptureTrusted
        else {
            showScreenCaptureInstructions()
            return
        }
        guard let sessionID = hoverState.session?.id else {
            return
        }
        loadThumbnails(for: sessionID)
    }

    private func showScreenCaptureInstructions() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Enable Window Thumbnails"
        alert.informativeText = """
        Allow FreeDock in System Settings → Privacy & Security → Screen Recording. macOS may ask you to reopen FreeDock after approval. Window switching continues to work without thumbnails.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func hoverBegan(
        item: DockItem,
        presentation: DockItemPresentation,
        sourceRect: CGRect,
        sourceDock: DockPanel
    ) {
        guard applicationWindows.isAccessibilityTrusted,
              item.kind == .application,
              presentation.isAvailable,
              let bundleIdentifier = presentation.bundleID,
              !bundleIdentifier.isEmpty,
              !isExplicitPresentation
        else {
            return
        }

        if hoverState.session?.itemID == item.id {
            target?.sourceRect = sourceRect
            _ = hoverState.beginIconHover(
                itemID: item.id,
                anchor: sourceRect
            )
            if panel.isVisible {
                positionPanel()
            }
            return
        }

        let retargetingVisiblePanel = panel.isVisible
        close(resetNativeController: false)
        target = Target(
            itemID: item.id,
            bundleIdentifier: bundleIdentifier,
            applicationName: presentation.displayName,
            applicationIcon: presentation.icon,
            sourceRect: sourceRect
        )
        self.sourceDock = sourceDock

        let start = hoverState.beginIconHover(
            itemID: item.id,
            anchor: sourceRect
        )
        guard start.shouldDiscover else { return }
        _ = hoverState.markDiscoveryStarted(
            sessionID: start.session.id
        )
        scheduleOpen(
            token: start.openDelayToken,
            after: retargetingVisiblePanel ? 0.12 : 0.35
        )
        loadWindows(
            for: start.session.id,
            target: target
        )
    }

    func hoverEnded(itemID: DockItem.ID) {
        guard !isExplicitPresentation,
              hoverState.session?.itemID == itemID
        else {
            return
        }
        guard let token = hoverState.endIconHover() else {
            close(resetNativeController: false)
            return
        }
        scheduleClose(token: token)
    }

    func showExplicit(
        item: DockItem,
        presentation: DockItemPresentation,
        sourceRect: CGRect,
        sourceDock: DockPanel
    ) {
        guard item.kind == .application,
              presentation.isAvailable,
              let bundleIdentifier = presentation.bundleID,
              !bundleIdentifier.isEmpty
        else {
            NSSound.beep()
            return
        }

        guard applicationWindows.isAccessibilityTrusted else {
            _ = applicationWindows.requestAccessibilityAccess()
            return
        }

        close(resetNativeController: false)
        isExplicitPresentation = true
        target = Target(
            itemID: item.id,
            bundleIdentifier: bundleIdentifier,
            applicationName: presentation.displayName,
            applicationIcon: presentation.icon,
            sourceRect: sourceRect
        )
        self.sourceDock = sourceDock

        let start = hoverState.beginIconHover(
            itemID: item.id,
            anchor: sourceRect
        )
        _ = hoverState.markDiscoveryStarted(
            sessionID: start.session.id
        )
        _ = hoverState.openDelayElapsed(
            token: start.openDelayToken
        )
        loadWindows(
            for: start.session.id,
            target: target
        )
    }

    func close(
        forDockID dockID: UUID? = nil,
        resetNativeController: Bool = false
    ) {
        if let dockID, sourceDock?.dockID != dockID {
            return
        }
        close(resetNativeController: resetNativeController)
    }

    private func close(resetNativeController: Bool) {
        openWorkItem?.cancel()
        openWorkItem = nil
        closeWorkItem?.cancel()
        closeWorkItem = nil
        refreshTask?.cancel()
        refreshTask = nil
        loadTask?.cancel()
        loadTask = nil
        thumbnailTask?.cancel()
        thumbnailTask = nil
        applicationWindows.clearThumbnailCache()
        removeEventMonitors()

        if let sourceDock {
            sourceDock.removeChildWindow(panel)
        }
        panel.orderOut(nil)
        panel.contentView = nil
        hostingView = nil
        panel.allowsKey = false

        if let autoHideToken {
            sourceDock?.endTransientInteraction(autoHideToken)
            self.autoHideToken = nil
        }

        hoverState.reset()
        target = nil
        sourceDock = nil
        windows = []
        thumbnails = [:]
        thumbnailLoadingIDs = []
        thumbnailUnavailableIDs = []
        isExplicitPresentation = false
        if resetNativeController {
            applicationWindows.reset()
        }
    }

    private func scheduleOpen(
        token: UUID,
        after delay: TimeInterval
    ) {
        openWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.openWorkItem = nil
                if self.hoverState.openDelayElapsed(
                    token: token
                ) {
                    self.presentPanel()
                } else if self.hoverState.session == nil {
                    self.close(resetNativeController: false)
                }
            }
        }
        openWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: work
        )
    }

    private func loadWindows(
        for sessionID: UUID,
        target: Target?,
        retryCount: Int = 0
    ) {
        guard let target else { return }
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let query = await self.applicationWindows.loadWindows(
                bundleIdentifier: target.bundleIdentifier,
                applicationName: target.applicationName
            )
            guard !Task.isCancelled,
                  self.hoverState.session?.id == sessionID,
                  self.target?.itemID == target.itemID
            else {
                return
            }

            switch WindowPreviewPanelQueryPolicy.decision(
                for: query.status,
                windowCount: query.windows.count,
                retryAttempt: retryCount
            ) {
            case .accept:
                self.windows = query.windows
                let shouldPresent =
                    self.hoverState.completeDiscovery(
                        sessionID: sessionID,
                        windowCount: query.windows.count
                    )
                if shouldPresent {
                    self.presentPanel()
                } else if self.hoverState.session == nil {
                    self.close(resetNativeController: false)
                }
            case let .retry(delay):
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled,
                      self.hoverState.session?.id == sessionID,
                      self.target?.itemID == target.itemID
                else {
                    return
                }
                self.loadWindows(
                    for: sessionID,
                    target: target,
                    retryCount: retryCount + 1
                )
            case .close:
                self.close(resetNativeController: false)
            }
        }
    }

    private func presentPanel() {
        guard hoverState.isPresented,
              let target,
              let sourceDock,
              !windows.isEmpty
        else {
            return
        }

        TooltipManager.shared.hide()
        if autoHideToken == nil {
            autoHideToken = sourceDock.beginTransientInteraction()
        }
        configurePanelContent(
            target: target,
            sessionID: hoverState.session?.id
        )
        positionPanel()
        if panel.parent !== sourceDock {
            sourceDock.addChildWindow(panel, ordered: .above)
        }
        installEventMonitors()

        panel.allowsKey = isExplicitPresentation
        panel.alphaValue = 0
        if isExplicitPresentation {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFront(nil)
        }

        if NSWorkspace.shared
            .accessibilityDisplayShouldReduceMotion
        {
            panel.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(
                    name: .easeOut
                )
                panel.animator().alphaValue = 1
            }
        }
        scheduleRefresh()
        if let sessionID = hoverState.session?.id {
            loadThumbnails(for: sessionID)
        }
    }

    private func configurePanelContent(
        target: Target,
        sessionID: UUID?
    ) {
        let view = WindowPreviewView(
            applicationName: target.applicationName,
            applicationIcon: target.applicationIcon,
            windows: windows,
            thumbnails: thumbnails,
            thumbnailLoadingIDs: thumbnailLoadingIDs,
            thumbnailUnavailableIDs:
                thumbnailUnavailableIDs,
            isThumbnailCaptureEnabled:
                applicationWindows.isScreenCaptureTrusted,
            onWindowSelected: { [weak self] windowID in
                self?.selectWindow(windowID)
            },
            onEnableWindowThumbnails: { [weak self] in
                self?.enableWindowThumbnails()
            },
            onHoverChanged: { [weak self] hovering in
                guard let self, let sessionID else { return }
                self.panelHoverChanged(
                    hovering,
                    sessionID: sessionID
                )
            },
            onClose: { [weak self] in
                self?.close(resetNativeController: false)
            }
        )
        if let hostingView {
            hostingView.rootView = view
            hostingView.frame = CGRect(
                origin: .zero,
                size: preferredPanelSize
            )
        } else {
            let hostingView = WindowPreviewHostingView(
                rootView: view
            )
            hostingView.frame = CGRect(
                origin: .zero,
                size: preferredPanelSize
            )
            self.hostingView = hostingView
            panel.contentView = hostingView
        }
    }

    private func loadThumbnails(for sessionID: UUID) {
        thumbnailTask?.cancel()
        guard let target else { return }
        guard applicationWindows.isScreenCaptureTrusted else {
            thumbnails = [:]
            thumbnailLoadingIDs = []
            thumbnailUnavailableIDs = []
            if panel.isVisible {
                configurePanelContent(
                    target: target,
                    sessionID: sessionID
                )
            }
            return
        }

        let requestedWindows = windows
        thumbnailLoadingIDs = Set(
            requestedWindows
                .filter {
                    $0.captureWindowID != nil
                        && thumbnails[$0.id] == nil
                }
                .map(\.id)
        )
        thumbnailUnavailableIDs.subtract(
            thumbnailLoadingIDs
        )
        thumbnailUnavailableIDs.formUnion(
            requestedWindows
                .filter { $0.captureWindowID == nil }
                .map(\.id)
        )
        if panel.isVisible {
            configurePanelContent(
                target: target,
                sessionID: sessionID
            )
        }
        thumbnailTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for window in requestedWindows {
                guard !Task.isCancelled,
                      self.hoverState.session?.id == sessionID,
                      self.target?.itemID == target.itemID
                else {
                    return
                }
                let thumbnail =
                    await self.applicationWindows.thumbnail(
                        for: window,
                        maximumPixelSize: CGSize(
                            width: 332,
                            height: 192
                        )
                    )
                guard !Task.isCancelled,
                      self.hoverState.session?.id == sessionID,
                      self.target?.itemID == target.itemID
                else {
                    return
                }
                self.thumbnailLoadingIDs.remove(window.id)
                if let thumbnail {
                    self.thumbnails[window.id] = thumbnail
                    self.thumbnailUnavailableIDs.remove(
                        window.id
                    )
                } else {
                    self.thumbnails.removeValue(
                        forKey: window.id
                    )
                    self.thumbnailUnavailableIDs.insert(
                        window.id
                    )
                }
                self.configurePanelContent(
                    target: target,
                    sessionID: sessionID
                )
            }
            self.thumbnailTask = nil
        }
    }

    private func panelHoverChanged(
        _ hovering: Bool,
        sessionID: UUID
    ) {
        guard !isExplicitPresentation else { return }
        if hovering {
            closeWorkItem?.cancel()
            closeWorkItem = nil
            _ = hoverState.panelEntered(
                sessionID: sessionID
            )
        } else if let token = hoverState.panelExited(
            sessionID: sessionID
        ) {
            scheduleClose(token: token)
        }
    }

    private func scheduleClose(token: UUID) {
        closeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.closeWorkItem = nil
                if self.hoverState.closeDelayElapsed(
                    token: token
                ) {
                    self.close(resetNativeController: false)
                }
            }
        }
        closeWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.32,
            execute: work
        )
    }

    private func positionPanel() {
        guard let target, let sourceDock else { return }
        let sourceRect = target.sourceRect.isEmpty
            ? CGRect(
                x: sourceDock.frame.midX - 24,
                y: sourceDock.frame.midY - 24,
                width: 48,
                height: 48
            )
            : target.sourceRect
        let screen = NSScreen.screens.first {
            $0.frame.contains(
                CGPoint(x: sourceRect.midX, y: sourceRect.midY)
            )
        } ?? sourceDock.screen ?? NSScreen.main
        guard let screen else { return }

        let placement = WindowPreviewPanelGeometry.placement(
            size: preferredPanelSize,
            sourceRect: sourceRect,
            dockFrame: sourceDock.frameForPersistence,
            visibleFrame: screen.visibleFrame,
            orientation: sourceDock.dockOrientation,
            dockedEdge: sourceDock.dockedEdgeForLayout
        )
        panel.setFrame(placement.frame, display: false)
    }

    private var preferredPanelSize: CGSize {
        WindowPreviewPanelSizing.preferredSize(
            windowCount: windows.count
        )
    }

    private func selectWindow(
        _ windowID: DockApplicationWindow.ID
    ) {
        let controller = applicationWindows
        close(resetNativeController: false)
        Task { @MainActor in
            let result = await controller.focusWindow(id: windowID)
            guard result == .accepted else {
                NSSound.beep()
                return
            }
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        guard panel.isVisible,
              let target,
              let sessionID = hoverState.session?.id
        else {
            return
        }

        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled,
                  let self,
                  self.panel.isVisible,
                  self.target?.itemID == target.itemID,
                  self.hoverState.session?.id == sessionID
            else {
                return
            }

            let query = await self.applicationWindows.loadWindows(
                bundleIdentifier: target.bundleIdentifier,
                applicationName: target.applicationName
            )
            guard !Task.isCancelled,
                  self.target?.itemID == target.itemID,
                  self.hoverState.session?.id == sessionID
            else {
                return
            }
            self.refreshTask = nil

            if query.status == .temporarilyUnavailable {
                self.scheduleRefresh()
                return
            }
            guard query.status == .ready else {
                self.close(resetNativeController: false)
                return
            }
            guard !query.windows.isEmpty else {
                self.close(resetNativeController: false)
                return
            }

            if self.windows != query.windows {
                let previousCaptureIDs = Dictionary(
                    uniqueKeysWithValues: self.windows.map {
                        ($0.id, $0.captureWindowID)
                    }
                )
                self.windows = query.windows
                let newCaptureIDs = Dictionary(
                    uniqueKeysWithValues: query.windows.map {
                        ($0.id, $0.captureWindowID)
                    }
                )
                let currentIDs = Set(query.windows.map(\.id))
                self.thumbnails = self.thumbnails.filter {
                    currentIDs.contains($0.key)
                        && previousCaptureIDs[$0.key]
                            == newCaptureIDs[$0.key]
                }
                self.thumbnailLoadingIDs.formIntersection(
                    currentIDs
                )
                self.thumbnailUnavailableIDs
                    .formIntersection(currentIDs)
                self.configurePanelContent(
                    target: target,
                    sessionID: sessionID
                )
                self.positionPanel()
                self.loadThumbnails(for: sessionID)
            } else if self.thumbnailTask == nil {
                self.loadThumbnails(for: sessionID)
            }
            self.scheduleRefresh()
        }
    }

    private func installEventMonitors() {
        guard localEventMonitor == nil,
              globalEventMonitor == nil
        else {
            return
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .keyDown,
                .leftMouseDown,
                .rightMouseDown,
            ]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.close(resetNativeController: false)
                return nil
            }
            guard event.type == .leftMouseDown
                    || event.type == .rightMouseDown,
                  event.window !== self.panel
            else {
                return event
            }
            let point = event.window.map {
                $0.convertPoint(toScreen: event.locationInWindow)
            } ?? NSEvent.mouseLocation
            if self.target?.sourceRect.contains(point) == true {
                return event
            }
            self.close(resetNativeController: false)
            return event
        }

        let monitoredSessionID = hoverState.session?.id
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      WindowPreviewPanelEventPolicy
                        .shouldCloseForGlobalClick(
                            monitoredSessionID:
                                monitoredSessionID,
                            currentSessionID:
                                self.hoverState.session?.id
                        )
                else {
                    return
                }
                self.close(resetNativeController: false)
            }
        }
    }

    private func removeEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }
}

private final class WindowPreviewHostingView<Content: View>:
    NSHostingView<Content>
{
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}

private final class WindowPreviewPanel: NSPanel {
    var allowsKey = false

    init() {
        super.init(
            contentRect: CGRect(
                x: 0,
                y: 0,
                width: 384,
                height: WindowPreviewPanelSizing.height
            ),
            styleMask: [
                .borderless,
                .nonactivatingPanel,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
        ]
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

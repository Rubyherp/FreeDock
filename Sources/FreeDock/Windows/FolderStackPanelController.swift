import Cocoa
import SwiftUI

@MainActor
final class FolderStackPanelController: NSObject, NSWindowDelegate {
    let dockID: UUID
    let itemID: UUID

    private let item: DockItem
    private let recentFiles: [RecentFileRecord]
    private var sourceRect: CGRect
    private weak var sourceDock: DockPanel?
    private let panel: FolderStackPanel
    private let onOpenURL: (URL) -> Void
    private let onClearRecentFiles: () -> Void
    private let onOptionsChanged: (FolderStackOptions) -> Void
    private let onDidClose: () -> Void
    private var autoHideToken: UUID?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var isClosed = false

    init(
        dockID: UUID,
        item: DockItem,
        sourceRect: CGRect,
        sourceDock: DockPanel,
        recentFiles: [RecentFileRecord],
        onOpenURL: @escaping (URL) -> Void,
        onClearRecentFiles: @escaping () -> Void,
        onOptionsChanged: @escaping (FolderStackOptions) -> Void,
        onDidClose: @escaping () -> Void
    ) {
        self.dockID = dockID
        itemID = item.id
        self.item = item
        self.recentFiles = recentFiles
        self.sourceRect = sourceRect
        self.sourceDock = sourceDock
        self.onOpenURL = onOpenURL
        self.onClearRecentFiles = onClearRecentFiles
        self.onOptionsChanged = onOptionsChanged
        self.onDidClose = onDidClose
        panel = FolderStackPanel(
            contentRect: CGRect(x: 0, y: 0, width: 492, height: 424)
        )
        super.init()
        panel.delegate = self
    }

    func show() {
        guard !isClosed, let sourceDock else { return }

        TooltipManager.shared.hide()
        autoHideToken = sourceDock.beginTransientInteraction()

        let anchorRect = sourceRect.isEmpty
            ? CGRect(
                x: sourceDock.frame.midX - 24,
                y: sourceDock.frame.midY - 24,
                width: 48,
                height: 48
            )
            : sourceRect
        sourceRect = anchorRect
        let screen = NSScreen.screens.first {
            $0.frame.contains(CGPoint(x: anchorRect.midX, y: anchorRect.midY))
        } ?? sourceDock.screen ?? NSScreen.main
        guard let screen else {
            close()
            return
        }

        let placement = FolderStackPanelGeometry.placement(
            size: panel.frame.size,
            sourceRect: anchorRect,
            dockFrame: sourceDock.frameForPersistence,
            visibleFrame: screen.visibleFrame,
            orientation: sourceDock.dockOrientation
        )
        panel.setFrame(placement.frame, display: false)

        // The placement geometry can make the panel smaller on compact displays.
        // Pin the hosting view to an AppKit container instead of relying on its
        // 492×424 ideal size so SwiftUI always receives the actual panel size.
        let contentContainer = NSView(
            frame: CGRect(origin: .zero, size: placement.frame.size)
        )
        let hostingView = NSHostingView(rootView: stackView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(
                equalTo: contentContainer.leadingAnchor
            ),
            hostingView.trailingAnchor.constraint(
                equalTo: contentContainer.trailingAnchor
            ),
            hostingView.topAnchor.constraint(
                equalTo: contentContainer.topAnchor
            ),
            hostingView.bottomAnchor.constraint(
                equalTo: contentContainer.bottomAnchor
            ),
        ])
        panel.contentView = contentContainer
        sourceDock.addChildWindow(panel, ordered: .above)
        installEventMonitors()

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true

        removeEventMonitors()
        if let sourceDock {
            sourceDock.removeChildWindow(panel)
        }
        panel.delegate = nil
        panel.orderOut(nil)
        panel.contentView = nil

        if let autoHideToken {
            sourceDock?.endTransientInteraction(autoHideToken)
            self.autoHideToken = nil
        }
        onDidClose()
    }

    func windowWillClose(_: Notification) {
        close()
    }

    private var stackView: some View {
        FolderStackView(
            item: item,
            presentation: DockItemPresentation.resolve(item),
            recentFiles: recentFiles,
            onOpenURL: { [weak self] url in
                self?.requestOpen(url)
            },
            onOpenContainer: openContainerAction,
            onClearRecentFiles: clearRecentFilesAction,
            onOptionsChanged: { [weak self] options in
                self?.onOptionsChanged(options)
            },
            onClose: { [weak self] in
                self?.close()
            }
        )
    }

    private var openContainerAction: (() -> Void)? {
        guard containerURL != nil else { return nil }
        return { [weak self] in
            self?.requestOpenContainer()
        }
    }

    private var clearRecentFilesAction: (() -> Void)? {
        guard item.smartStackSource == .recentFiles else { return nil }
        return { [weak self] in
            self?.requestClearRecentFiles()
        }
    }

    private var containerURL: URL? {
        let candidate: URL?
        switch item.smartStackSource {
        case .recentFiles:
            candidate = nil
        case .downloads:
            candidate = FileManager.default.urls(
                for: .downloadsDirectory,
                in: .userDomainMask
            ).first?.standardizedFileURL
        case nil:
            candidate = item.fileURL
        }

        guard let candidate,
              FileManager.default.fileExists(atPath: candidate.path)
        else {
            return nil
        }
        return candidate
    }

    private func requestOpenContainer() {
        guard let containerURL else { return }
        requestOpen(containerURL)
    }

    private func requestOpen(_ url: URL) {
        let action = onOpenURL
        close()
        action(url)
    }

    private func requestClearRecentFiles() {
        let action = onClearRecentFiles
        close()
        action()
    }

    private func installEventMonitors() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }

            if event.type == .keyDown, event.keyCode == 53 {
                self.close()
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
            if self.sourceRect.contains(point) {
                return event
            }
            self.close()
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.close()
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

final class FolderStackPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

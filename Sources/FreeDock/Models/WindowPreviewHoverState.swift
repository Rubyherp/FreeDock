import Foundation

struct WindowPreviewHoverSession: Equatable, Sendable {
    let id: UUID
    let itemID: DockItem.ID
    var anchor: CGRect
}

struct WindowPreviewHoverStart: Equatable, Sendable {
    let session: WindowPreviewHoverSession
    let openDelayToken: UUID
    let shouldDiscover: Bool
}

/// Pure hover coordination for an asynchronously loaded window-preview panel.
///
/// Discovery starts immediately, but presentation waits for both a successful
/// result and the open delay. Session and timer tokens keep late callbacks from
/// reopening or closing a preview after the pointer has moved to another item.
struct WindowPreviewHoverState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case pending
        case loading
        case presented
    }

    private(set) var phase: Phase = .idle
    private(set) var session: WindowPreviewHoverSession?
    private(set) var openDelayToken: UUID?
    private(set) var closeDelayToken: UUID?
    private(set) var isPointerOverIcon = false
    private(set) var isPointerOverPanel = false
    private(set) var discoveredWindowCount: Int?
    private var didOpenDelayElapse = false

    var isPresented: Bool {
        phase == .presented
    }

    mutating func beginIconHover(
        itemID: DockItem.ID,
        anchor: CGRect,
        sessionID: UUID = UUID(),
        openToken: UUID = UUID()
    ) -> WindowPreviewHoverStart {
        if var current = session, current.itemID == itemID {
            current.anchor = anchor
            session = current
            isPointerOverIcon = true
            closeDelayToken = nil
            return WindowPreviewHoverStart(
                session: current,
                openDelayToken: openDelayToken ?? openToken,
                shouldDiscover: false
            )
        }

        let next = WindowPreviewHoverSession(
            id: sessionID,
            itemID: itemID,
            anchor: anchor
        )
        phase = .pending
        session = next
        openDelayToken = openToken
        closeDelayToken = nil
        isPointerOverIcon = true
        isPointerOverPanel = false
        discoveredWindowCount = nil
        didOpenDelayElapse = false
        return WindowPreviewHoverStart(
            session: next,
            openDelayToken: openToken,
            shouldDiscover: true
        )
    }

    @discardableResult
    mutating func markDiscoveryStarted(
        sessionID: UUID
    ) -> Bool {
        guard session?.id == sessionID,
              phase == .pending
        else {
            return false
        }
        phase = .loading
        return true
    }

    /// Returns true exactly when this result makes the preview presentable.
    @discardableResult
    mutating func completeDiscovery(
        sessionID: UUID,
        windowCount: Int
    ) -> Bool {
        guard session?.id == sessionID,
              phase == .pending || phase == .loading
        else {
            return false
        }
        discoveredWindowCount = max(0, windowCount)
        return reconcilePresentation()
    }

    /// Returns true exactly when this timer makes the preview presentable.
    @discardableResult
    mutating func openDelayElapsed(
        token: UUID
    ) -> Bool {
        guard token == openDelayToken,
              phase == .pending || phase == .loading
        else {
            return false
        }
        didOpenDelayElapse = true
        openDelayToken = nil
        return reconcilePresentation()
    }

    /// Leaving before presentation cancels immediately. A presented preview
    /// gets a close token so the pointer can cross the icon-to-panel gap.
    mutating func endIconHover(
        closeToken: UUID = UUID()
    ) -> UUID? {
        isPointerOverIcon = false
        guard phase == .presented else {
            reset()
            return nil
        }
        guard !isPointerOverPanel else { return nil }
        closeDelayToken = closeToken
        return closeToken
    }

    @discardableResult
    mutating func panelEntered(
        sessionID: UUID
    ) -> Bool {
        guard session?.id == sessionID,
              phase == .presented
        else {
            return false
        }
        isPointerOverPanel = true
        closeDelayToken = nil
        return true
    }

    mutating func panelExited(
        sessionID: UUID,
        closeToken: UUID = UUID()
    ) -> UUID? {
        guard session?.id == sessionID,
              phase == .presented
        else {
            return nil
        }
        isPointerOverPanel = false
        guard !isPointerOverIcon else { return nil }
        closeDelayToken = closeToken
        return closeToken
    }

    /// Returns true only when the current preview should actually close.
    @discardableResult
    mutating func closeDelayElapsed(
        token: UUID
    ) -> Bool {
        guard token == closeDelayToken,
              phase == .presented,
              !isPointerOverIcon,
              !isPointerOverPanel
        else {
            return false
        }
        reset()
        return true
    }

    @discardableResult
    mutating func updateAnchor(
        itemID: DockItem.ID,
        anchor: CGRect
    ) -> Bool {
        guard var current = session,
              current.itemID == itemID
        else {
            return false
        }
        current.anchor = anchor
        session = current
        return true
    }

    mutating func reset() {
        phase = .idle
        session = nil
        openDelayToken = nil
        closeDelayToken = nil
        isPointerOverIcon = false
        isPointerOverPanel = false
        discoveredWindowCount = nil
        didOpenDelayElapse = false
    }

    private mutating func reconcilePresentation() -> Bool {
        guard didOpenDelayElapse,
              let discoveredWindowCount
        else {
            return false
        }
        guard discoveredWindowCount > 0 else {
            reset()
            return false
        }
        phase = .presented
        return true
    }
}

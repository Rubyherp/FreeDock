import Foundation
import Testing
@testable import FreeDock

@Suite("Window preview hover state")
struct WindowPreviewHoverStateTests {
    @Test("Discovery and delay converge in either order")
    func discoveryAndDelayConverge() {
        let itemID = UUID()
        let sessionID = UUID()
        let openToken = UUID()
        var resultFirst = WindowPreviewHoverState()
        let start = resultFirst.beginIconHover(
            itemID: itemID,
            anchor: anchor,
            sessionID: sessionID,
            openToken: openToken
        )
        #expect(start.shouldDiscover)
        let didStartDiscovery = resultFirst.markDiscoveryStarted(
            sessionID: sessionID
        )
        #expect(didStartDiscovery)
        let didPresentFromResult = resultFirst.completeDiscovery(
            sessionID: sessionID,
            windowCount: 2
        )
        #expect(!didPresentFromResult)
        let didPresentFromDelay = resultFirst.openDelayElapsed(
            token: openToken
        )
        #expect(didPresentFromDelay)
        #expect(resultFirst.isPresented)

        var delayFirst = WindowPreviewHoverState()
        _ = delayFirst.beginIconHover(
            itemID: itemID,
            anchor: anchor,
            sessionID: sessionID,
            openToken: openToken
        )
        let didPresentBeforeResult = delayFirst.openDelayElapsed(
            token: openToken
        )
        #expect(!didPresentBeforeResult)
        let didPresentAfterResult = delayFirst.completeDiscovery(
            sessionID: sessionID,
            windowCount: 2
        )
        #expect(didPresentAfterResult)
        #expect(delayFirst.isPresented)
    }

    @Test("Leaving before the open delay prevents presentation")
    func earlyExitCancels() {
        let sessionID = UUID()
        let openToken = UUID()
        var state = WindowPreviewHoverState()
        _ = state.beginIconHover(
            itemID: UUID(),
            anchor: anchor,
            sessionID: sessionID,
            openToken: openToken
        )
        _ = state.completeDiscovery(
            sessionID: sessionID,
            windowCount: 1
        )

        let closeToken = state.endIconHover()
        #expect(closeToken == nil)
        #expect(state.phase == .idle)
        let didPresent = state.openDelayElapsed(token: openToken)
        #expect(!didPresent)
    }

    @Test("Rapid retarget rejects the previous discovery and timer")
    func rapidRetarget() {
        let firstSessionID = UUID()
        let firstToken = UUID()
        let secondSessionID = UUID()
        let secondToken = UUID()
        let secondItemID = UUID()
        var state = WindowPreviewHoverState()
        _ = state.beginIconHover(
            itemID: UUID(),
            anchor: anchor,
            sessionID: firstSessionID,
            openToken: firstToken
        )
        _ = state.beginIconHover(
            itemID: secondItemID,
            anchor: anchor.offsetBy(dx: 40, dy: 0),
            sessionID: secondSessionID,
            openToken: secondToken
        )

        let acceptedOldDiscovery = state.completeDiscovery(
            sessionID: firstSessionID,
            windowCount: 3
        )
        #expect(!acceptedOldDiscovery)
        let acceptedOldTimer = state.openDelayElapsed(
            token: firstToken
        )
        #expect(!acceptedOldTimer)
        #expect(state.session?.itemID == secondItemID)
        #expect(state.session?.id == secondSessionID)
    }

    @Test("Panel entry bridges the close grace period")
    func panelEntryBridgesGap() throws {
        let sessionID = UUID()
        var state = presentedState(sessionID: sessionID)
        let proposedCloseToken = state.endIconHover()
        let closeToken = try #require(proposedCloseToken)

        let didEnterPanel = state.panelEntered(
            sessionID: sessionID
        )
        #expect(didEnterPanel)
        let didClose = state.closeDelayElapsed(token: closeToken)
        #expect(!didClose)
        #expect(state.isPresented)
    }

    @Test("A stale close cannot dismiss a re-entered session")
    func staleCloseAfterReentry() throws {
        let sessionID = UUID()
        let itemID = UUID()
        var state = presentedState(
            sessionID: sessionID,
            itemID: itemID
        )
        let proposedCloseToken = state.endIconHover()
        let closeToken = try #require(proposedCloseToken)
        let restart = state.beginIconHover(
            itemID: itemID,
            anchor: anchor.offsetBy(dx: 2, dy: 3)
        )

        #expect(!restart.shouldDiscover)
        let didClose = state.closeDelayElapsed(token: closeToken)
        #expect(!didClose)
        #expect(state.isPresented)
        #expect(
            state.session?.anchor
                == anchor.offsetBy(dx: 2, dy: 3)
        )
    }

    @Test("Panel exit closes only after its current grace token")
    func panelExitClose() throws {
        let sessionID = UUID()
        var state = presentedState(sessionID: sessionID)
        _ = state.endIconHover()
        let didEnterPanel = state.panelEntered(
            sessionID: sessionID
        )
        #expect(didEnterPanel)
        let proposedCloseToken = state.panelExited(
            sessionID: sessionID
        )
        let closeToken = try #require(proposedCloseToken)

        let acceptedStaleClose = state.closeDelayElapsed(
            token: UUID()
        )
        #expect(!acceptedStaleClose)
        let didClose = state.closeDelayElapsed(token: closeToken)
        #expect(didClose)
        #expect(state.phase == .idle)
    }

    @Test("Empty discovery never presents")
    func emptyDiscovery() {
        let sessionID = UUID()
        let openToken = UUID()
        var state = WindowPreviewHoverState()
        _ = state.beginIconHover(
            itemID: UUID(),
            anchor: anchor,
            sessionID: sessionID,
            openToken: openToken
        )
        _ = state.openDelayElapsed(token: openToken)

        let didPresent = state.completeDiscovery(
            sessionID: sessionID,
            windowCount: 0
        )
        #expect(!didPresent)
        #expect(state.phase == .idle)
    }

    @Test("External reset invalidates every callback")
    func externalReset() {
        let sessionID = UUID()
        let openToken = UUID()
        var state = WindowPreviewHoverState()
        _ = state.beginIconHover(
            itemID: UUID(),
            anchor: anchor,
            sessionID: sessionID,
            openToken: openToken
        )
        state.reset()

        let acceptedDiscovery = state.completeDiscovery(
            sessionID: sessionID,
            windowCount: 1
        )
        #expect(!acceptedDiscovery)
        let acceptedTimer = state.openDelayElapsed(token: openToken)
        #expect(!acceptedTimer)
        #expect(state == WindowPreviewHoverState())
    }

    private var anchor: CGRect {
        CGRect(x: 100, y: 20, width: 48, height: 48)
    }

    private func presentedState(
        sessionID: UUID,
        itemID: UUID = UUID()
    ) -> WindowPreviewHoverState {
        let openToken = UUID()
        var state = WindowPreviewHoverState()
        _ = state.beginIconHover(
            itemID: itemID,
            anchor: anchor,
            sessionID: sessionID,
            openToken: openToken
        )
        _ = state.completeDiscovery(
            sessionID: sessionID,
            windowCount: 1
        )
        _ = state.openDelayElapsed(token: openToken)
        return state
    }
}

import Foundation
import Testing
@testable import FreeDock

@Suite("Dock external file drop claim state")
struct DockExternalFileDropClaimStateTests {
    @Test("Application targeting suppresses the parent pin target")
    func applicationTargeting() {
        let firstItemID = UUID()
        let secondItemID = UUID()
        var state = DockExternalFileDropClaimState()

        #expect(!state.shouldSuppressParentPinDrop)

        state.applicationTargetEntered(itemID: firstItemID)
        #expect(state.applicationTargetItemID == firstItemID)
        #expect(state.shouldSuppressParentPinDrop)

        state.applicationTargetEntered(itemID: secondItemID)
        state.applicationTargetExited(itemID: firstItemID)
        #expect(state.applicationTargetItemID == secondItemID)
        #expect(state.shouldSuppressParentPinDrop)

        state.applicationTargetExited(itemID: secondItemID)
        #expect(state.applicationTargetItemID == nil)
        #expect(!state.shouldSuppressParentPinDrop)
    }

    @Test("Ordinary parent operations do not claim the parent target")
    func ordinaryOperation() {
        let operationID = UUID()
        var state = DockExternalFileDropClaimState()

        let returnedID = state.beginOperation(
            operationID: operationID
        )

        #expect(returnedID == operationID)
        #expect(state.activeOperationID == operationID)
        #expect(state.isOperationInProgress)
        #expect(!state.shouldSuppressParentPinDrop)

        let didFinish = state.finishOperation(operationID)
        #expect(didFinish)
        #expect(state.activeOperationID == nil)
        #expect(!state.isOperationInProgress)
        #expect(!state.isAwaitingDispatchRelease)
    }

    @Test("Dispatch suppression clears while async loading stays active")
    func dispatchSuppressionRelease() {
        let itemID = UUID()
        let operationID = UUID()
        var state = DockExternalFileDropClaimState()

        let returnedID = state.claimApplicationDrop(
            itemID: itemID,
            operationID: operationID
        )
        state.applicationTargetExited(itemID: itemID)

        #expect(returnedID == operationID)
        #expect(state.applicationTargetItemID == nil)
        #expect(state.activeOperationID == operationID)
        #expect(state.isOperationInProgress)
        #expect(
            state.dispatchSuppressionOperationID == operationID
        )
        #expect(state.shouldSuppressParentPinDrop)

        let didRelease = state.releaseDispatchSuppression(
            for: operationID
        )
        #expect(didRelease)
        #expect(state.activeOperationID == operationID)
        #expect(state.isOperationInProgress)
        #expect(!state.isAwaitingDispatchRelease)
        #expect(!state.shouldSuppressParentPinDrop)

        let didFinish = state.finishOperation(operationID)
        #expect(didFinish)
        #expect(!state.isOperationInProgress)
        #expect(!state.shouldSuppressParentPinDrop)
    }

    @Test("A stale finish cannot clear a newer operation")
    func staleFinish() {
        let firstOperationID = UUID()
        let secondOperationID = UUID()
        let secondItemID = UUID()
        var state = DockExternalFileDropClaimState()

        state.beginOperation(operationID: firstOperationID)
        state.claimApplicationDrop(
            itemID: secondItemID,
            operationID: secondOperationID
        )

        let didFinishFirst = state.finishOperation(
            firstOperationID
        )
        #expect(!didFinishFirst)
        #expect(state.activeOperationID == secondOperationID)
        #expect(state.applicationTargetItemID == secondItemID)
        #expect(state.shouldSuppressParentPinDrop)
    }

    @Test("Finishing does not create or extend suppression")
    func finishDoesNotCreateSuppression() {
        let itemID = UUID()
        let operationID = UUID()
        var state = DockExternalFileDropClaimState()
        state.claimApplicationDrop(
            itemID: itemID,
            operationID: operationID
        )
        state.applicationTargetExited(itemID: itemID)
        let didRelease = state.releaseDispatchSuppression(
            for: operationID
        )
        #expect(didRelease)
        #expect(!state.shouldSuppressParentPinDrop)

        let didFinish = state.finishOperation(operationID)
        #expect(didFinish)
        #expect(state.activeOperationID == nil)
        #expect(state.applicationTargetItemID == nil)
        #expect(state.dispatchSuppressionOperationID == nil)
        #expect(!state.isAwaitingDispatchRelease)
        #expect(!state.shouldSuppressParentPinDrop)
    }

    @Test("A stale dispatch release cannot release a newer claim")
    func staleDispatchRelease() {
        let firstOperationID = UUID()
        let secondOperationID = UUID()
        let firstItemID = UUID()
        let secondItemID = UUID()
        var state = DockExternalFileDropClaimState()

        state.claimApplicationDrop(
            itemID: firstItemID,
            operationID: firstOperationID
        )
        state.applicationTargetExited(itemID: firstItemID)

        state.claimApplicationDrop(
            itemID: secondItemID,
            operationID: secondOperationID
        )
        state.applicationTargetExited(itemID: secondItemID)
        let didReleaseFirst = state.releaseDispatchSuppression(
            for: firstOperationID
        )
        #expect(!didReleaseFirst)
        #expect(state.activeOperationID == secondOperationID)
        #expect(
            state.dispatchSuppressionOperationID
                == secondOperationID
        )
        #expect(state.shouldSuppressParentPinDrop)

        let didReleaseSecond = state.releaseDispatchSuppression(
            for: secondOperationID
        )
        #expect(didReleaseSecond)
        #expect(state.activeOperationID == secondOperationID)
        #expect(!state.shouldSuppressParentPinDrop)
    }

    @Test("Reset clears targeting, loading, and dispatch suppression")
    func reset() {
        let operationID = UUID()
        var state = DockExternalFileDropClaimState()
        state.claimApplicationDrop(
            itemID: UUID(),
            operationID: operationID
        )

        state.reset()

        #expect(state == DockExternalFileDropClaimState())
        #expect(state.applicationTargetItemID == nil)
        #expect(state.activeOperationID == nil)
        #expect(state.dispatchSuppressionOperationID == nil)
        #expect(!state.shouldSuppressParentPinDrop)
    }
}

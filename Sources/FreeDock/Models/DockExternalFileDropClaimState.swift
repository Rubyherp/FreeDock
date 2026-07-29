import Foundation

/// Pure state for coordinating nested Finder drop targets in a dock.
///
/// An application cell sits inside the dock's parent pin target. App targeting
/// and claimed app drops suppress that parent so one Finder payload cannot be
/// handled twice. A claim's suppression lasts only through the current nested
/// drop-dispatch turn and is independent of asynchronous provider loading.
struct DockExternalFileDropClaimState: Equatable, Sendable {
    private struct ActiveOperation: Equatable, Sendable {
        let id: UUID
    }

    private(set) var applicationTargetItemID: UUID?
    private var activeOperation: ActiveOperation?
    private(set) var dispatchSuppressionOperationID: UUID?

    init() {}

    var activeOperationID: UUID? {
        activeOperation?.id
    }

    var isOperationInProgress: Bool {
        activeOperation != nil
    }

    var isAwaitingDispatchRelease: Bool {
        dispatchSuppressionOperationID != nil
    }

    var shouldSuppressParentPinDrop: Bool {
        applicationTargetItemID != nil
            || dispatchSuppressionOperationID != nil
    }

    mutating func applicationTargetEntered(itemID: UUID) {
        applicationTargetItemID = itemID
    }

    mutating func applicationTargetExited(itemID: UUID) {
        guard applicationTargetItemID == itemID else { return }
        applicationTargetItemID = nil
    }

    /// Starts an ordinary parent-target load without claiming it for an app.
    @discardableResult
    mutating func beginOperation(
        operationID: UUID = UUID()
    ) -> UUID {
        activeOperation = ActiveOperation(id: operationID)
        return operationID
    }

    /// Claims a Finder payload for one app and starts its asynchronous load.
    @discardableResult
    mutating func claimApplicationDrop(
        itemID: UUID,
        operationID: UUID = UUID()
    ) -> UUID {
        applicationTargetItemID = itemID
        activeOperation = ActiveOperation(id: operationID)
        dispatchSuppressionOperationID = operationID
        return operationID
    }

    /// Finishes only the current operation.
    @discardableResult
    mutating func finishOperation(_ operationID: UUID) -> Bool {
        guard let operation = activeOperation,
              operation.id == operationID
        else {
            return false
        }

        activeOperation = nil
        return true
    }

    /// Releases a claim on the next dispatch turn, without ending its load.
    @discardableResult
    mutating func releaseDispatchSuppression(
        for operationID: UUID
    ) -> Bool {
        guard dispatchSuppressionOperationID == operationID else {
            return false
        }
        dispatchSuppressionOperationID = nil
        return true
    }

    mutating func reset() {
        applicationTargetItemID = nil
        activeOperation = nil
        dispatchSuppressionOperationID = nil
    }
}

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FreeDock

@Suite("Dock item drag coordinator")
@MainActor
struct DockItemDragCoordinatorTests {
    @Test("Private drag providers round-trip the complete session")
    func providerRoundTrip() async {
        let profileID = UUID()
        let sourceDockID = UUID()
        let itemID = UUID()
        let coordinator = DockItemDragCoordinator()
        let provider = coordinator.beginDrag(
            profileID: profileID,
            sourceDockID: sourceDockID,
            itemID: itemID
        )

        #expect(
            provider.hasItemConformingToTypeIdentifier(
                UTType.freeDockItem.identifier
            )
        )
        let decoded = await withCheckedContinuation { continuation in
            coordinator.loadSession(from: provider) {
                continuation.resume(returning: $0)
            }
        }

        #expect(decoded == coordinator.activeSession)
        #expect(decoded?.profileID == profileID)
        #expect(decoded?.sourceDockID == sourceDockID)
        #expect(decoded?.itemID == itemID)
        coordinator.cancel()
        #expect(coordinator.activeSession == nil)
    }

    @Test("Stale completion cannot end a newer drag")
    func staleFinishIgnored() {
        let coordinator = DockItemDragCoordinator()
        _ = coordinator.beginDrag(
            profileID: UUID(),
            sourceDockID: UUID(),
            itemID: UUID()
        )
        let firstSessionID = coordinator.activeSession?.id

        _ = coordinator.beginDrag(
            profileID: UUID(),
            sourceDockID: UUID(),
            itemID: UUID()
        )
        let secondSessionID = coordinator.activeSession?.id
        if let firstSessionID {
            coordinator.finish(sessionID: firstSessionID)
        }

        #expect(coordinator.activeSession?.id == secondSessionID)
        if let secondSessionID {
            coordinator.finish(sessionID: secondSessionID)
        }
        #expect(coordinator.activeSession == nil)
    }

    @Test("Content revisions are monotonic")
    func contentRevision() {
        let coordinator = DockItemDragCoordinator()
        let initial = coordinator.contentRevision
        coordinator.publishContentChange()
        coordinator.publishContentChange()
        #expect(coordinator.contentRevision == initial + 2)
    }
}

import Cocoa
import Combine
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let freeDockItem = UTType(
        exportedAs: "com.freedock.dock-item",
        conformingTo: .data
    )
}

struct DockItemDragSession: Codable, Equatable, Sendable {
    let id: UUID
    let profileID: UUID
    let sourceDockID: UUID
    let itemID: UUID

    init(
        id: UUID = UUID(),
        profileID: UUID,
        sourceDockID: UUID,
        itemID: UUID
    ) {
        self.id = id
        self.profileID = profileID
        self.sourceDockID = sourceDockID
        self.itemID = itemID
    }
}

@MainActor
final class DockItemDragCoordinator: ObservableObject {
    @Published private(set) var activeSession: DockItemDragSession?
    @Published private(set) var contentRevision: UInt = 0

    var onSessionBegan: (@MainActor (DockItemDragSession) -> Void)?
    var onSessionEnded: (@MainActor (DockItemDragSession) -> Void)?

    private var localMouseUpMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var deferredFinishWorkItem: DispatchWorkItem?
    private var expiryWorkItem: DispatchWorkItem?

    func beginDrag(
        profileID: UUID,
        sourceDockID: UUID,
        itemID: UUID
    ) -> NSItemProvider {
        cancel()

        let session = DockItemDragSession(
            profileID: profileID,
            sourceDockID: sourceDockID,
            itemID: itemID
        )
        activeSession = session
        installEndMonitors(for: session.id)
        onSessionBegan?(session)

        let provider = NSItemProvider()
        let data = try? JSONEncoder().encode(session)
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.freeDockItem.identifier,
            visibility: .ownProcess
        ) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    func loadSession(
        from provider: NSItemProvider,
        completion: @escaping @MainActor (DockItemDragSession?) -> Void
    ) {
        provider.loadDataRepresentation(
            forTypeIdentifier: UTType.freeDockItem.identifier
        ) { data, _ in
            let session = data.flatMap {
                try? JSONDecoder().decode(
                    DockItemDragSession.self,
                    from: $0
                )
            }
            DispatchQueue.main.async {
                completion(session)
            }
        }
    }

    func finish(sessionID: UUID) {
        guard activeSession?.id == sessionID else { return }
        endSession()
    }

    func cancel() {
        endSession()
    }

    func publishContentChange() {
        contentRevision &+= 1
    }

    func isDragging(itemID: UUID, from dockID: UUID) -> Bool {
        activeSession?.itemID == itemID
            && activeSession?.sourceDockID == dockID
    }

    private func installEndMonitors(for sessionID: UUID) {
        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp]
        ) { [weak self] event in
            self?.scheduleDeferredFinish(for: sessionID)
            return event
        }

        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.scheduleDeferredFinish(for: sessionID)
            }
        }

        let expiry = DispatchWorkItem { [weak self] in
            self?.finish(sessionID: sessionID)
        }
        expiryWorkItem = expiry
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 120,
            execute: expiry
        )
    }

    private func scheduleDeferredFinish(for sessionID: UUID) {
        guard activeSession?.id == sessionID else { return }
        deferredFinishWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.finish(sessionID: sessionID)
        }
        deferredFinishWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.6,
            execute: work
        )
    }

    private func endSession() {
        let endingSession = activeSession
        deferredFinishWorkItem?.cancel()
        deferredFinishWorkItem = nil
        expiryWorkItem?.cancel()
        expiryWorkItem = nil

        if let localMouseUpMonitor {
            NSEvent.removeMonitor(localMouseUpMonitor)
            self.localMouseUpMonitor = nil
        }
        if let globalMouseUpMonitor {
            NSEvent.removeMonitor(globalMouseUpMonitor)
            self.globalMouseUpMonitor = nil
        }

        activeSession = nil
        if let endingSession {
            onSessionEnded?(endingSession)
        }
    }
}

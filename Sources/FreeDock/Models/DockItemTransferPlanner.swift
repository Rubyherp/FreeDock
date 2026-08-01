import Foundation

enum DockItemTransferOperation: Equatable, Sendable {
    case move
    case copy
}

enum DockItemTransferDestination: Equatable, Sendable {
    /// Places the transferred item in the target item's current slot.
    ///
    /// For a cross-dock transfer this inserts immediately before the target.
    /// For a same-dock move this matches the existing reorder behavior: the
    /// moved item finishes at the target item's pre-move index.
    case item(UUID)
    /// Removes the source item from its dock while retaining the target Trash.
    case trash(UUID)
    case trailing
}

enum DockItemTransferRejection: Equatable, Sendable {
    case sourceItemNotFound
    case targetItemNotFound(UUID)
    case duplicateItem(existingItemID: UUID)
    case invalidTrashTarget(UUID)
    case cannotRemoveTrash
    case inconsistentSameDockItems
}

enum DockItemTransferOutcome: Equatable, Sendable {
    case moved(itemID: UUID)
    case copied(itemID: UUID)
    case removed(itemID: UUID)
    case unchanged
    case rejected(DockItemTransferRejection)
}

struct DockItemTransferPlan: Equatable, Sendable {
    let sourceItems: [DockItem]
    let targetItems: [DockItem]
    let outcome: DockItemTransferOutcome

    var didTransfer: Bool {
        switch outcome {
        case .moved, .copied, .removed:
            return true
        case .unchanged, .rejected:
            return false
        }
    }
}

enum DockItemTransferPlanner {
    /// Plans an atomic item transfer without mutating either dock.
    ///
    /// Moves retain the item's identity. Copies receive a fresh identity while
    /// retaining every other stored value. A cross-dock transfer is rejected
    /// without changing either dock when the destination already contains the
    /// same file-system item or smart stack. Separators intentionally remain
    /// repeatable.
    static func planTransfer(
        itemID: UUID,
        from sourceDock: DockConfig,
        to targetDock: DockConfig,
        operation: DockItemTransferOperation = .move,
        destination: DockItemTransferDestination = .trailing,
        downloadsURL: URL? = nil
    ) -> DockItemTransferPlan {
        guard let sourceIndex = sourceDock.items.firstIndex(where: {
            $0.id == itemID
        }) else {
            return rejectedPlan(
                sourceItems: sourceDock.items,
                targetItems: targetDock.items,
                reason: .sourceItemNotFound
            )
        }
        let sourceItem = sourceDock.items[sourceIndex]

        if case let .trash(targetTrashID) = destination {
            guard targetDock.items.contains(where: {
                $0.id == targetTrashID && $0.kind == .trash
            }) else {
                return rejectedPlan(
                    sourceItems: sourceDock.items,
                    targetItems: targetDock.items,
                    reason: .invalidTrashTarget(targetTrashID)
                )
            }
            guard sourceItem.kind != .trash else {
                return rejectedPlan(
                    sourceItems: sourceDock.items,
                    targetItems: targetDock.items,
                    reason: .cannotRemoveTrash
                )
            }

            var sourceItems = sourceDock.items
            sourceItems.remove(at: sourceIndex)
            let targetItems = sourceDock.id == targetDock.id
                ? sourceItems
                : targetDock.items
            return DockItemTransferPlan(
                sourceItems: sourceItems,
                targetItems: targetItems,
                outcome: .removed(itemID: sourceItem.id)
            )
        }

        if sourceDock.id == targetDock.id {
            guard sourceDock.items == targetDock.items else {
                return rejectedPlan(
                    sourceItems: sourceDock.items,
                    targetItems: targetDock.items,
                    reason: .inconsistentSameDockItems
                )
            }
            return planWithinDock(
                sourceIndex: sourceIndex,
                items: sourceDock.items,
                destination: destination
            )
        }

        guard let insertionIndex = insertionIndex(
            for: destination,
            in: targetDock.items
        ) else {
            return rejectedPlan(
                sourceItems: sourceDock.items,
                targetItems: targetDock.items,
                reason: missingTargetReason(for: destination)
            )
        }

        if let duplicate = duplicate(
            of: sourceItem,
            in: targetDock.items,
            operation: operation,
            downloadsURL: resolvedDownloadsURL(downloadsURL)
        ) {
            return rejectedPlan(
                sourceItems: sourceDock.items,
                targetItems: targetDock.items,
                reason: .duplicateItem(existingItemID: duplicate.id)
            )
        }

        var sourceItems = sourceDock.items
        var targetItems = targetDock.items

        switch operation {
        case .move:
            sourceItems.remove(at: sourceIndex)
            targetItems.insert(sourceItem, at: insertionIndex)
            return DockItemTransferPlan(
                sourceItems: sourceItems,
                targetItems: targetItems,
                outcome: .moved(itemID: sourceItem.id)
            )

        case .copy:
            let copiedItem = copyWithFreshIdentity(
                sourceItem,
                avoiding: sourceDock.items + targetDock.items
            )
            targetItems.insert(copiedItem, at: insertionIndex)
            return DockItemTransferPlan(
                sourceItems: sourceItems,
                targetItems: targetItems,
                outcome: .copied(itemID: copiedItem.id)
            )
        }
    }

    private static func planWithinDock(
        sourceIndex: Int,
        items: [DockItem],
        destination: DockItemTransferDestination
    ) -> DockItemTransferPlan {
        guard let targetIndex = insertionIndex(
            for: destination,
            in: items
        ) else {
            return rejectedPlan(
                sourceItems: items,
                targetItems: items,
                reason: missingTargetReason(for: destination)
            )
        }

        let finalIndex: Int
        switch destination {
        case .item:
            finalIndex = targetIndex
        case .trash:
            preconditionFailure("Trash removal is planned before reordering")
        case .trailing:
            finalIndex = items.index(before: items.endIndex)
        }

        guard sourceIndex != finalIndex else {
            return DockItemTransferPlan(
                sourceItems: items,
                targetItems: items,
                outcome: .unchanged
            )
        }

        // Option only changes the operation between docks. Within one dock it
        // keeps the familiar reorder behavior instead of creating duplicates.
        var reorderedItems = items
        let movedItem = reorderedItems.remove(at: sourceIndex)
        reorderedItems.insert(
            movedItem,
            at: min(finalIndex, reorderedItems.endIndex)
        )
        return DockItemTransferPlan(
            sourceItems: reorderedItems,
            targetItems: reorderedItems,
            outcome: .moved(itemID: movedItem.id)
        )
    }

    private static func insertionIndex(
        for destination: DockItemTransferDestination,
        in items: [DockItem]
    ) -> Int? {
        switch destination {
        case let .item(targetItemID):
            return items.firstIndex { $0.id == targetItemID }
        case .trash:
            return nil
        case .trailing:
            return items.endIndex
        }
    }

    private static func missingTargetReason(
        for destination: DockItemTransferDestination
    ) -> DockItemTransferRejection {
        switch destination {
        case let .item(targetItemID):
            return .targetItemNotFound(targetItemID)
        case let .trash(targetItemID):
            return .invalidTrashTarget(targetItemID)
        case .trailing:
            preconditionFailure("A trailing destination always has an index")
        }
    }

    private static func duplicate(
        of item: DockItem,
        in items: [DockItem],
        operation: DockItemTransferOperation,
        downloadsURL: URL?
    ) -> DockItem? {
        if operation == .move,
           let identicalItem = items.first(where: { $0.id == item.id })
        {
            return identicalItem
        }

        guard let identity = contentIdentity(
            for: item,
            downloadsURL: downloadsURL
        ) else {
            return nil
        }
        return items.first {
            contentIdentity(
                for: $0,
                downloadsURL: downloadsURL
            ) == identity
        }
    }

    private static func contentIdentity(
        for item: DockItem,
        downloadsURL: URL?
    ) -> DockItemContentIdentity? {
        if item.kind == .trash {
            return .trash
        }
        if let source = item.smartStackSource {
            if source == .downloads, let downloadsURL {
                return .file(pathIdentity(for: downloadsURL))
            }
            return .smartStack(source)
        }
        if let url = item.fileURL {
            return .file(pathIdentity(for: url))
        }
        return nil
    }

    private static func pathIdentity(for url: URL) -> String {
        url.standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    private static func resolvedDownloadsURL(_ override: URL?) -> URL? {
        override?.standardizedFileURL
            ?? FileManager.default.urls(
                for: .downloadsDirectory,
                in: .userDomainMask
            ).first?.standardizedFileURL
    }

    private static func copyWithFreshIdentity(
        _ item: DockItem,
        avoiding existingItems: [DockItem]
    ) -> DockItem {
        let existingIDs = Set(existingItems.map(\.id))
        var copiedItem = item
        repeat {
            copiedItem.id = UUID()
        } while existingIDs.contains(copiedItem.id)
        return copiedItem
    }

    private static func rejectedPlan(
        sourceItems: [DockItem],
        targetItems: [DockItem],
        reason: DockItemTransferRejection
    ) -> DockItemTransferPlan {
        DockItemTransferPlan(
            sourceItems: sourceItems,
            targetItems: targetItems,
            outcome: .rejected(reason)
        )
    }
}

private enum DockItemContentIdentity: Equatable {
    case file(String)
    case smartStack(SmartStackSource)
    case trash
}

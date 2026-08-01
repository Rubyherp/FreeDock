import Foundation
import Testing
@testable import FreeDock

@Suite("Dock item transfer planner")
struct DockItemTransferPlannerTests {
    @Test("Cross-dock moves default to retaining identity and metadata")
    func crossDockMove() throws {
        let options = FolderStackOptions(
            presentation: .grid,
            sortOrder: .dateModified,
            showHiddenFiles: true
        )
        let before = DockItem.document(
            at: URL(fileURLWithPath: "/tmp/Before.txt")
        )
        let transferred = DockItem(
            kind: .folder,
            path: "/tmp/Project",
            label: "Custom Project",
            folderOptions: options
        )
        let after = DockItem.document(
            at: URL(fileURLWithPath: "/tmp/After.txt")
        )
        let source = DockConfig(
            name: "Source",
            items: [.separator(), transferred]
        )
        let target = DockConfig(
            name: "Target",
            items: [before, after]
        )

        let plan = DockItemTransferPlanner.planTransfer(
            itemID: transferred.id,
            from: source,
            to: target,
            destination: .item(after.id)
        )

        #expect(plan.sourceItems == [source.items[0]])
        #expect(plan.targetItems == [before, transferred, after])
        #expect(plan.outcome == .moved(itemID: transferred.id))
        #expect(plan.didTransfer)
    }

    @Test("Option-copy appends an exact value copy with a fresh identity")
    func crossDockCopy() throws {
        let options = FolderStackOptions(
            presentation: .list,
            sortOrder: .recentlyOpened,
            showHiddenFiles: true
        )
        let transferred = DockItem.smartStack(
            .recentFiles,
            label: "My Recents",
            options: options
        )
        let source = DockConfig(name: "Source", items: [transferred])
        let target = DockConfig(name: "Target", items: [.separator()])

        let plan = DockItemTransferPlanner.planTransfer(
            itemID: transferred.id,
            from: source,
            to: target,
            operation: .copy,
            destination: .trailing
        )
        let copied = try #require(plan.targetItems.last)

        #expect(plan.sourceItems == source.items)
        #expect(plan.targetItems.dropLast() == target.items[...])
        #expect(copied.id != transferred.id)
        var expectedCopy = transferred
        expectedCopy.id = copied.id
        #expect(copied == expectedCopy)
        #expect(plan.outcome == .copied(itemID: copied.id))
        #expect(plan.didTransfer)
    }

    @Test("Logical duplicates reject atomically instead of losing source metadata")
    func duplicateMoveRejected() {
        let sourceItem = DockItem(
            kind: .application,
            path: "/Applications/Example.app",
            label: "Source Name"
        )
        let existing = DockItem(
            kind: .application,
            path: "/Applications/Example.app",
            label: "Target Name"
        )
        let source = DockConfig(name: "Source", items: [sourceItem])
        let target = DockConfig(name: "Target", items: [existing])

        let plan = DockItemTransferPlanner.planTransfer(
            itemID: sourceItem.id,
            from: source,
            to: target
        )

        #expect(plan.sourceItems == source.items)
        #expect(plan.targetItems == target.items)
        #expect(
            plan.outcome
                == .rejected(.duplicateItem(existingItemID: existing.id))
        )
        #expect(!plan.didTransfer)
    }

    @Test("Smart-stack duplicates reject copies while separators stay repeatable")
    func semanticDuplicateRules() throws {
        let stack = DockItem.recentFilesStack(label: "Source Recents")
        let existingStack = DockItem.recentFilesStack(label: "Target Recents")
        let source = DockConfig(
            name: "Source",
            items: [stack, .separator()]
        )
        let target = DockConfig(name: "Target", items: [existingStack])

        let rejected = DockItemTransferPlanner.planTransfer(
            itemID: stack.id,
            from: source,
            to: target,
            operation: .copy
        )
        #expect(
            rejected.outcome
                == .rejected(
                    .duplicateItem(existingItemID: existingStack.id)
                )
        )

        let separator = source.items[1]
        let copiedSeparator = DockItemTransferPlanner.planTransfer(
            itemID: separator.id,
            from: source,
            to: target,
            operation: .copy
        )
        let appended = try #require(copiedSeparator.targetItems.last)
        #expect(appended.kind == .separator)
        #expect(appended.id != separator.id)
        #expect(copiedSeparator.didTransfer)
    }

    @Test("Same-dock forward and backward moves retain target-slot behavior")
    func sameDockTargetSlotReorder() {
        let first = DockItem(appPath: "/Applications/First.app")
        let second = DockItem(appPath: "/Applications/Second.app")
        let third = DockItem(appPath: "/Applications/Third.app")
        let fourth = DockItem(appPath: "/Applications/Fourth.app")
        let dock = DockConfig(
            name: "One Dock",
            items: [first, second, third, fourth]
        )

        let forward = DockItemTransferPlanner.planTransfer(
            itemID: first.id,
            from: dock,
            to: dock,
            destination: .item(third.id)
        )
        #expect(forward.sourceItems == [second, third, first, fourth])
        #expect(forward.targetItems == forward.sourceItems)

        let backward = DockItemTransferPlanner.planTransfer(
            itemID: fourth.id,
            from: dock,
            to: dock,
            destination: .item(second.id)
        )
        #expect(backward.sourceItems == [first, fourth, second, third])
        #expect(backward.targetItems == backward.sourceItems)
    }

    @Test("Same-dock trailing moves and self-drops avoid regressions")
    func sameDockTrailingAndUnchanged() {
        let first = DockItem(appPath: "/Applications/First.app")
        let second = DockItem(appPath: "/Applications/Second.app")
        let third = DockItem(appPath: "/Applications/Third.app")
        let dock = DockConfig(
            name: "One Dock",
            items: [first, second, third]
        )

        let trailing = DockItemTransferPlanner.planTransfer(
            itemID: first.id,
            from: dock,
            to: dock
        )
        #expect(trailing.sourceItems == [second, third, first])
        #expect(trailing.outcome == .moved(itemID: first.id))

        let selfDrop = DockItemTransferPlanner.planTransfer(
            itemID: second.id,
            from: dock,
            to: dock,
            destination: .item(second.id)
        )
        #expect(selfDrop.sourceItems == dock.items)
        #expect(selfDrop.targetItems == dock.items)
        #expect(selfDrop.outcome == .unchanged)

        let optionReorder = DockItemTransferPlanner.planTransfer(
            itemID: first.id,
            from: dock,
            to: dock,
            operation: .copy,
            destination: .item(third.id)
        )
        #expect(optionReorder.sourceItems == [second, third, first])
        #expect(optionReorder.outcome == .moved(itemID: first.id))
    }

    @Test("Dropping a pinned item on Trash removes only the pinned item")
    func sameDockTrashRemoval() {
        let app = DockItem(appPath: "/Applications/Example.app")
        let trash = DockItem.trash()
        let dock = DockConfig(name: "Dock", items: [app, trash])

        let plan = DockItemTransferPlanner.planTransfer(
            itemID: app.id,
            from: dock,
            to: dock,
            destination: .trash(trash.id)
        )

        #expect(plan.sourceItems == [trash])
        #expect(plan.targetItems == [trash])
        #expect(plan.outcome == .removed(itemID: app.id))
        #expect(plan.didTransfer)
    }

    @Test("Cross-dock Trash removal leaves the target dock unchanged")
    func crossDockTrashRemoval() {
        let document = DockItem.document(
            at: URL(fileURLWithPath: "/tmp/Document.pdf")
        )
        let source = DockConfig(name: "Source", items: [document])
        let trash = DockItem.trash()
        let target = DockConfig(name: "Target", items: [trash])

        let plan = DockItemTransferPlanner.planTransfer(
            itemID: document.id,
            from: source,
            to: target,
            operation: .copy,
            destination: .trash(trash.id)
        )

        #expect(plan.sourceItems.isEmpty)
        #expect(plan.targetItems == target.items)
        #expect(plan.outcome == .removed(itemID: document.id))
    }

    @Test("Trash removal rejects invalid targets and the Trash itself")
    func invalidTrashRemoval() {
        let app = DockItem(appPath: "/Applications/Example.app")
        let trash = DockItem.trash()
        let dock = DockConfig(name: "Dock", items: [app, trash])
        let missingID = UUID()

        let missing = DockItemTransferPlanner.planTransfer(
            itemID: app.id,
            from: dock,
            to: dock,
            destination: .trash(missingID)
        )
        let selfRemoval = DockItemTransferPlanner.planTransfer(
            itemID: trash.id,
            from: dock,
            to: dock,
            destination: .trash(trash.id)
        )

        #expect(missing.outcome == .rejected(.invalidTrashTarget(missingID)))
        #expect(selfRemoval.outcome == .rejected(.cannotRemoveTrash))
        #expect(missing.sourceItems == dock.items)
        #expect(selfRemoval.sourceItems == dock.items)
    }

    @Test("Downloads stacks and the real Downloads folder conflict")
    func downloadsIdentityConflict() {
        let downloadsURL = URL(fileURLWithPath: "/tmp/FreeDock Downloads")
        let stack = DockItem.downloadsStack()
        let folder = DockItem.folder(at: downloadsURL)

        let stackToFolder = DockItemTransferPlanner.planTransfer(
            itemID: stack.id,
            from: DockConfig(name: "Source", items: [stack]),
            to: DockConfig(name: "Target", items: [folder]),
            downloadsURL: downloadsURL
        )
        #expect(
            stackToFolder.outcome
                == .rejected(.duplicateItem(existingItemID: folder.id))
        )

        let folderToStack = DockItemTransferPlanner.planTransfer(
            itemID: folder.id,
            from: DockConfig(name: "Source", items: [folder]),
            to: DockConfig(name: "Target", items: [stack]),
            downloadsURL: downloadsURL
        )
        #expect(
            folderToStack.outcome
                == .rejected(.duplicateItem(existingItemID: stack.id))
        )
    }

    @Test("Missing targets and inconsistent same-dock snapshots are rejected")
    func invalidRequestsRejected() {
        let item = DockItem(appPath: "/Applications/Example.app")
        let source = DockConfig(name: "Source", items: [item])
        let target = DockConfig(name: "Target")
        let missingID = UUID()

        let missingTarget = DockItemTransferPlanner.planTransfer(
            itemID: item.id,
            from: source,
            to: target,
            destination: .item(missingID)
        )
        #expect(
            missingTarget.outcome
                == .rejected(.targetItemNotFound(missingID))
        )

        var staleSnapshot = source
        staleSnapshot.items = []
        let inconsistent = DockItemTransferPlanner.planTransfer(
            itemID: item.id,
            from: source,
            to: staleSnapshot
        )
        #expect(
            inconsistent.outcome
                == .rejected(.inconsistentSameDockItems)
        )
    }
}

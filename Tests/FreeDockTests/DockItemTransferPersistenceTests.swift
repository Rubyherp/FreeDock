import Foundation
import Testing
@testable import FreeDock

@Suite("Dock item transfer persistence")
struct DockItemTransferPersistenceTests {
    @Test("Cross-dock move persists in the active profile only")
    func movePersistsInActiveProfile() throws {
        let retainedItem = DockItem.document(
            at: URL(fileURLWithPath: "/tmp/FreeDock Retained.txt")
        )
        let transferredItem = DockItem(
            kind: .folder,
            path: "/tmp/FreeDock Project",
            label: "Open-source Project",
            folderOptions: FolderStackOptions(
                presentation: .grid,
                sortOrder: .dateModified,
                showHiddenFiles: true
            )
        )
        let targetItem = DockItem(
            kind: .application,
            path: "/Applications/Target.app",
            label: "Target"
        )
        let sourceDock = DockConfig(
            name: "Active Source",
            orientation: .vertical,
            iconSize: 54,
            items: [retainedItem, transferredItem]
        )
        let targetDock = DockConfig(
            name: "Active Target",
            iconSize: 62,
            items: [targetItem]
        )
        let activeProfile = DockProfile(
            name: "Active",
            docks: [sourceDock, targetDock]
        )
        let inactiveProfile = inactiveFixtureProfile()
        let originalConfig = AppConfig(
            profiles: [activeProfile, inactiveProfile],
            activeProfileID: activeProfile.id
        )

        let (updatedConfig, plan) = try applyingTransfer(
            to: originalConfig,
            itemID: transferredItem.id,
            sourceDockID: sourceDock.id,
            targetDockID: targetDock.id,
            operation: .move
        )
        let reloaded = try saveAndReload(updatedConfig)

        #expect(plan.outcome == .moved(itemID: transferredItem.id))
        #expect(reloaded.activeProfileID == activeProfile.id)
        let reloadedActive = try #require(
            reloaded.profiles.first { $0.id == activeProfile.id }
        )
        let reloadedSource = try #require(
            reloadedActive.docks.first { $0.id == sourceDock.id }
        )
        let reloadedTarget = try #require(
            reloadedActive.docks.first { $0.id == targetDock.id }
        )
        #expect(reloadedSource.items == [retainedItem])
        #expect(reloadedTarget.items == [targetItem, transferredItem])
        #expect(reloadedSource.settings == sourceDock.settings)
        #expect(reloadedTarget.settings == targetDock.settings)
        #expect(
            reloaded.profiles.first { $0.id == inactiveProfile.id }
                == inactiveProfile
        )
    }

    @Test("Option-copy persists fresh identity and complete item metadata")
    func copyPersistsFreshIdentityAndMetadata() throws {
        let transferredItem = DockItem.smartStack(
            .recentFiles,
            label: "Everything I Opened",
            options: FolderStackOptions(
                presentation: .list,
                sortOrder: .recentlyOpened,
                showHiddenFiles: true
            )
        )
        let targetItem = DockItem.separator()
        let sourceDock = DockConfig(
            name: "Active Source",
            items: [transferredItem]
        )
        let targetDock = DockConfig(
            name: "Active Target",
            items: [targetItem]
        )
        let activeProfile = DockProfile(
            name: "Active",
            docks: [sourceDock, targetDock]
        )
        let inactiveProfile = inactiveFixtureProfile()
        let originalConfig = AppConfig(
            profiles: [inactiveProfile, activeProfile],
            activeProfileID: activeProfile.id
        )

        let (updatedConfig, plan) = try applyingTransfer(
            to: originalConfig,
            itemID: transferredItem.id,
            sourceDockID: sourceDock.id,
            targetDockID: targetDock.id,
            operation: .copy
        )
        let copiedItem = try #require(plan.targetItems.last)
        let reloaded = try saveAndReload(updatedConfig)
        let reloadedActive = try #require(
            reloaded.profiles.first { $0.id == activeProfile.id }
        )
        let reloadedSource = try #require(
            reloadedActive.docks.first { $0.id == sourceDock.id }
        )
        let reloadedTarget = try #require(
            reloadedActive.docks.first { $0.id == targetDock.id }
        )

        #expect(copiedItem.id != transferredItem.id)
        var expectedCopy = transferredItem
        expectedCopy.id = copiedItem.id
        #expect(copiedItem == expectedCopy)
        #expect(plan.outcome == .copied(itemID: copiedItem.id))
        #expect(reloadedSource.items == sourceDock.items)
        #expect(reloadedTarget.items == [targetItem, expectedCopy])
        #expect(
            reloaded.profiles.first { $0.id == inactiveProfile.id }
                == inactiveProfile
        )
    }

    @Test("Canonical paths reject a symlink duplicate atomically")
    func symlinkDuplicateIsRejected() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freedock-transfer-symlink-\(UUID().uuidString)"
            )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let realFolder = temporaryDirectory.appendingPathComponent("Real")
        let linkedFolder = temporaryDirectory.appendingPathComponent("Alias")
        try FileManager.default.createDirectory(
            at: realFolder,
            withIntermediateDirectories: false
        )
        try FileManager.default.createSymbolicLink(
            at: linkedFolder,
            withDestinationURL: realFolder
        )

        let sourceItem = DockItem.folder(at: linkedFolder)
        let targetItem = DockItem.folder(at: realFolder)
        let sourceDock = DockConfig(
            name: "Source",
            items: [sourceItem]
        )
        let targetDock = DockConfig(
            name: "Target",
            items: [targetItem]
        )

        let plan = DockItemTransferPlanner.planTransfer(
            itemID: sourceItem.id,
            from: sourceDock,
            to: targetDock
        )

        #expect(
            plan.outcome
                == .rejected(
                    .duplicateItem(existingItemID: targetItem.id)
                )
        )
        #expect(plan.sourceItems == sourceDock.items)
        #expect(plan.targetItems == targetDock.items)
    }

    private func applyingTransfer(
        to config: AppConfig,
        itemID: UUID,
        sourceDockID: UUID,
        targetDockID: UUID,
        operation: DockItemTransferOperation
    ) throws -> (AppConfig, DockItemTransferPlan) {
        var updatedConfig = config
        var activeDocks = updatedConfig.docks
        guard let sourceIndex = activeDocks.firstIndex(where: {
            $0.id == sourceDockID
        }) else {
            throw TransferFixtureError.missingSourceDock
        }
        guard let targetIndex = activeDocks.firstIndex(where: {
            $0.id == targetDockID
        }) else {
            throw TransferFixtureError.missingTargetDock
        }

        let plan = DockItemTransferPlanner.planTransfer(
            itemID: itemID,
            from: activeDocks[sourceIndex],
            to: activeDocks[targetIndex],
            operation: operation
        )
        guard plan.didTransfer else {
            throw TransferFixtureError.transferRejected
        }

        activeDocks[sourceIndex].items = plan.sourceItems
        activeDocks[targetIndex].items = plan.targetItems
        updatedConfig.docks = activeDocks
        return (updatedConfig, plan)
    }

    private func saveAndReload(_ config: AppConfig) throws -> AppConfig {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freedock-transfer-persistence-\(UUID().uuidString)"
            )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let configPath = temporaryDirectory.appendingPathComponent(
            "freedock.json"
        )
        let manager = ConfigManager(configPath: configPath)
        manager.config = config
        manager.saveImmediately()

        let reloadedManager = ConfigManager(configPath: configPath)
        guard reloadedManager.loadedFromDisk else {
            throw TransferFixtureError.configDidNotReload
        }
        return reloadedManager.config
    }

    private func inactiveFixtureProfile() -> DockProfile {
        DockProfile(
            name: "Inactive",
            docks: [
                DockConfig(
                    name: "Inactive Dock",
                    orientation: .vertical,
                    iconSize: 41,
                    items: [
                        DockItem(
                            kind: .application,
                            path: "/Applications/Inactive.app",
                            label: "Leave Me Alone"
                        ),
                        DockItem.downloadsStack(
                            label: "Inactive Downloads"
                        ),
                    ]
                ),
            ]
        )
    }
}

private enum TransferFixtureError: Error {
    case missingSourceDock
    case missingTargetDock
    case transferRejected
    case configDidNotReload
}

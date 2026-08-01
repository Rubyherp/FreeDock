import Foundation

struct DockItemAdditionPlan: Equatable, Sendable {
    let items: [DockItem]
    let addedCount: Int
    let skippedCount: Int
}

enum DockItemPlanner {
    static func planAddingTrash(
        to existingItems: [DockItem]
    ) -> DockItemAdditionPlan {
        guard !existingItems.contains(where: { $0.kind == .trash }) else {
            return DockItemAdditionPlan(
                items: existingItems,
                addedCount: 0,
                skippedCount: 1
            )
        }
        return DockItemAdditionPlan(
            items: existingItems + [.trash()],
            addedCount: 1,
            skippedCount: 0
        )
    }

    /// Produces one ordered update, preserving Finder's URL order and removing aliases
    /// or repeated paths that resolve to an item already in the dock.
    static func planAdding(
        urls: [URL],
        to existingItems: [DockItem],
        downloadsURL: URL? = nil
    ) -> DockItemAdditionPlan {
        var items = existingItems
        var seenPaths = Set(
            existingItems.compactMap { item in
                item.fileURL.map(pathIdentity(for:))
            }
        )
        if existingItems.contains(where: {
            $0.smartStackSource == .downloads
        }),
        let resolvedDownloadsURL = resolvedDownloadsURL(downloadsURL)
        {
            seenPaths.insert(pathIdentity(for: resolvedDownloadsURL))
        }
        var addedCount = 0
        var skippedCount = 0

        for url in urls {
            guard let item = DockItem.pinnedItem(at: url),
                  let itemURL = item.fileURL
            else {
                skippedCount += 1
                continue
            }

            let identity = pathIdentity(for: itemURL)
            guard seenPaths.insert(identity).inserted else {
                skippedCount += 1
                continue
            }

            items.append(item)
            addedCount += 1
        }

        return DockItemAdditionPlan(
            items: items,
            addedCount: addedCount,
            skippedCount: skippedCount
        )
    }

    static func planAdding(
        smartStack source: SmartStackSource,
        to existingItems: [DockItem],
        downloadsURL: URL? = nil
    ) -> DockItemAdditionPlan {
        let hasSameSource = existingItems.contains {
            $0.smartStackSource == source
        }
        let duplicatesDownloadsFolder: Bool
        if source == .downloads,
           let resolvedDownloadsURL = resolvedDownloadsURL(downloadsURL)
        {
            let downloadsIdentity = pathIdentity(for: resolvedDownloadsURL)
            duplicatesDownloadsFolder = existingItems.contains { item in
                item.smartStackSource == nil
                    && item.kind == .folder
                    && item.fileURL.map(pathIdentity(for:))
                        == downloadsIdentity
            }
        } else {
            duplicatesDownloadsFolder = false
        }

        guard !hasSameSource, !duplicatesDownloadsFolder else {
            return DockItemAdditionPlan(
                items: existingItems,
                addedCount: 0,
                skippedCount: 1
            )
        }

        return DockItemAdditionPlan(
            items: existingItems + [.smartStack(source)],
            addedCount: 1,
            skippedCount: 0
        )
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
}

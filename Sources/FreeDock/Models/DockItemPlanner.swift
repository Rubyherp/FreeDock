import Foundation

struct DockItemAdditionPlan: Equatable, Sendable {
    let items: [DockItem]
    let addedCount: Int
    let skippedCount: Int
}

enum DockItemPlanner {
    /// Produces one ordered update, preserving Finder's URL order and removing aliases
    /// or repeated paths that resolve to an item already in the dock.
    static func planAdding(
        urls: [URL],
        to existingItems: [DockItem]
    ) -> DockItemAdditionPlan {
        var items = existingItems
        var seenPaths = Set(
            existingItems.compactMap { item in
                item.fileURL.map(pathIdentity(for:))
            }
        )
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

    private static func pathIdentity(for url: URL) -> String {
        url.standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}
